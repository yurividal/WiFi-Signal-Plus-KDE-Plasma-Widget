# WiFi Signal Plus — KDE Plasma Widget

A vibe-coded KDE Plasma 6 port of the GNOME Shell extension
[WiFi Signal Plus](https://github.com/JalilArfaoui/gnome-extension-wifi-signal-plus)
by Jalil Arfaoui. The goal is to replicate the original as faithfully as possible.

## What it does

Shows the **WiFi generation** (4 / 5 / 6 / 6E / 7) of your active connection as a
small icon in the panel. Click it to open a popup with:

- **Speed** — current TX/RX bitrate and the AP's advertised maximum
- **Channel** — frequency, band, and channel number
- **Channel width** — in MHz
- **Modulation** — MCS index, spatial streams (MIMO), and guard interval
- **Signal** — quality bar, dBm value, and a rolling signal history graph
- **BSSID** — MAC address of the connected access point
- **Access Points** — all BSSIDs for your current network, with signal/security/channel
- **Nearby Networks** — other SSIDs visible to NetworkManager

## Screenshots

_TODO_

## Requirements

| Dependency | Package (Arch/Manjaro) |
|---|---|
| KDE Plasma 6.0+ | `plasma-desktop` |
| Python 3 + dbus bindings | `python-dbus` |
| `iw` | `iw` |
| NetworkManager | `networkmanager` |

## Installation

### From source

```bash
git clone https://github.com/YOUR_USERNAME/plasma-widget-wifi-signal-plus
cd plasma-widget-wifi-signal-plus
./install.sh          # or manually:
kpackagetool6 --install . --type Plasma/Applet
```

Then right-click the panel → **Add Widgets** → search for **WiFi Signal Plus**.

### Manual copy

```bash
cp -r . ~/.local/share/plasma/plasmoids/wifi-signal-plus/
```

Log out and back in (or run `plasmashell --replace &`) for Plasma to pick it up.

## Configuration

Right-click the widget → **Configure WiFi Signal Plus…**

| Setting | Default | Description |
|---|---|---|
| Tray icon size | 16 px | Width of the panel icon slot (system tray standard is 22 px) |

## How it works

- **Generation detection** — parses `iw dev <iface> link` output; logic is a direct
  port of the TypeScript in the original GNOME extension (`wifiGeneration.ts` →
  `contents/js/wifiGeneration.js`).
- **Access point data** — a small Python script (`contents/scripts/nm_aps.py`) queries
  NetworkManager over D-Bus (`GetAllAccessPoints`) for per-AP details (frequency,
  bandwidth, max bitrate, signal strength, security flags). No `nmcli` parsing.
- **Nearby network scan** — runs `iw dev <iface> scan dump` to read the kernel's
  cached scan results without triggering a new scan.

## Project structure

```
metadata.json
contents/
  config/
    main.xml            KConfig XT schema (user settings)
    config.qml          Settings page registry
  icons/
    wifi-4.png … wifi-7.png   Generation badge icons (from original extension)
    wifi-1.svg … wifi-3.svg
  js/
    wifiGeneration.js   Ported parser (iw link / iw scan dump)
  scripts/
    nm_aps.py           NM D-Bus AP scanner
  ui/
    main.qml            Root PlasmoidItem, data sources, compact representation
    FullRepresentation.qml  Popup panel UI
    configGeneral.qml   Settings page UI
```

## Credits

- Original GNOME extension and all icons: [Jalil Arfaoui](https://github.com/JalilArfaoui/gnome-extension-wifi-signal-plus)
- KDE port: vibe-coded with GitHub Copilot

## License

GPL-2.0-or-later (same as the original extension)
