# Clip

The app/status menu includes **Configuration and updates…** for settings export/import and optional iCloud settings sync, off by default. It transfers capture exclusions, retention, plain-text/link-title options, copy sounds and shortcuts. Capture pause, login items and permissions are device-specific. Enable iCloud Drive and settings sync on both Macs using the same Apple account to restore preferences, with backups before changes. Clipboard history retains its existing CloudKit **iCloud history archive** toggle. **Check for updates…** reads the matching cloud/local private release channel.

[中文](README.md) | **English**



**Quick access. A lighter footprint.** A keyboard-friendly, local clipboard library.

[Product page and real demo](https://app-mac-clips.tianli.cyou/) · [Measured comparison and limitations](promotion/COMPARISON.md)

<!-- lightweight:start -->
## Resource use

| Download | Idle memory | Idle CPU | Cold launch to window |
|---|---|---|---|
| **2.1 MB** (installed 3.1 MB) | **56.6 MB** | **0.07%** | **488 ms** |

Native SwiftUI/AppKit with no third-party dependencies; history is stored with the system SQLite. Every 0.25 s it only compares the pasteboard change counter; images are decoded at preview size with a 48-image cache, and hiding the main window unloads the interface.

Other running components (separate devices and sampling windows; figures are not added together):

- Installed CloudKit edition (window hidden): v1.1.1 (48); 2026-09-26; Mac16,12 / Apple M4 / macOS 27.2; Installed 2.4 MB; Memory 26.2 MB; CPU 0.03%; Measured operation Not measured; CloudKit setting: True; main window hidden, original preferences and real data retained. Idle residency only, without triggered transfers or new clipboard copies; not a sync peak.

<sub>v1.2.1 (78) · Mac16,12 / Apple M4 / macOS 27.2 · Local release; isolated snapshot of 2767 real clipboard records and separate preferences; named pasteboard polling remains active with no new copy, UI shown in background, no cloud sync. · measured 2026-10-06. Measured on the listed device; re-measured for each version. Memory uses phys_footprint; CPU is CPU time ÷ wall time over a 60-second sampling window; sizes in decimal MB. Raw data: [perf/lightweight.json](perf/lightweight.json).</sub>
<!-- lightweight:end -->

In a controlled image-browsing test, Clip's own physical footprint dropped from 275.5 to 117.3 MiB (about 57%, build 26). This is a before/after result, not a Deck memory benchmark. Matched latency testing is still pending.

A native Swift clipboard library for macOS. A menu-bar icon opens the three-column interface: filter, select and edit. Custom shortcuts are unassigned by default. Standard Command-C copies selected text, or all selected records when there is no text selection. Multiple text records are joined in display order with blank lines; files and images retain native pasteboard payloads. Every action offers application-only or global scope under Settings → Shortcuts. Global actions use the selection retained in Clip. Clear a custom binding to unregister it immediately. Conflicts and registration failures are shown; no fallback combination is chosen automatically.

Capture text, rich text, links, images and files; deduplicate content, pin entries, organize collections, edit and merge text. Local data stays in `~/Library/Application Support/Clipbook/`. The existing bundle ID and `clipbook://show`, `hide`, `toggle`, `settings` URLs remain compatible.

Link-title fetching and iCloud archiving are optional network features. Link responses are streamed and cancelled at 256 KiB, even when a server ignores the Range header. Automatic paste needs macOS Accessibility permission.

To receive Mac clipboard history on iPhone, use the same Apple account with iCloud Drive enabled on both devices. Enable **Settings → iCloud → iCloud 历史归档** on Mac and **Settings → iCloud 同步 → 同步 Clip 历史** in iPhone Clip. Keep Mac Clip running: the archive initially adds the latest 500 items, then newly copied text, links, and images. Find an item in iPhone Clip, open it and tap Copy, then paste into another app. Keep both apps open during the first check and wait for the sync status to update. Receiving history does not replace the phone's system clipboard. File paths are excluded and rich text becomes plain text. Local Mac cleanup does not delete the separate cloud archive. App Store and TestFlight iPhone builds use Production, so the Mac build must target the matching CloudKit environment. Sync is off by default; the measurements above are with sync off, and enabling it adds to them.

## Command line `clip` (for agents and scripts)

The window is for people; the command line is for agents. `clip` is the same signed program that ships inside Clip.app (`Clip.app/Contents/Resources/bin/clip → ../../MacOS/Clipbook`). It shares the window's business code and library: `ClipStore` (capture, dedupe, edit, retention), `Classifier`, `Paster`, `DeckImporter`, `AppSettings`, and the shared button rules in `ClipRules` (merge limits, collection icon/color whitelist, which transforms apply, export). It never starts the interface or takes focus; `--help` returns in about 20 ms.

Install: after `./build.sh` installs the app it runs `scripts/install-cli.py`, which links `~/.local/bin/clip → /Applications/Clip.app/Contents/Resources/bin/clip` and never overwrites an unrelated file or link. It can also be run by hand: `python3 scripts/install-cli.py /Applications/Clip.app`.

```bash
clip status --json                         # version, whether the app runs, record count, recording prefs, Deck, iCloud switch
clip stats --json                          # sidebar counts: kinds / source apps / collections
clip list --kind link --limit 20 --json    # same order, filters and paging as the grid; --no-text for metadata only
clip search invoice --json                 # = list --query
clip show 1234 --json                      # full text, title, link page title, file paths (with existence), image path, transforms
clip add --text "https://example.com" --json      # same path as a capture: kind detection, dedupe moves to top, link title per settings
echo "draft" | clip add --stdin --title memo --json
clip edit 1234 --text "new text" --title title    # = Save: validates first, writes only what changed
clip transform 1234 json                   # = Transform, saved; leaves the clipboard alone unless --copy
clip merge 12 13 14 --json                 # = Merge into one (images and files cannot be merged)
clip pin 1234 · clip unpin 1234
clip delete 12 13 --yes                    # irreversible, requires --yes; --dry-run only reports
clip clear --dry-run --json                # clear history (keeps pinned and collection items); run it with --yes
clip collection create Work --icon briefcase --color '#16a34a'
clip collection add Work 1234 1235 · clip collection move Work up · clip collection delete Work --yes
clip settings --json · clip settings set maxItems 3000 · clip pause · clip resume · clip ignore add com.example.app
clip settings set launchAtLogin true --dry-run     # launch at login (a system login item); drop --dry-run to apply
clip import-deck --json                    # = Import Deck history; safe to repeat
clip export 1234 -o ~/Desktop/shot.png     # original image
clip cloud status --json · clip cloud list --favorites --json   # iCloud state and this Mac's archive cache (read-only, the phone's list rule)
clip cloud show <key> --json · clip cloud show <key> -o photo.png   # one archived item in full, with its source; export its image (key and local_id come from cloud list)
clip cloud push --dry-run --json           # how many records "补充最近历史" would archive; --yes asks the running Clip to do it
clip cloud on --yes · clip cloud off --yes # ask the running Clip to flip the "iCloud 历史归档" switch
clip cloud favorite <key> · clip cloud unfavorite <key> · clip cloud delete <key> --yes   # favorite, unfavorite, delete as on iPhone / iPad (the same synced history, written by the running Clip)
clip shortcut list --json · clip shortcut scope search global · clip shortcut clear search   # view, re-scope or clear shortcuts
clip shortcut set search opt+cmd+f · clip shortcut set pause ⌃⌥P --scope global   # give an action a chord written out (the same save as recording it in the window; exit 2 naming the holder when it is taken)
clip start · clip quit                     # start Clip in the background (no main window, no focus change) · quit Clip
clip config status --json · clip config export -o clip-config.json · clip config import clip-config.json --yes   # export / import of the "配置与更新" window
clip config sync on --yes                  # ask the running Clip to turn on "使用 iCloud 记住配置"
clip update check --json                   # "Check for updates": current version, latest on this channel, whether a newer one exists and how to upgrade (read-only; downloads and installs nothing)
clip update install --dry-run --json · clip update install --yes   # "升级到新版…": verify the release and its signature, replace this app; a running Clip quits first and is reopened afterwards
clip copy 1234                             # replaces the system clipboard: use only when the user asks for it
```

Contract: every command has `--help` (exit 0) and `--json` (a stable object with `"ok"`; failures return `"ok": false` and `"error"`). The JSON `"command"` is the full command path (e.g. `collection create`, `cloud list`), the same on success and failure. Exit codes: `0` success, `1` runtime error, `2` bad arguments or missing `--yes`, `3` record/collection/library not found, `4` needs a running Clip or the installed app (or the local edition has no iCloud), `5` library or import busy. Read commands open the library read-only: no directory, database, migration or preference write. Write commands reuse the window's validation and ranges (keep 100–100000 records, retention 0/7/30/90/365 days, icon and color whitelist, plain-text transform only for rich text, no text edit or merge for images/files) and apply the keep/retention limits to old unprotected records. `clip add` records the source as Clip CLI (`cyou.tianli.clipbook.cli`). Existing identical content is treated like a repeated copy: it moves to the top and its source becomes this one; `--json` returns the old one as `previous_source` (use `--from <id>`, i.e. "Save as new", to keep a source). `clip edit` validates every argument before writing, so a refused edit leaves the record unchanged; an unchanged body is not rewritten, so rich text is not reduced to plain text. Deck import holds a lock shared by the app and the command line. After a write, a local notification tells a running Clip (this build onward) to re-read its list or preferences. Clipboard writes from `clip copy` carry an `org.nspasteboard.source` marker, so a running Clip neither records them again nor plays its sound. For isolated runs set `CLIPBOOK_HOME` and `CLIPBOOK_PREFERENCES_SUITE`; with `CLIPBOOK_BACKGROUND=1` as well, `copy` writes to an isolated named pasteboard.

iCloud: the app process owns sync and the command line never opens the sync store for writing. `cloud status` / `cloud list` open this Mac's archive cache read-only and list it with the phone's own `ClipLibrary.list` (the same code: newest row per item, deletions hide, newest first, same filters and search), as fresh as the app's last sync. `cloud push` (= "补充最近历史", add recent history) and `cloud on|off` (= the "iCloud 历史归档" switch) upload to or stop syncing your iCloud, so they require `--yes` and are run by the running Clip (which does the account checks; exit 4 when Clip is not running). Read the result back with `cloud status` (`enabled`, `recent_pending`, archive marker counts). With iCloud on, after `clip add` / `edit` / import a running Clip archives the newest records as it does for a new copy; if Clip is not running, the next start catches up. Launch at login, `settings set launchAtLogin`, calls the same code as the Settings toggle (a system login item); it applies only to a Clip installed in Applications and exits 4 in an isolated run.

App only (needs a person, or only meaningful in the window): pasting into the previous app (activate it and send ⌘V), shortcut recording, the Accessibility "Grant…" prompt, sound preview, grid selection, showing/hiding windows and focusing search, opening the Settings and "配置与更新…" windows, the Edit menu, opening the data folder / revealing in Finder / opening links (`show --json` already returns the paths and URL), About / Minimize / Close. Shortcut recording means capturing a key press; to store a chord written out for an action use `clip shortcut set` — nothing is bound by default, and a chord is written only when the action and the chord are both given. Start and quit with `clip start` / `clip quit`; upgrade with `clip update install --yes` (the window's own installer; an isolated run goes no further than `--dry-run`). Three facts only the running Clip knows — whether Accessibility is granted (`permissions.accessibility` in `status`), whether each global shortcut registered (`registration` in `shortcut list`), and the iCloud sync status and errors (`live` in `cloud status`) — are written by the app to `runtime-state.json` in the data folder and read by the commands; while Clip is not running the last two are `app_not_running` / `null`, and the grant keeps its last reported value, marked as not live. The sync sentence under the "使用 iCloud 记住配置" switch is `sync_status` in `config status`. The phone's favorite, unfavorite and delete change the same synced history; on the Mac use `clip cloud favorite|unfavorite|delete <key>`: the command reads and asks, and the running Clip writes through the phone's own code (exit 4 while Clip is not running — `clip start` first). Only the synced history changes; the Mac library's own copy stays as it is. The item-by-item map of window features to commands is registered under `sop.agent_cli` in `project.yaml`.

Verify: `bash tests/test-cli.sh [Clip.app]` runs the in-bundle entry against an isolated library (and checks the user's general clipboard is untouched); the production `--selftest` has its own `clip` assertions.

## Build and verify

Use `open -g -a Clip --args --background` to start capture and sync without opening the main window; the menu bar or Dock can still open it. Release builds target CloudKit Production to match App Store/TestFlight. The original development archive remains intact; production uses a separate cache and seeds the latest 500 records from local history.

`bash build.sh --build-only` compiles and runs the production self-test without installing. `bash build.sh` installs the app as the catalog's English name (`name_en`: Clip) into `/Applications` and links the `clip` command. The build reuses the headquarters Xcode selector, CodingKey checker and icon converter. It preserves the Apple Development signing identity when available.

`build/Clipbook --selftest` exercises the real store, importer, classifier and watcher with isolated fixtures. `bash tests/test-link-title.sh` verifies bounded HTTP fetching against a local server that ignores Range.

General preferences persist without leaving Settings open. Retention runs on the next capture; deletion requires confirmation, and login-item failures or pending approval are visible. Installation does not forcibly kill a running instance. `CLIPBOOK_HOME` and `CLIPBOOK_PREFERENCES_SUITE` provide isolated UI-test storage; a custom home never automatically imports Deck data.
