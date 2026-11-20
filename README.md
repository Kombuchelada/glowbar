<p align="center">
  <img src="docs/images/icon.png" width="128" height="128" alt="Glowbar app icon">
</p>

<h1 align="center">Glowbar</h1>

<p align="center">
  <b>Control the RGB lighting on GIGABYTE AORUS monitors from macOS.</b><br>
  A native menu bar app for the monitor's LED light bar: a Mac alternative to the lighting page of GIGABYTE Control Center, which only runs on Windows.
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/panel-dark.png">
    <img src="docs/images/panel-light.png" width="320" alt="Glowbar menu bar panel showing 16 lighting effects, color swatches, a hue strip, and speed and brightness sliders">
  </picture>
</p>

GIGABYTE doesn't make a Mac version of GIGABYTE Control Center (GCC), RGB Fusion or OSD
Sidekick, so on a Mac there's no way to change the LED lighting on an AORUS FO32U2P or a
similar AORUS FO-series OLED monitor. Glowbar talks to the monitor's lighting controller
directly over USB.

## Features

- **All 16 lighting effects built into the monitor**: Static, Pulse, Flash, Double Flash,
  Color Cycle, Scanner, Expand, Wave, Star Slide, Meteor, Shaking, Recover, Double Meteor,
  Color Stack, Color Rain and Off
- **Color, speed and brightness** controls that turn on only for effects that use them
- **Lives in the menu bar**: no Dock icon or window, optional Open at Login
- **Changes apply instantly**, your last settings are remembered, and they are sent again
  whenever the monitor reconnects (the light bar forgets them when the monitor cuts its power)
- **Command-line tool** (`glowbar`) for scripts, Shortcuts and automation
- **Home Assistant** support over MQTT: the light bar shows up as a light, and it goes
  unavailable on its own when you unplug your laptop or close the lid
- Native Swift and SwiftUI, universal (Apple silicon and Intel), about 1 MB, no drivers or
  kernel extensions, no network access unless you turn on Home Assistant

## Supported monitors

| Monitor | Status |
| --- | --- |
| AORUS FO32U2P | ✅ Tested: all 16 effects work |
| Other AORUS FO-series monitors | Probably. Glowbar checks the monitor's firmware and only sends commands if it uses the FO-series command set |
| AORUS monitors with older lighting firmware | ❌ Not yet. They use a different command set; Glowbar detects this and sends nothing |

If you have another AORUS monitor, run `glowbar info` (it only reads from the monitor) and
[open a compatibility report](../../issues/new?template=monitor-report.yml).

## Requirements

- macOS 14 Sonoma or later
- **The monitor's USB upstream cable (USB-C or USB-B) connected to the Mac.** The lighting
  controller is a USB device inside the monitor, so a video cable alone isn't enough. If you
  use the monitor's built-in KVM, the active USB upstream port has to be the one going to the Mac.

## Install

### Homebrew

```sh
brew install --cask kombuchelada/tap/glowbar
```

This installs Glowbar.app and puts the `glowbar` CLI on your PATH.

### Download

Download `Glowbar-<version>.pkg` from [Releases](../../releases) and open it. The installer
puts Glowbar in Applications, links the `glowbar` CLI into `/usr/local/bin`, and starts the app.

Prefer not to use an installer? Download `Glowbar-<version>.zip` instead, unzip it, and move
**Glowbar.app** to Applications.

Releases, including the installer, are signed with a Developer ID and notarized by Apple, so
they open like any other download.

To uninstall, quit Glowbar and move it to the Trash. If you used the installer, also run:

```sh
sudo rm /usr/local/bin/glowbar
sudo pkgutil --forget io.github.kombuchelada.glowbar.pkg
```

### Build from source

Requires Xcode 16 or later, or just the Xcode Command Line Tools.

```sh
git clone https://github.com/Kombuchelada/glowbar.git
cd glowbar
./scripts/build-app.sh --install   # builds build/Glowbar.app and copies it to ~/Applications
```

## Usage

Click the light-strip icon in the menu bar. Pick an effect, then adjust color, speed and
brightness; the monitor updates as you go. **↻** sends the current settings again (useful
after the monitor was power-cycled or switched KVM inputs).

### Command line

The app bundle includes a small CLI. Homebrew installs put it on your PATH as `glowbar`;
otherwise it's at `/Applications/Glowbar.app/Contents/Resources/glowbar`.

```sh
cli=glowbar
$cli list                                   # find the lighting controller (no USB traffic)
$cli info                                   # firmware version and FO-series check (read-only)
$cli effects                                # list effect names
$cli set staticColor --color FF4200 --brightness 10
$cli set rainbowWave --speed 4
$cli set off
```

Speed is 1–6 and brightness is 1–10.

### Home Assistant

Glowbar can add the light bar to [Home Assistant](https://www.home-assistant.io) through MQTT
discovery, so you can control it from dashboards and automations.

1. In Home Assistant, set up the [MQTT integration](https://www.home-assistant.io/integrations/mqtt/)
   if you haven't already (the Mosquitto broker add-on is the easiest way).
2. In Glowbar's panel, click the **house** button, turn on **Connect to Home Assistant**, enter
   the broker's host, port and login, and click **Apply**.

A **Glowbar on <your Mac>** device appears with a light (on/off, effect, color, brightness) and a
Speed control. It's made for laptops: when the Mac sleeps, leaves the network, or is unplugged
from the monitor, the light shows as *unavailable* in Home Assistant instead of failing, and
Glowbar reconnects quietly in the background. Changes made while the monitor is unplugged are
applied when you plug it back in. See [docs/HOME_ASSISTANT.md](docs/HOME_ASSISTANT.md) for
topics and details.

## How it works

The monitor's light bar is driven by an ITE USB HID controller (VID `0x048D`, PID `0x8295`)
that takes 64-byte HID feature reports. Each change is an effect report followed by an
"apply" report, which Glowbar sends with IOKit. [docs/PROTOCOL.md](docs/PROTOCOL.md)
describes the commands and every effect's parameters.

The protocol encoder is a small, dependency-free Swift library (`GlowbarKit`) with tests
that pin every report's bytes.

## FAQ

**Does GIGABYTE Control Center work on macOS?**
No. GCC, RGB Fusion and OSD Sidekick are Windows-only. Glowbar covers monitor lighting on Mac.

**Can it change brightness, input, or other OSD settings?**
No, only the LED lighting. Picture settings go through a different interface (DDC/CI).

**Does it need admin rights, a driver or Input Monitoring permission?**
No. macOS lets apps open vendor-specific USB HID devices like this one without extra permissions.

**Is this safe for my monitor?**
It sends only standard lighting commands, and it refuses to send anything if the firmware
isn't the FO-series type it expects. Still, this is an unofficial tool, so use it at your own risk.

**Why do some effects ignore my color?**
Scanner, Expand, Wave, Color Cycle, Recover, Color Stack and Color Rain use colors built into
the monitor's firmware.

## Development

```sh
swift build
swift test
```

| Path | What it is |
| --- | --- |
| `Sources/GlowbarKit` | Protocol encoder (`LightingProtocol.swift`), IOKit HID transport (`MonitorLighting.swift`), and the Home Assistant MQTT bridge (`HomeAssistant.swift`, `MQTTClient.swift`, `MQTTPacket.swift`) |
| `Sources/GlowbarApp` | SwiftUI menu bar app |
| `Sources/glowbar` | CLI |
| `Tests/GlowbarKitTests` | Byte-level tests for every report, MQTT packets and Home Assistant messages |

### Releases

Releases are signed with Developer ID Application and Developer ID Installer certificates
and notarized. With both certificates in your keychain and notarization credentials saved via
`xcrun notarytool store-credentials <profile>`:

```sh
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
INSTALLER_IDENTITY="Developer ID Installer: Your Name (TEAMID)" \
NOTARY_PROFILE=<profile> ./scripts/build-app.sh --notarize --pkg
```

This builds, signs the app and the CLI with the hardened runtime, notarizes, staples the
ticket and writes `build/Glowbar-<version>.zip`, printing the values for the Homebrew cask.
`--pkg` also wraps the app in `build/Glowbar-<version>.pkg` with `scripts/make-pkg.sh`,
notarized and stapled too. The installer always installs into `/Applications`, for all users,
then links the CLI into `/usr/local/bin` (never replacing an unrelated file there) and opens
Glowbar for the user at the screen (`Resources/pkg/postinstall`). Attach both files to the
GitHub release.

Contributions are welcome, especially compatibility reports and support for more AORUS monitors.

## Disclaimer

Glowbar is an independent project. It isn't affiliated with, endorsed by or supported by
GIGABYTE Technology Co., Ltd. GIGABYTE, AORUS and GIGABYTE Control Center are trademarks of
their owners and are used here only to describe compatibility.

## License

[MIT](LICENSE)
