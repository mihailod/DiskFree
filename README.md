# DiskFree

A tiny macOS menu bar app that shows how many gigabytes are free on your startup disk, and optionally how much swap and junk are taking up space.

```
74GB • Swap 2.1GB  Junk 0.2GB
```

## Free space

The number is the same figure Finder shows, so it includes space macOS can reclaim on its own. It refreshes every second by default (adjustable under **Refresh Every**) and when the Mac wakes. Its color tells you whether a macOS upgrade still fits:

| Color | Free space | On a 256 GB drive |
|---|---|---|
| red | under 30 GB: a macOS upgrade won't fit | under 30 GB |
| orange | under 30 GB + 1/8 of the drive: the upgrade fits, but would leave the drive over 7/8 full | 30–61 GB |
| green | above that | 62 GB and up |

30 GB is Apple's ~25 GB upgrade requirement plus some margin. The drive size is its marketed size (256 GB, 512 GB, 1 TB…), since macOS reports a bit less.

## Swap and Junk

Turn these on with **Show Swap** and **Show Junk**. They appear after the free space in the menu bar, and the menu always shows them at the top.

- **Swap**: the size of the swap files on disk. Rebooting deletes them. Orange from 1/8 of your RAM, red from 1/4 (2 GB and 4 GB with 16 GB of RAM).
- **Junk**: space that's safe to delete, grouped like the Disk Diet app: Caches, Logs, Temporary Files and Trash. The menu shows the breakdown. Orange from 1/128 of the drive, red from 1/64 (2 GB and 4 GB on a 256 GB drive). It's re-measured every 30 seconds and whenever you open the menu. If a measurement takes long because the caches hold many files, it waits at least 100× that long before the next one, so it never uses more than about 1% of the Mac's time.

Below orange, both use the same green (or system color) as the free space.

Junk leaves out a few things on purpose:

- **Trash** is only counted if you give DiskFree Full Disk Access (System Settings → Privacy & Security). macOS keeps every other app out of it.
- **Privacy-protected caches** (Apple Music, TV, Safari, CloudKit) are skipped. Just opening them makes macOS ask for permission.
- **Unused app languages** aren't counted. Deleting them breaks the apps' code signatures.

## Menu

- **Swap** and **Junk**: current sizes, with the Junk breakdown
- **Refresh Now**: re-read everything now
- **Refresh Every**: 1, 5 or 10 seconds for free space and swap
- **Show GB**: `74GB` instead of `74`, for all three numbers
- **Show Swap**, **Show Junk**: add them to the menu bar
- **Font Size**: Normal (matches other menu bar items), Big, Huge
- **Bold Font**: heavy or regular weight
- **OK Color**: green or the system text color when all is well

Settings are remembered across restarts.

## Build

Apple Silicon only, macOS 13 or later. Needs the Xcode command line tools.

```sh
./build.sh
open DiskFree.app
```

To start it at login, add `DiskFree.app` in System Settings → General → Login Items. To put it first in the menu bar, hold ⌘ and drag it there; macOS remembers the position.

The icon is drawn in code by `make_icon.swift`. Delete `AppIcon.icns` and rebuild to regenerate it.

---

By Mihailo Despotovic, 2026
