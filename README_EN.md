# Clips

[中文](README.md)

A native Swift clipboard library for macOS. A menu-bar icon opens the existing three-column interface: filter, select and edit. No custom hotkeys are registered.

Capture text, rich text, links, images and files; deduplicate content, pin entries, organize collections, edit and merge text. Local data stays in `~/Library/Application Support/Clipbook/`. The existing bundle ID and `clipbook://show`, `hide`, `toggle`, `settings` URLs remain compatible.

Link-title fetching is optional and is the only network operation. Responses are streamed and cancelled at 256 KiB, even when a server ignores the Range header. Automatic paste needs macOS Accessibility permission.

## Build and verify

`bash build.sh --build-only` compiles and runs the production self-test without installing. `bash build.sh` installs `/Applications/Clips.app`. The build reuses the headquarters Xcode selector, CodingKey checker and icon factory. It preserves the Apple Development signing identity when available.

`build/Clipbook --selftest` exercises the real store, importer, classifier and watcher with isolated fixtures. `bash tests/test-link-title.sh` verifies bounded HTTP fetching against a local server that ignores Range.

The product name is Clips in both languages; existing Chinese interface labels are retained. Installation no longer forcibly kills a running instance.
