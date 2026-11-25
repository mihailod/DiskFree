# DiskFree

A tiny macOS menu bar app that shows how many gigabytes are free on your startup disk, and optionally how much space swap, junk and Claude are taking up.

```
74GB • Swap 2.1GB  Junk 0.2GB  Claude 2.2GB
```

## Free space

The number is the same figure Finder shows, so it includes space macOS can reclaim on its own. It refreshes every second by default (adjustable under **Refresh Every**) and when the Mac wakes. Its color tells you whether a macOS upgrade still fits:

| Color | Free space | On a 256 GB drive |
|---|---|---|
| red | under 30 GB: a macOS upgrade won't fit | under 30 GB |
| orange | under 30 GB + 1/8 of the drive: the upgrade fits, but would leave the drive over 7/8 full | 30–61 GB |
| green | above that | 62 GB and up |

30 GB is Apple's ~25 GB upgrade requirement plus some margin. The drive size is its marketed size (256 GB, 512 GB, 1 TB…), since macOS reports a bit less.

## Swap, Junk and Claude

Turn these on with **Show Swap**, **Show Junk** and **Show Claude**. They appear after the free space in the menu bar, and the menu always shows them at the top.

- **Swap**: the size of the swap files on disk. Rebooting deletes them. Orange from 1/8 of your RAM, red from 1/4 (2 GB and 4 GB with 16 GB of RAM).
- **Junk**: space that's safe to delete, grouped like the Disk Diet app: Caches, Logs, Temporary Files and Trash. The menu shows the breakdown. Orange from 1/128 of the drive, red from 1/64 (2 GB and 4 GB on a 256 GB drive). Each category has a **Delete** submenu that asks first, then permanently deletes what's inside the folders (never the folders themselves):
  - **Caches**: everything in `~/Library/Caches` except the privacy-protected folders below. Apps rebuild what they need.
  - **Logs**: only your own `~/Library/Logs`. System logs belong to root and stay.
  - **Temporary Files**: only items unchanged for a day, since running apps may still be using newer ones.
  - **Trash**: same as Empty Trash in Finder. Only offered when DiskFree can read the Trash.
- **Claude**: everything the Claude desktop app, Claude Code and Cowork keep on disk: `~/.claude`, `~/.claude.json`, `~/Library/Application Support/Claude`, Claude's caches, logs and HTTP storage, and `~/Claude`. The menu shows the breakdown. It's Claude's orange (a deeper shade on a light menu bar, so it stays readable), and turns red when the desktop app has kept old versions of Claude Code, the coding agent it downloads for Code sessions (numbered 2.1.x, separately from the app itself). **Old Claude Code ▸ Delete** in the menu deletes them. It asks first, and keeps any version a running Claude session still uses. The menu lists them under Old Claude Code, and Claude's local virtual machine images (`vm_bundles`, `claude-code-vm`) under VM Bundles. VM bundles don't turn it red, since some developers use them on purpose. If neither the app nor any of these folders is on the Mac, the menu says Claude (Not installed). Claude's caches also count toward Junk.

Junk and Claude are re-measured every 30 seconds and whenever you open the menu. If a measurement takes long because the folders hold many files, it waits at least 100× that long before the next one, so it never uses more than about 1% of the Mac's time.

Below orange, Swap and Junk use the same green (or system color) as the free space.

Junk leaves out a few things on purpose:

- **Trash** is only counted if you give DiskFree Full Disk Access (System Settings → Privacy & Security). macOS keeps every other app out of it.
- **Privacy-protected caches** (Apple Music, TV, Safari, CloudKit) are skipped. Just opening them makes macOS ask for permission.
- **Unused app languages** aren't counted. Deleting them breaks the apps' code signatures.

## Menu

- **Swap**, **Junk** and **Claude**: current sizes, with the Junk and Claude breakdowns, including old Claude Code versions and VM bundles
- **Refresh Now**: re-read everything now
- **Refresh Every**: 1, 5 or 10 seconds for free space and swap
- **Show GB**: `74GB` instead of `74`, for every number
- **Show Swap**, **Show Junk**, **Show Claude**: add them to the menu bar
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
