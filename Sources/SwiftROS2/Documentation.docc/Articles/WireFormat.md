# Wire format

What SwiftROS2 puts on the wire to interoperate with `rmw_zenoh_cpp` and
`rmw_cyclonedds_cpp`.

## Zenoh key expression

Format: `<domain>/<namespace>/<topic>/<dds_type_name>/<type_hash>`.

The DDS type name uses the `::msg::dds_::Type_` form (e.g.
`sensor_msgs::msg::dds_::Imu_`). On Humble, the type-hash segment is the
literal `TypeHashNotSupported`. On Jazzy and later, it is the
`RIHS01_<hex>` value or the segment is omitted entirely if no hash is
known.

## Attachment (33 bytes)

Layout (Zenoh `ext::Serializer`):

| Bytes | Meaning |
|---|---|
| 0–7   | seq (Int64, little-endian) |
| 8–15  | timestamp_ns (Int64, little-endian) |
| 16    | `0x10` LEB128 length prefix for the 16-byte GID array |
| 17–32 | publisher GID (16 raw bytes) |

## CDR encoding

XCDR v1, explicit little-endian. Every payload starts with the four-byte
encapsulation header `00 01 00 00`. Fixed-size arrays serialize without a
length prefix; sequences carry a four-byte `uint32` length prefix.

## DDS topic and type names

- Topic: `rt/<topic>` (the `rt/` prefix marks it as a ROS 2 topic).
- Type: same `pkg::msg::dds_::Type_` form as Zenoh.
- Type hash: encoded as USER_DATA `typehash=RIHS01_<hex>;`.
