# Releasing DNSWatch

## Prerequisites
- Xcode 15+
- Developer ID Application certificate installed (for signing)
- `swiftformat` and `swiftlint` installed (`brew install swiftformat swiftlint`)
- App Store Connect app-specific password (for notarization)

## Release checklist
1. Update `version.env` (`MARKETING_VERSION`, `BUILD_NUMBER`).
2. Update `CHANGELOG.md` and keep the top section as `Unreleased`.
3. Run format + lint:
   - `swiftformat DNSWatch/Sources`
   - `swiftlint --strict`
4. Build and package:
   - `./Scripts/package_app.sh --sign`
5. Notarize (optional):
   - `./Scripts/package_app.sh --notarize`
6. Verify install from `dist/` (DMG + ZIP).
7. Create GitHub release and upload artifacts:
   - `DNSWatch-v<version>-mac.dmg`
   - `DNSWatch-v<version>-mac.zip`
   - `DNSWatch-v<version>-mac.dSYM.zip`

## Environment variables
- `SIGNING_IDENTITY`: Code signing identity (default: `-` for ad-hoc)
- `APPLE_ID`: Apple ID email
- `APPLE_TEAM_ID`: Apple Team ID
- `APPLE_APP_PASSWORD`: App-specific password
- `ARCHES`: Build arches (default: host arch; use `"arm64 x86_64"` for universal)
