# Clip

[中文](README.md)

**Quick access. A lighter footprint.** A keyboard-friendly, local clipboard library.

[Product page and real demo](https://app-mac-clips.tianli.cyou/) · [Measured comparison and limitations](promotion/COMPARISON.md)

Build 26 occupies approximately 3.3 MB on this Mac. In a controlled image-browsing test, Clip's own physical footprint dropped from 275.5 to 117.3 MiB (about 57%). This is a before/after result, not a Deck memory benchmark. Matched latency testing is still pending. There is no public installer yet.

A native Swift clipboard library for macOS. A menu-bar icon opens the three-column interface: filter, select and edit. Custom shortcuts are unassigned by default. Standard Command-C copies selected text, or all selected records when there is no text selection. Multiple text records are joined in display order with blank lines; files and images retain native pasteboard payloads. Every action offers application-only or global scope under Settings → Shortcuts. Global actions use the selection retained in Clip. Clear a custom binding to unregister it immediately. Conflicts and registration failures are shown; no fallback combination is chosen automatically.

Capture text, rich text, links, images and files; deduplicate content, pin entries, organize collections, edit and merge text. Local data stays in `~/Library/Application Support/Clipbook/`. The existing bundle ID and `clipbook://show`, `hide`, `toggle`, `settings` URLs remain compatible.

Link-title fetching and iCloud archiving are optional network features. Link responses are streamed and cancelled at 256 KiB, even when a server ignores the Range header. Automatic paste needs macOS Accessibility permission.

## Build and verify

`bash build.sh --build-only` compiles and runs the production self-test without installing. `bash build.sh` installs the catalog's display name into `/Applications`. The build reuses the headquarters Xcode selector, CodingKey checker and icon converter. It preserves the Apple Development signing identity when available.

`build/Clipbook --selftest` exercises the real store, importer, classifier and watcher with isolated fixtures. `bash tests/test-link-title.sh` verifies bounded HTTP fetching against a local server that ignores Range.

General preferences persist without leaving Settings open. Retention runs on the next capture; deletion requires confirmation, and login-item failures or pending approval are visible. Installation does not forcibly kill a running instance. `CLIPBOOK_HOME` and `CLIPBOOK_PREFERENCES_SUITE` provide isolated UI-test storage; a custom home never automatically imports Deck data.
