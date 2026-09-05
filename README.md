# FalconMD

A lightweight native macOS Markdown editor. Formatting appears as you type.

Requires **macOS 15** and **Xcode 26**.

## Features

- Open, edit, and save `.md` / `.markdown` files
- Live Markdown styling (headings, emphasis, lists, quotes, code, links, images)
- Start page with New, Open, and recents
- Drop Markdown / plain-text files onto the start page or editor to open them
- Native page scrolling and independent horizontal scrolling for wide tables
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

Drag one or more Markdown / plain-text files from Finder onto the welcome page
or an editor window. A highlighted border confirms a supported drop. Each file
opens through the document controller; dropping an already-open file focuses its
window. Image drops in the editor still insert images into the assets folder.
Folders and batches containing unsupported files are rejected.

Scroll vertically over text or a table to move the page. Scroll horizontally over
a wide table (or use Shift + mouse wheel) to move its columns. A trackpad gesture
keeps its initial axis through momentum. Page scrolling uses the engine's public
`fitsContent` mode inside a system scroll view, following [AppKit's responsive
scrolling guidance](https://developer.apple.com/library/archive/releasenotes/AppKit/RN-AppKitOlderNotes/#10_9Scrolling).

## App icon

The app icon is maintained as an editable [SVG source](design/app-icon/falconmd-icon.svg).
See the [icon maintenance guide](design/app-icon/README.md) for design constraints,
PNG regeneration, and validation. The generated images are committed in
`FalconMD/Assets.xcassets/AppIcon.appiconset/`; building the app does not require Node.js.

## GitHub Actions

Pushes to `main` and pull requests run tests without uploading an app artifact.

Pushing a version tag such as `v0.1.0` builds a universal Release app, creates
`FalconMD.dmg`, and publishes both the DMG and its SHA-256 checksum on the
matching GitHub Release. The stable latest-download URL is:

`https://github.com/cyx2007/FalconMD/releases/latest/download/FalconMD.dmg`

The app inside the DMG is **ad-hoc signed**. Public distribution without
Gatekeeper warnings still requires a Developer ID certificate and notarization.
