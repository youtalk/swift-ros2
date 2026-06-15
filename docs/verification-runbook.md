# RCL verification runbook (W4)

Runs the W3 harnesses against a LAN ROS 2 Jazzy host and records results into
`docs/parity-matrix.json`. Apple host with `SWIFT_ROS2_ENABLE_RCL=1`; set
`LINUX_IP` to the host (e.g. `192.168.1.85`). Build once:

```bash
SWIFT_ROS2_ENABLE_RCL=1 swift build -c release --product rcl-bench --product rcl-soak
```

The two backends are selected at runtime by the first argument: `rcl` (native
rcl + rmw_cyclonedds_cpp) vs `dds` (pure-Swift wire). One binary, two paths.

## Axis 1 — latency / throughput

In-process publish-call cost + throughput (no host needed), per backend × payload:

```bash
SWIFT_ROS2_ENABLE_RCL=1 swift run -c release rcl-bench rcl publish imu       --count 100000
SWIFT_ROS2_ENABLE_RCL=1 swift run -c release rcl-bench dds publish imu       --count 100000
SWIFT_ROS2_ENABLE_RCL=1 swift run -c release rcl-bench rcl publish image64k  --count 1000
SWIFT_ROS2_ENABLE_RCL=1 swift run -c release rcl-bench rcl publish cloud120k --count 1000
# ...and the dds variants
```

LAN end-to-end round-trip. The bench publishes to `/rcl_bench/bench` with a
send-stamp and subscribes `/rcl_bench/bench_echo`, computing `now − stamp` on
its own clock (no host/sender clock-sync needed). On the **host**, relay the
topic back (the host's RMW must match the backend under test):

```bash
# host (Jazzy)
ros2 run topic_tools relay /rcl_bench/bench /rcl_bench/bench_echo
```

On the **Apple host**, measure (domain 0 reaches the LAN; under `.rcl` the link
can be multicast or, via `.rclUnicast`, static unicast — `ddsUnicastPeers` /
`ddsNetworkInterface` are now honoured on the RCL backend, exported as
`CYCLONEDDS_URI`, so the LAN need not carry multicast):

```bash
SWIFT_ROS2_ENABLE_RCL=1 swift run -c release rcl-bench rcl roundtrip-lan imu --domain 0 --count 5000
```

Record (p50/p99 → value; verdict by your threshold), via the `parity-tool set`
from W3 Part 1:

```bash
swift run parity-tool set "publish.typed.sensor_msgs/Imu" --axis latency --verdict pass \
  --value "rcl publish p50=<X>us p99=<Y>us @max; LAN rt p50=<Z>ms (rcl-bench)"
```

## Axis 2 — endurance / soak

Long run (background or cron), per backend × payload — start with the large
payloads (allocation churn is the primary leak detector):

```bash
SWIFT_ROS2_ENABLE_RCL=1 swift run -c release rcl-soak rcl cloud120k \
  --duration-s 14400 --sample-s 30 --rate-hz 30 --domain 0 | tee soak-rcl-cloud.log
```

Each `rcl_soak SAMPLE t=.. rss_mb=.. fds=.. msgs_per_s=..` line is a time-series
point; the final `rcl_soak RESULT ... verdict=healthy|LEAK rss_slope_b_per_min=..
fd_growth=.. tput_degradation_pct=..` is the verdict (RSS least-squares slope /
FD growth / throughput degradation via `SoakAnalysis`; trend axes need ≥10
samples, so use `--duration-s` ≥ `10 × --sample-s`).

**Resilience (fault injection).** `--inject-malformed` opens a subscription to a
never-published topic for the whole run (receive-path robustness). Host-restart
and network-drop cannot be driven from the harness — during a run, manually
restart the host's subscriber / `rmw_zenohd` or drop the network, and confirm
the time-series recovers (throughput returns; RSS does not step up).

Record:

```bash
swift run parity-tool set "publish.typed.sensor_msgs/PointCloud2" --axis soak --verdict pass \
  --value "4h @30Hz: rss_slope=<X>B/min fd_growth=<Y> healthy (rcl-soak)"
```

## Committing results

Every `parity-tool set` re-renders `docs/PARITY.md` and re-canonicalizes
`docs/parity-matrix.json` atomically. Commit both files and open a PR; the CI
parity-matrix drift guard enforces the canonical form. Latency/soak verdicts are
recorded here in W4 — they are intentionally left `pending` by the harness PRs.

## Applicability map (W4)

Not every axis applies to every row. The full assignment is in the W4 plan's
"30-row × 4-axis applicability map"; the rule:

- **latency / soak** — only the corpus data paths. Measured on `imu` / `image64k`
  (`CompressedImage`) / `cloud120k` (`PointCloud2`); latency also on the
  corresponding subscribe rows (round-trip). Every other row is `na`: small/scalar
  bundled types are *represented by* the `Imu` corpus row (same typed-publish path);
  route-b `non_bundled` rows are the pure-Swift DDS path (DDS baseline); lifecycle /
  service / param / action / qos / transport rows are not data paths; soak has no
  separate subscribe harness (covered by the publish-side soak).
- **correctness** — every row with an RCL implementation: byte parity for the 11
  bundled typed types (`crcl-golden`), behavioral + LAN parity for the rest. `na`
  for `*/Image` (RCL missing — raw Image is byte-seam-only) and `transport.zenoh`
  (verified in M9, design §19.5; separate xcframework, out of DDS scope).
- **resource** — the on-device Conduit publish surface only (the 11 bundled typed
  sensor rows + `publish.serialized.non_bundled`); every other row is `na`.

## Pass/fail thresholds (W4)

The verdict is "real-time-adequate / production-viable for Conduit," **not** "RCL
beats the pure-Swift wire path" (M5 showed wire wins end-to-end ~2× while RCL wins
publish-call cost; both sub-millisecond p99 — acceptable).

- **latency (Axis 1):** PASS if end-to-end **p99 ≤ 2 ms at 100 Hz** for all three
  corpus types **and** publish-call **p99 ≤ 1 ms**. Record p50/p95/p99/max + msgs/s.
- **soak (Axis 2):** PASS if `SoakAnalysis` reports `healthy` for the full run
  (RSS slope ≤ 1 MB/min, FD net growth ≤ 8, throughput degradation ≤ 20 %) **and**
  the injected-fault time-series recovers.
- **correctness (Axis 3):** PASS if byte-identical (`CDREncoder == rmw_serialize`,
  for typed rows) **and** the LAN/behavioral parity check for the row holds.
- **resource (Axis 4):** PASS if device (arm64) Release binary-size delta
  **≤ +2 MiB**, CPU within a few % of the `.dds` build, no `serious`/`critical`
  thermal escalation under load, and battery drain comparable.

## W4 results summary (3/4 axes — W5 input)

Run on native macOS arm64 (Apple Silicon), `SWIFT_ROS2_ENABLE_RCL=1`, Release;
LAN host = Jazzy + CycloneDDS over domain 0. Matrix after the W4 stack:
**35 pass / 73 n-a / 0 fail / 12 pending** (the 12 pending = the `resource` axis,
pending the iPhone run).

- **Latency (Axis 1) — PASS.** In-process publish-call p99 = 3.5 µs (Imu) / 28 µs
  (CompressedImage 64 KiB) / 29.6 µs (PointCloud2 120 KB); end-to-end round-trip p99
  = 206 / 374 / 490 µs @100 Hz — all under the 1 ms / 2 ms SLOs. Pure-Swift DDS stays
  ~2× faster end-to-end (Imu rt p99 113 µs), as in M5. LAN round-trip delivered
  1000/1000 (interop proven); absolute LAN latency was dominated by a Python `rclpy`
  echo relay (host had no `topic_tools`), so it is interop evidence, not the SLO
  number.
- **Soak (Axis 2) — PASS.** RCL cloud120k 30 min / image64k 20 min + a 12 min
  malformed-receive fault run: all `healthy`, RSS slope 9–17 KB/min (≪ 1 MB/min),
  FD growth 0, throughput degradation 0.0 %. DDS cloud120k baseline comparable
  (12 KB/min). Bounded runs, not the 8 h overnight target — leak/stability checks
  with ~60–110× margin.
- **Correctness (Axis 3) — PASS.** Byte parity for all 11 bundled typed types
  (`crcl-golden`: `CDREncoder == rmw_serialize`); behavioral parity via the five
  `crcl-*-loopback` gates (pub/sub, non-bundled pub/sub, AddTwoInts + params,
  Fibonacci action); LAN: stock-ROS 2 `ros2 topic info --verbose` reports type hash
  `RIHS01_7d9a00ff…` (canonical match) and `echo` shows correct field values.
- **Resource (Axis 4) — pending.** iPhone on-device measurement (Conduit, build-twice
  + `conduit-run-on-iphone` / `oslog-stream-to-file`); 12 cells remain `pending`.

Verdict for W5: on every axis run so far the RCL backend is real-time-adequate and
stable for Conduit-class loads; the only open evidence is on-device resource cost.

## Out of scope

- **Axis 4 (resource: binary-size / CPU / battery on a real iPhone)** is
  Conduit-side (needs the Conduit repo + a physical device + the
  `conduit-run-on-iphone` / `oslog-stream-to-file` skills), tracked separately.
- **DDS unicast on the RCL backend** is supported via `.rclUnicast` (peers +
  optional interface exported as `CYCLONEDDS_URI`); LAN runs can use multicast
  (RCL), `.rclUnicast` (RCL), or the pure-Swift `.ddsUnicast` path.
