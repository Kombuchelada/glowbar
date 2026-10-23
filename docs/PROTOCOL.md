# FO-series monitor lighting protocol

How Glowbar talks to the RGB lighting controller in GIGABYTE AORUS FO-series monitors.
`Sources/GlowbarKit/LightingProtocol.swift` has the exact per-effect values, and
`Tests/GlowbarKitTests` pins them.

## Device

- USB HID, VID `0x048D` (ITE), PID `0x8295`, usage page `0xFF89` (vendor-defined).
- All traffic is 64-byte **feature** reports with report ID `0xCC` in byte 0.
- The controller sits behind the monitor's USB upstream port, so it's only visible when the
  monitor's USB-C or USB-B upstream cable goes to the computer.

## Commands (`report[1]`)

| Byte | Meaning | Payload |
| --- | --- | --- |
| `0x60` | Query info | none; then read the 64-byte info reply with GetFeature |
| `0x20`, `0x21` | Effect for zone 0 / zone 1 | 32-byte parameter block at `report[2]` |
| `0x28` | Apply latched effects | `report[2]` = zone bit mask (`3`) |
| `0x32` | Host-streamed strip control | `report[2]` = enable bits (`0` = off) |

### Info reply

| Offset | Field |
| --- | --- |
| 0 | report ID |
| 1 | product |
| 2 | device number |
| 3 | strip detect |
| 4–7 | firmware version (little-endian) |
| 12–39 | product string |
| 40–55 | calibration |
| 56–59 | chip ID |

The controller takes the FO-series command set when `fw[2] == 4 || fw[0] == 1`. Glowbar
sends nothing to controllers that don't match.

### Effect parameter block (32 bytes, little-endian)

| Offset | Field |
| --- | --- |
| 0 | zone select 0, u32: always `0xFFFFFFFE` on FO series (so `report[2]` = `0xFE`) |
| 4 | zone select 1, u32: always `0x1FF` on FO series |
| 8 | reserved |
| 9 | mode |
| 10 / 11 | max / min brightness (%) |
| 12 / 16 | color 0 / color 1 (`0x00RRGGBB`) |
| 20, 22, 24, 26 | time 0–3, u16 (ms) |
| 28, 29, 30, 31 | control 0, control 1, option 0, option 1 |

FO-series monitors always use command `0x21`.

### Session sequence

1. `CC 60`, then GetFeature (identify, check the firmware)
2. `CC 20 01 …zeros`, then `CC 28 03` (reset)
3. `CC 32 00` (turn off host-streamed strip mode; first effect only)
4. `CC 21 <effect>`, then `CC 28 03` for every change

### Effects

Brightness levels 1–10 map to `{15,20,30,40,50,60,70,80,90,100}` %. Speed levels 1–6
select from per-effect timing tables (slowest to fastest).

| Effect | Mode | Notes |
| --- | --- | --- |
| Static | 1 | brightness |
| Pulse | 2 | max 100 % |
| Flash | 3 | option 0 = 1 |
| Double Flash | 3 | option 0 = 2 |
| Color Cycle | 4 | control 0 = 7 (rainbow) |
| Scanner | 19 | firmware colors; a block slides back and forth over a solid bar |
| Expand | 18 | firmware colors; a block grows from the center and shrinks back |
| Wave | 6 | control 0 = 7 (rainbow); color 1 = `0xF000` |
| Star Slide | 5 | chosen color |
| Meteor | 11 | chosen color |
| Shaking | 12 | chosen color; option 0 = 1 |
| Recover | 13 | rainbow; option 0 = 1 |
| Double Meteor | 14 | chosen color |
| Color Stack | 15 | rainbow; option 0 = 2 |
| Color Rain | 16 | rainbow; control 0 = 7, option 0 = 1 |
| Off | 1 | color 0, max 100 % |
