# Omega LocSim Liquid Glass icon

Historical artwork, used through 3.2.1. Version 3.2.2 selects `OmegaLocSimPeel` instead; this editable vector source is preserved.

Original Ω and north-pointing navigation geometry, designed from scratch for Omega LocSim. The blue/cyan background reaches the system icon edge; the artwork contains no white border or baked icon mask.

## Editable source

- `layers/01-Omega.svg` and `layers/02-Navigation.svg`: original 1024 × 1024 vector layers, with no embedded shadows, gradients, blur, or background.
- `../../StikDebug/OmegaLocSimGlass.icon`: the editable Apple Icon Composer document. The two vectors were imported, assembled, previewed with native Liquid Glass, configured for iOS, and saved using Apple's Icon Composer. Its JSON defines the cyan-to-cobalt background gradient and native group translucency/shadow. Native effects remain editable.
- The existing StikDebug icon, previous supplied Omega artwork, upstream attribution, and repository license remain in place.

The icon uses Apple's automatic Default, Dark, and Mono/tinted appearance treatment. The tinted preview is one example color; iOS chooses the user's tint at runtime. These are native glass appearances, not separate painted bitmap imitations.

## Integration

Both Xcode configurations set `ASSETCATALOG_COMPILER_APPICON_NAME = OmegaLocSimGlass`. The source is inside the synchronized `StikDebug` target directory. The old `OmegaLocSim.appiconset` remains preserved but inactive. Xcode compiles the layered icon and generates fallback images for older supported iOS versions.

`OmegaLocSimBrand.imageset` contains 80, 160, and 240 pixel Default and Dark PNG images resized from Apple-rendered exports. Settings uses that asset name and follows the system light/dark appearance.

## Export and validation

The previews were exported using the `ictool` bundled inside Apple Icon Composer, after native UI assembly and preview. Example (run from the repository root):

```sh
'/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool' \
  StikDebug/OmegaLocSimGlass.icon --export-image --output-file /tmp/omega-icon.png \
  --platform iOS --rendition Default --width 1024 --height 1024 --scale 1 \
  --design-generation 27
```

Use `Dark` or `TintedDark` for the other previews; tinted exports accept `--tint-color` and `--tint-strength`. The preview contact sheet shows the three appearances and 60/40/29 pixel sizes. Icon Composer and the asset compiler supply the system mask, lighting, native glass depth, and appearance transformations.

An isolated Xcode 27.1 `actool` compilation succeeded for `iphoneos`, deployment target 17.4, including iPhone/iPad output. The generated info plist names `OmegaLocSimGlass`; `Assets.car` contains light, dark, and tintable `IconImageStack` renditions with both SVG vectors, and the generated iPhone fallback PNG was decoded and visually checked. The existing missing `AccentColor` notice is unrelated to the icon.

Apple references: [Icon Composer](https://developer.apple.com/icon-composer/), [creating an app icon with Icon Composer](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer), [app icon design guidance](https://developer.apple.com/design/human-interface-guidelines/app-icons).
