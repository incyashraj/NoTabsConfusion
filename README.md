# NoTabsConfusion

Swipe up with four fingers and Mission Control shows every open window. Most apps are plain black or white, and the windows change place every time you swipe.

This keeps a set color on the three you used last, so you can see where you came from and where you were going.

- The one you just left: purple
- The one before that: amber
- The one before that: teal

Colors show only in Mission Control. The menu bar item is NoTabs. Free, and not on the App Store.

[Website](https://incyashraj.github.io/NoTabsConfusion/) · [Download 1.3](https://github.com/incyashraj/NoTabsConfusion/releases/latest/download/NoTabsConfusion-1.3.zip)

<img src="docs/icon.png" width="64" height="64" alt="NoTabsConfusion icon">

## Requirements

- Apple silicon
- macOS 26.2 or later
- Signed with Developer ID Application: Yashraj Pardeshi (DBYD4AW5Q8)

## Install

1. Unzip the download and move `NoTabsConfusion.app` to Applications.
2. Open it. A window named NoTabsConfusion opens, and NoTabs shows in the menu bar. Close the window and the app stays there.
3. Allow the access prompt so the app can see the front window. It also needs Accessibility access.


## Preferences

The menu bar icon can pause the borders, ignore the front app, show or hide app icons, and open the app at login.

Preferences sets the three colors, the border width, the glow, and whether to mark the last 2 or 3 apps. SmartNotch is ignored until you include it again from the menu.

## Privacy

No account, no ads, and no network requests. See [PRIVACY.md](PRIVACY.md).

## Build

Open `NoTabsConfusion.xcodeproj` in Xcode and run the NoTabsConfusion scheme.
