# Complete map, shared peel mask, centered Omega

Version 3.2.6 (build 8). Active document: `../../StikDebug/OmegaLocSimPeel.icon`.

The complete reference-inspired map is built from 18 independent vector elements in `CompleteMap.icon`. The production icon applies exactly the same peel path to each, including the navigation medallion. Two separate vectors form the peel underside/lip, with native Composer shadow. The schematic has an Omega outline and 19 individual guides: 40 total layers in four groups. No raster artwork or embedded image is used by either document.

The Omega has a symmetric outline around x=512. Its geometric bounds are x=140...884, y=182...842, centered at (512,512). The reveal is asymmetric but does not move or distort the underlying Omega.

Native fill specializations define both Default and Dark. A simultaneous base fill overrides specializations, so no layer uses both. Dark map areas are charcoal, the corridor/lens blue, and arrow/Omega white. Native glass, translucency and shadows supply the surface treatment. Fine schematic guides use plain vectors for clarity.

Reviewed complete-map and peeled light/dark exports, plus clear/tinted modes and 60-pixel previews. Opened and saved in Icon Composer. Build 8 is packaged but not installed; the phone remains disconnected. Settings and compatibility PNGs are generated outputs, not source artwork. Historical designs remain in Git history and `previous-flattened.icon`.

The navigation medallion and arrow move up 100 canvas units as one assembly. The peel boundary reveals roughly 80 more units at the left edge and 70 around its midpoint. The blue blueprint gradient and guide colors now match in Default and Dark appearances; the map face retains its charcoal dark palette. Omega geometry remains unchanged.
