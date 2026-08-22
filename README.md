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

Pushes to `main` and pull requests run tests, build a Release app, and upload `FalconMD.app.zip`.

The package is **ad-hoc signed**. It runs on the machine that built it; distributing to other Macs needs a Developer ID certificate and notarization.
