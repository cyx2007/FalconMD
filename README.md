# FalconMD

A lightweight native macOS Markdown editor. Formatting appears as you type.

Requires **macOS 15** and **Xcode 26**.

## Features

- Open, edit, and save `.md` / `.markdown` files
- Live Markdown styling (headings, emphasis, lists, quotes, code, links, images)
- Start page with New, Open, and recents
- Find / replace (`⌘F`)
- Raw source toggle (`⌘\`)
- Format menu scoped to the current window
- Paste or drop images into `{filename}.assets/`

## Build

Open `FalconMD.xcodeproj` in Xcode, select the **FalconMD** scheme, and run.

Command line:

```bash
xcodebuild -project FalconMD.xcodeproj -scheme FalconMD \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData test
```

The Debug app lands at:

`build/DerivedData/Build/Products/Debug/FalconMD.app`

You can also open `Sample.md` with **File → Open**.

## GitHub Actions

Pushes to `main` and pull requests run tests without uploading an app artifact.

Pushing a version tag such as `v0.1.0` builds a universal Release app, creates
`FalconMD.dmg`, and publishes both the DMG and its SHA-256 checksum on the
matching GitHub Release. The stable latest-download URL is:

`https://github.com/cyx2007/FalconMD/releases/latest/download/FalconMD.dmg`

The app inside the DMG is **ad-hoc signed**. Public distribution without
Gatekeeper warnings still requires a Developer ID certificate and notarization.
