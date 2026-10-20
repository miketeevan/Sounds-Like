# Build and installation

## Simulator builds

Install Xcode with iOS and tvOS simulator platform support. Run `./scripts/build-all.sh` from the repository root. The universal iOS app covers iPhone, iPad and adaptive compact/expanded layouts; no separate Duo binary is needed. CarPlay templates compile into the same iOS target. Top Shelf is embedded in the TV app.

## Device signing

1. Select your Apple developer team in Signing & Capabilities for the iOS app, Siri extension, TV app and Top Shelf extension. Personal signing teams are intentionally blank in this public copy.
2. Replace `uk.mike.RadioBridge` and its extension suffixes with identifiers registered to your team. Use the same app identifier for iOS and tvOS if they should share the same iCloud key-value store.
3. Update the iCloud key-value store identifier in App/RadioBridge.entitlements, App/CarPlay.entitlements and TV/SoundsLike.entitlements consistently. Keep the TeamIdentifierPrefix substitution.
4. Register an App Group, replace `group.uk.mike.RadioBridge` in TV/SoundsLike.entitlements, TopShelf/TopShelf.entitlements and TopShelf/ShelfSnapshot.swift, and enable it on both TV targets.
5. Enable Siri and iCloud key-value storage on the relevant identifiers. Choose a connected device with Developer Mode enabled, then Run. Xcode manages provisioning.

For CarPlay, Apple must grant the audio entitlement. Once approved, use `SOUNDS_LIKE_ENTITLEMENTS=App/CarPlay.entitlements` for the RadioBridge build. Do not apply it to the Siri extension. CarPlay is not enabled in the normal app entitlement file.

Example physical builds after configuring signing:

```sh
xcodebuild -project RadioBridge.xcodeproj -scheme RadioBridge -configuration Release -destination 'generic/platform=iOS' -derivedDataPath build-ios -allowProvisioningUpdates build
xcodebuild -project RadioBridge.xcodeproj -scheme SoundsLikeTV -configuration Release -destination 'generic/platform=tvOS' -derivedDataPath build-tv -allowProvisioningUpdates build
```

## Verification scope

Physical iPhone/iPad playback, iPad windows, favourites and download-list syncing were exercised during development. TV playback and remote navigation were exercised on earlier installed builds. The latest TV build includes Top Shelf; deployment of that update was blocked by the Apple developer device connection, so physical Top Shelf behaviour remains unverified. Adaptive Duo screenshots are layout previews. CarPlay entitlement approval and vehicle testing remain outstanding.

The repository is a source release. Producing an installable IPA or App Store/TestFlight release requires your signing identities, provisioning and distribution configuration.
