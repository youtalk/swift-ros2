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
}
