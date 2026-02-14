# Building for App Store

## Prerequisites
1. **Apple Developer account** (enrolled at developer.apple.com)
2. **Xcode** installed with command line tools

## Setup signing (one-time)
1. Open the project in Xcode:
   ```bash
   open ios/Runner.xcworkspace
   ```
2. Select **Runner** in the navigator, then **Runner** target
3. Go to **Signing & Capabilities**
4. Check **Automatically manage signing**
5. Select your **Team** (sign in with Apple ID if needed)
6. Ensure Bundle ID `com.fmoip.app` is registered in your Apple Developer account

## Build IPA
```bash
cd /path/to/FMoIP
flutter build ipa
```

Output: `build/ios/ipa/fmoip.ipa`

Upload to App Store Connect via Xcode (Window > Organizer) or Transporter app.
