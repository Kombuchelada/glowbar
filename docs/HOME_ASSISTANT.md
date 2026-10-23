# Home Assistant

Glowbar publishes the light bar to Home Assistant with
[MQTT discovery](https://www.home-assistant.io/integrations/mqtt/#mqtt-discovery). It needs an
MQTT broker that Home Assistant also uses, such as the Mosquitto broker add-on. Glowbar has its
own small MQTT 3.1.1 client, so there's nothing else to install on the Mac.

## Setup

Click the **house** button in Glowbar's panel to open the settings:

| Setting | Notes |
| --- | --- |
| Host, Port | The broker, for example `homeassistant.local` and `1883` |
| Use TLS | For brokers with a certificate trusted by macOS (usually port `8883`) |
| Username, Password | The broker login. The password is stored in your login keychain |
| Discovery prefix | `homeassistant` unless you changed it in Home Assistant's MQTT settings |

## Entities

Each Mac gets its own device, **Glowbar on <Mac name>**:

- **Light** (JSON schema): on/off, RGB color, brightness (10 levels) and every effect except
  Off. Turning the light off selects Glowbar's Off effect. Turning it on again restores the last
  effect. Picking a color while the effect uses the monitor's built-in colors (Wave, Scanner and
  so on) switches to Static, so the color shows up.
- **Speed** (number, 1–6).

The panel and Home Assistant stay in sync both ways.

## When the Mac or monitor goes away

The light is available only while both of these are `online` (`availability_mode: all`):

| Topic | Goes `offline` when |
| --- | --- |
| `glowbar/<id>/status` | Glowbar quits, the Mac sleeps or leaves the network (MQTT last will), or the connection is turned off |
| `glowbar/<id>/monitor` | The monitor's USB upstream cable is unplugged |

While unavailable, Home Assistant shows the light as *unavailable* rather than off. If the broker
can't be reached, Glowbar retries in the background (immediately when the network changes, then
backing off to once a minute). It doesn't show alerts, and the panel keeps working as usual.
Lighting changes made while the monitor is unplugged are saved and sent when it's plugged in again.

## Topics

`<id>` is a random identifier created once per Mac.

| Topic | Direction | Payload |
| --- | --- | --- |
| `homeassistant/light/glowbar_<id>/light/config` | Glowbar → HA | Light discovery (retained) |
| `homeassistant/number/glowbar_<id>/speed/config` | Glowbar → HA | Speed discovery (retained) |
| `glowbar/<id>/state` | Glowbar → HA | `{"state":"ON","effect":"Pulse","brightness":7,"color_mode":"rgb","color":{"r":255,"g":66,"b":0},"speed":3}` (retained) |
| `glowbar/<id>/set` | HA → Glowbar | JSON light command: `state`, `effect`, `brightness` (1–10), `color` |
| `glowbar/<id>/speed/set` | HA → Glowbar | `1`–`6` |
| `glowbar/<id>/status`, `glowbar/<id>/monitor` | Glowbar → HA | `online` / `offline` (retained) |
| `homeassistant/status` | HA → Glowbar | On `online`, Glowbar publishes discovery and state again |

To remove the device from Home Assistant, turn off the connection in Glowbar, then delete the
device on the MQTT integration page.
