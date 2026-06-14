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
is multicast — the `transport.dds` unicast-config gap means `ddsUnicastPeers`
is ignored on the RCL backend, so the LAN must carry multicast):

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

## Out of scope

- **Axis 4 (resource: binary-size / CPU / battery on a real iPhone)** is
  Conduit-side (needs the Conduit repo + a physical device + the
  `conduit-run-on-iphone` / `oslog-stream-to-file` skills), tracked separately.
- **DDS unicast on the RCL backend** is blocked by the `transport.dds` matrix
  gap; LAN runs use multicast (RCL) or the pure-Swift `.ddsUnicast` path.
