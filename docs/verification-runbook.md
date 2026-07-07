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

## W4 results summary (4/4 axes — W5 input)

Axes 1–3 run on native macOS arm64 (Apple Silicon), `SWIFT_ROS2_ENABLE_RCL=1`,
Release, LAN host = Jazzy + CycloneDDS over domain 0; Axis 4 on a physical
iPhone 15 Pro (M3d). Matrix after the W4 stack + the M3d resource run:
**47 pass / 73 n-a / 0 fail / 0 pending** (pending-free — all four axes recorded).

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
- **Resource (Axis 4) — PASS.** iPhone 15 Pro, two signed Release builds (`.dds`
  baseline vs `SWIFT_ROS2_ENABLE_RCL=1` `.rcl`), camera + LiDAR load, 5 min each
  (`xctrace` Activity Monitor, per-process): CPU mean RCL 78.7 % vs DDS 78.6 %
  (≈ identical); physical-footprint RCL 304 MiB vs DDS 334 MiB (RCL lower); thermal
  RCL `Fair` vs DDS `Nominal` (both below `serious`/`critical` — the one-level delta
  tracks cumulative session heat, since CPU load is identical); device arm64 Release
  binary delta **+1.43 MiB** (≤ +2 MiB); battery drain comparable (~3–4 %/5 min).
  RCL's on-device cost is on par with the pure-Swift DDS path. **Caveat (bug):** the
  RCL run had to use *multicast* discovery — RCL with **unicast peers** fails
  `rmw_create_node` on iOS because the exported `CYCLONEDDS_URI` carries
  `<EnableTopicDiscoveryEndpoints>` (emitted by `CDDSBridge/dds_bridge.c` for the
  unicast-peers case), which the CycloneDDS bundled in `CRos2Jazzy.xcframework`
  rejects as an unknown element. The standalone `CCycloneDDS.xcframework` used by
  the pure-Swift DDS path accepts it, so the same shared discovery XML is valid for
  one CycloneDDS build and not the other. The bug does not affect the measured
  resource cost, but it does block RCL on Conduit's real unicast-on-Wi-Fi path;
  tracked separately.

Verdict for W5: across all four axes the RCL backend is real-time-adequate, stable,
byte-correct, and resource-on-par with the pure-Swift path for Conduit-class loads.
The one open risk is operational rather than performance: RCL's **unicast** discovery
path is currently broken on iOS (the `EnableTopicDiscoveryEndpoints` config bug
above), so RCL is not yet usable for Conduit's real on-device scenario (Wi-Fi, where
multicast is blocked) until that is fixed.

## Out of scope

- **Axis 4 (resource: binary-size / CPU / battery on a real iPhone)** is
  Conduit-side (needs the Conduit repo + a physical device); recorded in the W4
  summary above via the M3d run, no longer pending.
- **DDS unicast on the RCL backend** is supported via `.rclUnicast` (peers +
  optional interface exported as `CYCLONEDDS_URI`) on macOS/LAN; on **iOS** it is
  currently broken — the exported XML's `<EnableTopicDiscoveryEndpoints>` element
  is rejected by the CycloneDDS bundled in `CRos2Jazzy.xcframework` (see the Axis 4
  caveat above). LAN runs can use multicast (RCL), `.rclUnicast` (RCL, macOS), or
  the pure-Swift `.ddsUnicast` path.

## MZ3 — zenoh-rmw variant (RCL-over-Zenoh)

The MZ arc re-runs the four axes with `.zenoh(locator:)` routed through
`rcl + rmw_zenoh_cpp + zenoh-c` (`SWIFT_ROS2_RCL_RMW=zenoh`). Everything below
was measured with a local `rmw_zenohd` router in Docker
(`conduit/support/docker`, `ros_jazzy_zenoh`, rmw_zenoh 0.2.9) because the LAN
Jazzy host was unavailable — repeat the latency/correctness axes against a
native LAN host when it returns.

### Build (per-variant scratch paths are mandatory)

```bash
# The zenoh variant; NEVER share .build between variants (stale-manifest graph).
SWIFT_ROS2_ENABLE_RCL=1 SWIFT_ROS2_RCL_RMW=zenoh swift build --scratch-path .build-zenoh
```

### Router + environment

```bash
# Router (domain 0!): conduit/support/docker/.env pins ROS_DOMAIN_ID=123 — override:
( cd <conduit>/support/docker && ROS_DOMAIN_ID=0 docker compose up -d --force-recreate ros-jazzy )

# Until the AMENT synthesis (#155) is in your build, export the mini prefix:
export AMENT_PREFIX_PATH=<repo>/build/ros2zenoh/ament-prefix
export RMW_IMPLEMENTATION=rmw_zenoh_cpp
```

### Axis 1 — latency

```bash
# In-process publish-call + roundtrip, and the relay-based LAN mode.
# rcl-bench defaults to --domain 42; the router container is domain 0.
.build-zenoh/debug/rcl-bench zenoh publish   imu       --count 3000 --rate-hz 100 --domain 0 --locator tcp/127.0.0.1:7447
.build-zenoh/debug/rcl-bench zenoh roundtrip cloud120k --count 3000 --rate-hz 100 --domain 0 --locator tcp/127.0.0.1:7447
# roundtrip-lan needs a relay on the host side; topic_tools relay LOCKS its
# type at subscribe time — restart it between payload types:
docker exec -d ros_jazzy_zenoh bash -c "source /opt/ros/jazzy/setup.bash && \
  export RMW_IMPLEMENTATION=rmw_zenoh_cpp ROS_DOMAIN_ID=0 && \
  ros2 run topic_tools relay /rcl_bench/bench /rcl_bench/bench_echo"
.build-zenoh/debug/rcl-bench zenoh roundtrip-lan image64k --count 2000 --rate-hz 100 --domain 0 --locator tcp/127.0.0.1:7447
```

### Axis 2 — soak

```bash
# Two concurrent 8 h runs on different ROS domains share one router cleanly:
.build-zenoh/debug/rcl-soak zenoh cloud120k --duration-s 28800 --sample-s 30 --rate-hz 100 --domain 0 --locator tcp/127.0.0.1:7447 --expect-echo
.build-zenoh/debug/rcl-soak zenoh image64k  --duration-s 28800 --sample-s 30 --rate-hz 100 --domain 1 --locator tcp/127.0.0.1:7447 --expect-echo
# (one relay per domain, as above, on /rcl_soak/soak -> /rcl_soak/soak_echo)
# Fault run: shorter soak + `docker restart ros_jazzy_zenoh` mid-run +
# --inject-malformed; recovery shows up as recv_zero_run_max > 0 with
# recv_recovered=true in the RESULT line.
```

### Axis 3 — correctness

```bash
# Field-level agreement with a real Jazzy subscriber (echo decodes the fields):
docker exec ros_jazzy_zenoh bash -c "source /opt/ros/jazzy/setup.bash && \
  export RMW_IMPLEMENTATION=rmw_zenoh_cpp && ros2 topic echo /rcl_soak/soak --once --no-arr"
# Type-hash: ros2 topic info <topic> --verbose  (RIHS01 must be accepted)
# Behavioral parity on rmw_zenoh (all three green on the zenoh variant):
.build-zenoh/debug/crcl-loopback && .build-zenoh/debug/crcl-svc-loopback && .build-zenoh/debug/crcl-action-loopback
```

### Recording convention (MZ3)

Zenoh-variant results go on the `transport.zenoh` row (flip its `na` axis
cells) — never overwrite the corpus rows' W4 cyclonedds values. The resource
axis stays with the MZ4 iPhone batch.
