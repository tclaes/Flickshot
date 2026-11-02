# Flickshot

A native Apple Silicon replacement for [Lightshot](https://app.prntscr.com/), whose Mac app is Intel-only and needs Rosetta.

## Build & install

```bash
./build.sh install
```

This builds `build/Flickshot.app` (arm64, ad-hoc signed), copies it to `/Applications` and launches it. Requires macOS 14+ and the Xcode Command Line Tools.

On first launch, grant **Screen & System Audio Recording** in System Settings → Privacy & Security. Every rebuild gets a new ad-hoc signature, so after reinstalling you may need to remove Flickshot from that list and add it again.

Prebuilt versions are attached to [Releases](https://github.com/tclaes/Flickshot/releases). They are not notarized by Apple, so building from source is the recommended way to install.

## Usage

| Action | How |
| --- | --- |
| Take screenshot | **⌥⌘S** or menu bar icon → Take Screenshot |
| Select area | Drag (Shift = square). Click once to select the whole display. ⌘A = whole display |
| Move / resize | Drag inside the selection (no tool selected) / drag the handles |
| Annotate | Pen, line, arrow, rectangle, ellipse, marker, text. Shift snaps lines to 45° and makes shapes square |
| Line width | Scroll wheel / two-finger scroll while a selection is showing |
| Copy | ⌘C, Return, or double-click the selection |
| Save | ⌘S |
| Undo | ⌘Z |
| Cancel | Esc or right-click |

## License

[MIT](LICENSE)
