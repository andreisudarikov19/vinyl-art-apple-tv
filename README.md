# Vinyl for Apple TV

This is the README for a future product. Work in progress.

## Development setup

Requires Xcode 26+ and [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

1. Register an application at https://www.discogs.com/settings/developers
   (use **Create an Application**, not the personal-access-token button) to
   get a Consumer Key and Consumer Secret.
2. Copy the secrets template and fill in your credentials:
   ```sh
   cp Sources/Auth/AppSecrets.example.swift Sources/Auth/AppSecrets.swift
   # edit AppSecrets.swift with your Consumer Key and Secret
   ```
   `AppSecrets.swift` is gitignored, so your credentials stay local.
3. Generate the Xcode project and open it:
   ```sh
   xcodegen generate
   open VinylForAppleTV.xcodeproj
   ```
