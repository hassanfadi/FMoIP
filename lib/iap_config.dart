/// In-app purchase configuration.
///
/// Create the product in:
/// - Android: Google Play Console → Monetize → Products → Subscriptions
/// - iOS: App Store Connect → Your app → Subscriptions (or In-App Purchases)
///
/// For iOS local testing: In Xcode, Edit Scheme → Run → Options →
/// StoreKit Configuration → select ios/Runner/FMoIPProducts.storekit

import 'dart:io';

class IapConfig {
  IapConfig._();

  /// Subscription (ad-free) product ID for Android. Must match Google Play Console.
  static const String subscriptionProductIdAndroid = 'fmoip_pro';

  /// Subscription (ad-free) product ID for iOS. Must match App Store Connect.
  static const String subscriptionProductIdIos = 'fmoip_pro';

  static String get subscriptionProductId =>
      Platform.isAndroid ? subscriptionProductIdAndroid : subscriptionProductIdIos;

  /// Product IDs to query (one per platform to avoid duplicate keys in a const set).
  static Set<String> get productIds => {subscriptionProductId};
}
