# Omega LocSim 3.3.2 (11)

- Smooth sheet transitions, camera following, status changes, and route controls.
- Keep search-result identity stable as suggestions update.
- Cancel queued automatic scrolling when you scroll directly or dismiss the sheet.
- Respect Reduce Motion with fades and no camera animation.

The public build includes standard pairing-file import and excludes the separately licensed StikPair on-device pairing integration. The personal 3.4.1 build remains separate from this public release. Both use `com.omega.locsim`, so installing the public build replaces an existing personal Omega installation.

The release asset is an unsigned arm64 iPhone/iPad IPA that must be signed before installation. It contains no developer provisioning profile or pairing credentials.

Validation: the generic iOS Release build passed. The IPA passed ZIP integrity checks and an extract-and-compare check of every file and its permissions. Its arm64 executable contains no code signature, and the app has no provisioning profile, pairing record, private-key/token payload, StikPair integration, or debug acceptance runner.

Asset: `omega-locsim-3.3.2-unsigned.ipa` (11,829,844 bytes).

SHA-256: `348d4cb07c8920287ddeb84489a757448022b63527619ff5b588adf08cde733f`.

No new physical-device or live road-data validation is claimed for this release.
