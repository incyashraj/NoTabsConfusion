<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="NoTabsConfusion app icon">
</p>

<h1 align="center">NoTabsConfusion</h1>

<p align="center">
  Free menu bar app for Mac. In Mission Control it outlines the windows you were just using and shows each app icon.
  <br>
  <a href="https://incyashraj.github.io/NoTabsConfusion/">Website</a>
  ·
  <a href="https://github.com/incyashraj/NoTabsConfusion/releases/latest">Download</a>
</p>

The menu bar name is FocusBorder. The app is not on the App Store.

## Download

[NoTabsConfusion 1.0](https://github.com/incyashraj/NoTabsConfusion/releases/latest/download/NoTabsConfusion-1.0.zip)

- Apple silicon
- macOS 26.2 or later
- Signed with Developer ID Application: Yashraj Pardeshi (DBYD4AW5Q8)

## Install

1. Unzip the download and move `NoTabsConfusion.app` to Applications.
2. Open it. There is no Dock icon. Use the scope icon in the menu bar.
3. Allow the access prompt so the app can see the front window. It also needs Accessibility access.
4. If macOS blocks the first open, go to System Settings → Privacy & Security and click Open Anyway.

Open Mission Control to see the borders. The most recent window gets a purple-blue glow, the one before it an amber border, and the third a teal border. Each border carries that app’s icon. Borders stay hidden the rest of the time.

## Privacy

No account, no ads, and no network requests. The [privacy note](PRIVACY.md) has the short version.

## Build

Open `NoTabsConfusion.xcodeproj` in Xcode and run the NoTabsConfusion scheme. The project targets macOS 26.2.
