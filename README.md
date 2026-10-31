# DiskFree

A tiny macOS menu bar app that shows one thing: how many gigabytes are free on your startup disk.

The number changes color as space runs low:

| Free space | Color |
|---|---|
| 50 GB or more | green (or the menu bar's own text color) |
| 30–49 GB | dark gold |
| 10–29 GB | orange |
| under 10 GB | red |

Free space is the same figure Finder shows, so it includes space macOS can reclaim on its own (caches and the like). It refreshes every 30 seconds and when the Mac wakes.

## Menu

- **Refresh**: re-read free space now
- **GB on/off**: show `57GB` instead of `57`
- **Font Size**: Normal (matches other menu bar items), Big, Huge
- **Bold Font**: heavy or regular weight
- **OK Color**: green or the system text color for 50 GB and up

Settings are remembered across restarts.

## Build

Apple Silicon only, macOS 13 or later. Needs the Xcode command line tools.

```sh
./build.sh
open DiskFree.app
```

To start it at login, add `DiskFree.app` in System Settings → General → Login Items.

The icon is drawn in code by `make_icon.swift`. Delete `AppIcon.icns` and rebuild to regenerate it.

---

By Mihailo Despotovic, 2026
