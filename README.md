# MacDirStat ✺

A warm, hand-drawn take on WinDirStat for macOS. It gives you a directory tree, a file-type legend and a treemap of your disk, drawn with ivory paper, clay-orange ink and pencil hatching.

## Build & run

Needs macOS 14+ and the Swift toolchain (Xcode Command Line Tools is enough).

```bash
./Scripts/build-app.sh          # → build/MacDirStat.app (release, ad-hoc signed, with icon)
open build/MacDirStat.app
open build/MacDirStat.app --args --scan ~/Downloads   # start mapping straight away
```

Copy `build/MacDirStat.app` into `/Applications` if you want to keep it. For a complete map of Macintosh HD,
grant it **Full Disk Access** (System Settings › Privacy & Security). Otherwise a few protected folders are
counted as "kept their secrets".

## What's inside

- **Fast scanning**: `getattrlistbulk(2)` feeds a pool of worker threads, and hard links are only counted once.
  Sizes are bytes allocated on disk and match `du`. On an M-series Mac, about 3M files are scanned in roughly 30s.
- **The Tree**: an `NSOutlineView` with hatched share bars, sortable columns, and ⌘⌫ to trash.
- **The Map**: a squarified treemap. The layout is computed on the main thread and only goes as deep as there
  are pixels to show; the pixel shading runs on background threads.
  - *Sketchbook*: flat gouache tiles, pencil hatching, and wobbly pen outlines around folders.
  - *Cushions*: classic van Wijk cushion shading, like the original WinDirStat.
  - Hand-lettered tags on the big folders (⌘L to toggle).
- **File Types**: click an extension to outline every matching file on the map.
- **Four papers**: Ivory, Oat, Clay and Slate (dark), switched with ⌘1–⌘4.

| Action | How |
|---|---|
| Select | click a tile or a row |
| Dive into a folder | double-click, or ⌘↓ |
| Zoom out / to the top | ⌘↑ / ⇧⌘↑, or the breadcrumbs |
| Reveal / Copy path / Trash | right-click, ⌥⌘F, ⇧⌘C, ⌘⌫ |
| Rescan | ⌘R (or right-click › Rescan This Folder) |

## Layout

```
Sources/MacDirStat/
  Model/      FileNode, DiskScanner (getattrlistbulk), ExtensionRegistry
  Treemap/    TreemapLayout (squarify + cushions), TreemapRenderer (pixels + sketch), TreemapView (NSView)
  Views/      SwiftUI shell, DirectoryOutline (NSOutlineView), welcome/scanning screens
  Support/    Theme palettes, Sketch (rough.js-style wobbly paths), formatting & whimsy
Scripts/      build-app.sh, make-icon.swift
```
