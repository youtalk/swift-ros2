import Foundation

/// One periodic sample taken during a soak run.
public struct SoakSample: Equatable, Sendable {
    public let tSeconds: Double
    public let rssBytes: UInt64
    public let openFDs: Int
    public let msgsPerSec: Double

    public init(tSeconds: Double, rssBytes: UInt64, openFDs: Int, msgsPerSec: Double) {
        self.tSeconds = tSeconds
        self.rssBytes = rssBytes
        self.openFDs = openFDs
        self.msgsPerSec = msgsPerSec
    }
}

/// The leak/health verdict for a completed soak run.
public struct SoakVerdict: Equatable, Sendable {
    public let leakSuspected: Bool
    public let rssSlopeBytesPerMin: Double
    public let fdGrowth: Int
    public let throughputDegradationPct: Double
    public let summary: String
}

/// Pure analysis of a soak time-series. No I/O — unit-tested in normal CI.
public enum SoakAnalysis {
    /// `leakSuspected` if any of: RSS least-squares slope exceeds
    /// `rssSlopeLimitBytesPerMin`; net FD growth (last − first) exceeds
    /// `fdGrowthLimit`; or throughput degradation (first-fifth vs last-fifth
    /// mean) exceeds `throughputDegradationLimitPct`. The trend axes (RSS slope,
    /// throughput) need at least `minSamplesForTrend` samples to be meaningful
    /// and to outlast process-startup warmup; below that they are reported as 0
    /// (inconclusive) so a short probe cannot false-flag. FD growth is robust at
    /// any count. Fewer than 2 samples is fully inconclusive (not a leak).
    public static func analyze(
        _ samples: [SoakSample],
        rssSlopeLimitBytesPerMin: Double = 1_000_000,
        fdGrowthLimit: Int = 8,
        throughputDegradationLimitPct: Double = 20,
        minSamplesForTrend: Int = 10
    ) -> SoakVerdict {
        guard samples.count >= 2 else {
            return SoakVerdict(
                leakSuspected: false, rssSlopeBytesPerMin: 0, fdGrowth: 0,
                throughputDegradationPct: 0, summary: "inconclusive: <2 samples")
        }

        // FD growth (net last − first) is robust even with a couple of samples;
        // a transient spike that recovers nets to 0.
        let fdGrowth = samples[samples.count - 1].openFDs - samples[0].openFDs

        // Trend axes need enough points to outlast startup warmup and to give
        // the first/last fifths ≥2 points each.
        var rssSlopeBytesPerMin = 0.0
        var throughputDegradationPct = 0.0
        if samples.count >= minSamplesForTrend {
            let n = Double(samples.count)
            let xs = samples.map { $0.tSeconds }
            let ys = samples.map { Double($0.rssBytes) }
            let meanX = xs.reduce(0, +) / n
            let meanY = ys.reduce(0, +) / n
            var num = 0.0
            var den = 0.0
            for i in 0..<samples.count {
                num += (xs[i] - meanX) * (ys[i] - meanY)
                den += (xs[i] - meanX) * (xs[i] - meanX)
            }
            rssSlopeBytesPerMin = (den == 0 ? 0 : num / den) * 60

            let fifth = samples.count / 5  // ≥2 here, so the slices are non-empty
            func mean(_ s: ArraySlice<SoakSample>) -> Double {
                s.map { $0.msgsPerSec }.reduce(0, +) / Double(s.count)
            }
            let firstMean = mean(samples.prefix(fifth))
            let lastMean = mean(samples.suffix(fifth))
            throughputDegradationPct =
                firstMean <= 0 ? 0 : max(0, (firstMean - lastMean) / firstMean * 100)
        }

        let leakSuspected =
            rssSlopeBytesPerMin > rssSlopeLimitBytesPerMin
            || fdGrowth > fdGrowthLimit
            || throughputDegradationPct > throughputDegradationLimitPct

        let summary =
            "rss_slope=\(Int(rssSlopeBytesPerMin.rounded())) B/min, fd_growth=\(fdGrowth), "
            + "tput_degradation=\(String(format: "%.1f", throughputDegradationPct))% -> "
            + (leakSuspected ? "LEAK SUSPECTED" : "healthy")

        return SoakVerdict(
            leakSuspected: leakSuspected, rssSlopeBytesPerMin: rssSlopeBytesPerMin,
            fdGrowth: fdGrowth, throughputDegradationPct: throughputDegradationPct,
            summary: summary)
    }

    /// Receive-side echo continuity for an `--expect-echo` soak run.
    ///
    /// Given the per-sample receive rates (the `recv_per_s` series), returns
    /// the length of the longest run of consecutive zero-recv samples and
    /// whether delivery recovered after stalling. `recoveredAfterZeroRecv` is
    /// true iff the series contains at least one zero sample and does not end
    /// in one (delivery resumed after the last stall). A series with no zero
    /// samples reports `(0, false)` — there was nothing to recover from. An
    /// empty series reports `(0, false)`.
    public static func echoContinuity(
        recvPerSecond: [Double]
    ) -> (maxConsecutiveZeroRecvSamples: Int, recoveredAfterZeroRecv: Bool) {
        echoContinuity(recvPerSecond: recvPerSecond, stallThreshold: 0, excludeWarmup: false)
    }

    /// Threshold-aware echo continuity.
    ///
    /// A sample counts as stalled iff its rate is `<= stallThreshold` — a
    /// strict `== 0` check misses partial outages (a router restart that
    /// drops delivery to a fraction of the target rate within one sample
    /// window is a real stall the zero-only check reports as clean). With
    /// `excludeWarmup`, leading stalled samples before the first healthy one
    /// are skipped: an `--expect-echo` run whose relay/subscription match
    /// completes after the first window would otherwise report a phantom
    /// stall. `recoveredAfterZeroRecv` is true iff at least one (post-warmup)
    /// stall run exists and the series ends healthy. Caveat: a series that
    /// never delivers is consumed entirely by warmup exclusion and reports
    /// clean — callers must also check the total received count (the soak
    /// RESULT line carries `received=` for exactly this reason).
    public static func echoContinuity(
        recvPerSecond: [Double],
        stallThreshold: Double,
        excludeWarmup: Bool
    ) -> (maxConsecutiveZeroRecvSamples: Int, recoveredAfterZeroRecv: Bool) {
        var series = recvPerSecond[...]
        if excludeWarmup {
            series = series.drop(while: { $0 <= stallThreshold })
        }
        var maxRun = 0
        var run = 0
        for value in series {
            if value <= stallThreshold {
                run += 1
                maxRun = max(maxRun, run)
            } else {
                run = 0
            }
        }
        // run == 0 here means the series does not end in a stalled sample.
        return (maxRun, maxRun > 0 && run == 0)
    }
}
