import SwiftROS2Bench
import XCTest

final class SoakAnalysisTests: XCTestCase {
    /// Build a time series: `count` samples at `interval` seconds, RSS starting
    /// at `rss0` growing `rssPerSample` bytes each step, FDs starting at `fd0`
    /// growing `fdPerSample`, throughput `tput` scaled linearly to `tputEndScale`
    /// across the run to model degradation.
    private func series(
        count: Int, interval: Double = 1, rss0: UInt64 = 100_000_000,
        rssPerSample: Int = 0, fd0: Int = 20, fdPerSample: Int = 0,
        tput: Double = 1000, tputEndScale: Double = 1
    ) -> [SoakSample] {
        (0..<count).map { i in
            let frac = count > 1 ? Double(i) / Double(count - 1) : 0
            let scale = 1 + (tputEndScale - 1) * frac
            return SoakSample(
                tSeconds: Double(i) * interval,
                rssBytes: UInt64(Int64(rss0) + Int64(rssPerSample) * Int64(i)),
                openFDs: fd0 + fdPerSample * i,
                msgsPerSec: tput * scale)
        }
    }

    func testFlatSeriesIsHealthy() {
        let v = SoakAnalysis.analyze(series(count: 600))
        XCTAssertFalse(v.leakSuspected)
        XCTAssertLessThan(abs(v.rssSlopeBytesPerMin), 1.0)
        XCTAssertEqual(v.fdGrowth, 0)
        XCTAssertLessThan(v.throughputDegradationPct, 1.0)
    }

    func testRisingRSSFlagsLeak() {
        let v = SoakAnalysis.analyze(series(count: 600, rssPerSample: 200_000))
        XCTAssertTrue(v.leakSuspected)
        XCTAssertGreaterThan(v.rssSlopeBytesPerMin, 1_000_000)
    }

    func testGrowingFDsFlagsLeak() {
        let v = SoakAnalysis.analyze(series(count: 60, fdPerSample: 1))
        XCTAssertTrue(v.leakSuspected)
        XCTAssertEqual(v.fdGrowth, 59)
    }

    func testThroughputDegradationFlagged() {
        let v = SoakAnalysis.analyze(series(count: 600, tputEndScale: 0.5))
        XCTAssertTrue(v.leakSuspected)
        XCTAssertGreaterThan(v.throughputDegradationPct, 20)
    }

    func testEmptyOrSingleSampleIsInconclusiveNotALeak() {
        XCTAssertFalse(SoakAnalysis.analyze([]).leakSuspected)
        XCTAssertFalse(SoakAnalysis.analyze(series(count: 1)).leakSuspected)
    }

    func testAllEqualTimestampsGivesZeroSlopeNotALeak() {
        // interval 0 → every tSeconds is 0 (den == 0). Even with rising RSS the
        // slope guard yields 0, so the RSS axis must not false-flag.
        let v = SoakAnalysis.analyze(series(count: 60, interval: 0, rssPerSample: 200_000))
        XCTAssertEqual(v.rssSlopeBytesPerMin, 0)
        XCTAssertFalse(v.leakSuspected)
    }

    func testTransientFDSpikeThatRecoversIsNotALeak() {
        // FDs spike mid-run then return to baseline: last − first == 0, so the
        // net-growth signal (not max − min) correctly reports no leak.
        let fds = [20, 20, 100, 100, 20, 20]
        let samples = fds.enumerated().map { i, fd in
            SoakSample(tSeconds: Double(i), rssBytes: 100_000_000, openFDs: fd, msgsPerSec: 1000)
        }
        let v = SoakAnalysis.analyze(samples)
        XCTAssertEqual(v.fdGrowth, 0)
        XCTAssertFalse(v.leakSuspected)
    }

    func testShortRunBelowTrendMinimumDoesNotFlagRSS() {
        // 8 samples (< the 10-sample trend minimum) with steep RSS growth:
        // process-startup warmup must not be mistaken for a leak, so the RSS
        // slope is reported as inconclusive (0).
        let v = SoakAnalysis.analyze(series(count: 8, rssPerSample: 5_000_000))
        XCTAssertEqual(v.rssSlopeBytesPerMin, 0)
        XCTAssertFalse(v.leakSuspected)
    }

    // MARK: - echoContinuity (H7 receive-side observability)

    func testEchoContinuityEmptySeries() {
        let r = SoakAnalysis.echoContinuity(recvPerSecond: [])
        XCTAssertEqual(r.maxConsecutiveZeroRecvSamples, 0)
        XCTAssertFalse(r.recoveredAfterZeroRecv)
    }

    func testEchoContinuityAllNonZeroHasNoStall() {
        let r = SoakAnalysis.echoContinuity(recvPerSecond: [100, 99, 101])
        XCTAssertEqual(r.maxConsecutiveZeroRecvSamples, 0)
        // No zero sample means there was nothing to recover from.
        XCTAssertFalse(r.recoveredAfterZeroRecv)
    }

    func testEchoContinuityMidRunStallThatRecovers() {
        let r = SoakAnalysis.echoContinuity(recvPerSecond: [100, 0, 0, 0, 100])
        XCTAssertEqual(r.maxConsecutiveZeroRecvSamples, 3)
        XCTAssertTrue(r.recoveredAfterZeroRecv)
    }

    func testEchoContinuityStallAtEndIsNotRecovered() {
        let r = SoakAnalysis.echoContinuity(recvPerSecond: [100, 100, 0, 0])
        XCTAssertEqual(r.maxConsecutiveZeroRecvSamples, 2)
        XCTAssertFalse(r.recoveredAfterZeroRecv)
    }

    func testEchoContinuityLongestZeroRunWins() {
        let r = SoakAnalysis.echoContinuity(recvPerSecond: [0, 100, 0, 0, 0, 100, 0, 0, 100])
        XCTAssertEqual(r.maxConsecutiveZeroRecvSamples, 3)
        XCTAssertTrue(r.recoveredAfterZeroRecv)
    }

    func testEchoContinuityAllZerosIsNeverRecovered() {
        let r = SoakAnalysis.echoContinuity(recvPerSecond: [0, 0, 0])
        XCTAssertEqual(r.maxConsecutiveZeroRecvSamples, 3)
        XCTAssertFalse(r.recoveredAfterZeroRecv)
    }

    func testEchoContinuitySingleZeroThenRecovery() {
        let r = SoakAnalysis.echoContinuity(recvPerSecond: [0, 100])
        XCTAssertEqual(r.maxConsecutiveZeroRecvSamples, 1)
        XCTAssertTrue(r.recoveredAfterZeroRecv)
    }
}
