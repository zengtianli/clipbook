# Clip

[中文](README.md) | **English**



**Quick access. A lighter footprint.** A keyboard-friendly, local clipboard library.

[Product page and real demo](https://app-mac-clips.tianli.cyou/) · [Measured comparison and limitations](promotion/COMPARISON.md)

<!-- lightweight:start -->
## Lightweight (measured)

| Download | Idle memory | Idle CPU | Cold launch to window |
|---|---|---|---|
| **2.0 MB** (installed 3.6 MB) | **53 MB** | **0.1%** | **1.2 s** |

Native SwiftUI/AppKit with no third-party dependencies; history is stored with the system SQLite. Every 0.25 s it only compares the pasteboard change counter; images are decoded at preview size with a 48-image cache, and hiding the main window unloads the interface.

<sub>v1.1 (36) · Mac16,12 / Apple M4 / macOS 27.2 · measured 2026-09-26. Memory is phys_footprint (the Memory column in Activity Monitor); CPU is CPU time ÷ wall time over 60 idle seconds; sizes in decimal MB. Raw data: [perf/lightweight.json](perf/lightweight.json).</sub>
<!-- lightweight:end -->

In a controlled image-browsing test, Clip's own physical footprint dropped from 275.5 to 117.3 MiB (about 57%, build 26). This is a before/after result, not a Deck memory benchmark. Matched latency testing is still pending.

A native Swift clipboard library for macOS. A menu-bar icon opens the three-column interface: filter, select and edit. Custom shortcuts are unassigned by default. Standard Command-C copies selected text, or all selected records when there is no text selection. Multiple text records are joined in display order with blank lines; files and images retain native pasteboard payloads. Every action offers application-only or global scope under Settings → Shortcuts. Global actions use the selection retained in Clip. Clear a custom binding to unregister it immediately. Conflicts and registration failures are shown; no fallback combination is chosen automatically.

Capture text, rich text, links, images and files; deduplicate content, pin entries, organize collections, edit and merge text. Local data stays in `~/Library/Application Support/Clipbook/`. The existing bundle ID and `clipbook://show`, `hide`, `toggle`, `settings` URLs remain compatible.

Link-title fetching and iCloud archiving are optional network features. Link responses are streamed and cancelled at 256 KiB, even when a server ignores the Range header. Automatic paste needs macOS Accessibility permission.

To receive Mac clipboard history on iPhone, use the same Apple account with iCloud Drive enabled on both devices. Enable **Settings → iCloud → iCloud 历史归档** on Mac and **Settings → iCloud 同步 → 同步 Clip 历史** in iPhone Clip. Keep Mac Clip running: the archive initially adds the latest 500 items, then newly copied text, links, and images. Find an item in iPhone Clip, open it and tap Copy, then paste into another app. Keep both apps open during the first check and wait for the sync status to update. Receiving history does not replace the phone's system clipboard. File paths are excluded and rich text becomes plain text. Local Mac cleanup does not delete the separate cloud archive. App Store and TestFlight iPhone builds use Production, so the Mac build must target the matching CloudKit environment. Sync is off by default; the measurements above are with sync off, and enabling it adds to them.

## Build and verify

Use `open -g -a Clip --args --background` to start capture and sync without opening the main window; the menu bar or Dock can still open it. Release builds target CloudKit Production to match App Store/TestFlight. The original development archive remains intact; production uses a separate cache and seeds the latest 500 records from local history.

`bash build.sh --build-only` compiles and runs the production self-test without installing. `bash build.sh` installs the catalog's display name into `/Applications`. The build reuses the headquarters Xcode selector, CodingKey checker and icon converter. It preserves the Apple Development signing identity when available.

`build/Clipbook --selftest` exercises the real store, importer, classifier and watcher with isolated fixtures. `bash tests/test-link-title.sh` verifies bounded HTTP fetching against a local server that ignores Range.

General preferences persist without leaving Settings open. Retention runs on the next capture; deletion requires confirmation, and login-item failures or pending approval are visible. Installation does not forcibly kill a running instance. `CLIPBOOK_HOME` and `CLIPBOOK_PREFERENCES_SUITE` provide isolated UI-test storage; a custom home never automatically imports Deck data.
