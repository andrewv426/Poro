# Radio Canada fonts

Drop the four `.ttf` files from Google Fonts into **this directory**, then add them to the `Poro` target in Xcode (drag into the project navigator → check "Copy items if needed" → confirm target membership on `Poro`).

Required files (exact filenames matter — they're referenced by `PoroFontWeight.postScriptName` in `Poro/Views/PoroTheme.swift` and by `AppDelegate.registerBundledFonts()`):

- `RadioCanada-Regular.ttf` (weight 400)
- `RadioCanada-Medium.ttf` (weight 500)
- `RadioCanada-SemiBold.ttf` (weight 600)
- `RadioCanada-Bold.ttf` (weight 700)

Download: https://fonts.google.com/specimen/Radio+Canada

`AppDelegate.applicationDidFinishLaunching` registers these at runtime via `CTFontManagerRegisterFontsForURL`. We tried the `INFOPLIST_KEY_ATSApplicationFontsPath` build setting first — Xcode 26.1 silently ignores it, so we register programmatically instead.
