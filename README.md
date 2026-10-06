# NoTabsConfusion

Free menu bar app for Mac. In Mission Control it outlines the windows you were just using and shows each app icon. The menu bar name is FocusBorder. Not on the App Store.

[Website](https://incyashraj.github.io/NoTabsConfusion/) · [Download 1.0](https://github.com/incyashraj/NoTabsConfusion/releases/latest/download/NoTabsConfusion-1.0.zip)

<img src="docs/icon.png" width="64" height="64" alt="NoTabsConfusion icon">

## Requirements

- Apple silicon
- macOS 26.2 or later
- Signed with Developer ID Application: Yashraj Pardeshi (DBYD4AW5Q8)

## Install

1. Unzip the download and move `NoTabsConfusion.app` to Applications.
2. Open it. There is no Dock icon. Use the scope icon in the menu bar.
3. Allow the access prompt so the app can see the front window. It also needs Accessibility access.
4. If macOS blocks the first open, go to System Settings → Privacy & Security and click Open Anyway.

The most recent window gets a purple-blue border, the one before it an amber border, and the third a teal border. Borders stay hidden until Mission Control is open.

## Privacy

No account, no ads, and no network requests. See [PRIVACY.md](PRIVACY.md).

## Build

Open `NoTabsConfusion.xcodeproj` in Xcode and run the NoTabsConfusion scheme.
