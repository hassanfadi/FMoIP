/// AdMob configuration for FMoIP.
///
/// To use your own Google AdMob account:
///
/// 1. Create an app in AdMob (https://admob.google.com):
///    - One for Android (get Android App ID)
///    - One for iOS (get iOS App ID)
///
/// 2. Create a "Banner" ad unit for each app and copy the Ad unit IDs.
///
/// 3. Replace the values below with your real IDs:
///    - [bannerAdUnitIdAndroid] – Banner ad unit ID for Android (e.g. ca-app-pub-1234567890123456/1234567890)
///    - [bannerAdUnitIdIos] – Banner ad unit ID for iOS
///
/// 4. Set your App IDs in native config:
///    - Android: android/app/src/main/AndroidManifest.xml
///      Replace the <meta-data android:name="com.google.android.gms.ads.APPLICATION_ID" android:value="..." />
///      with your Android App ID (e.g. ca-app-pub-1234567890123456~1234567890).
///    - iOS: ios/Runner/Info.plist
///      Replace the <string> for GADApplicationIdentifier with your iOS App ID.
///
/// Until you replace these, the app uses Google's test IDs so you can run without policy issues.

import 'dart:io';

class AdConfig {
  AdConfig._();

  /// Banner ad unit ID for Android. Test: ca-app-pub-3940256099942544/6300978111
  static const String bannerAdUnitIdAndroid =
      'ca-app-pub-1133915836610707/2055276408';

  /// Banner ad unit ID for iOS. Replace with your AdMob banner ad unit ID.
  static const String bannerAdUnitIdIos =
      'ca-app-pub-3940256099942544/2934735716'; // Test ID

  static String get bannerAdUnitId =>
      Platform.isAndroid ? bannerAdUnitIdAndroid : bannerAdUnitIdIos;
}
