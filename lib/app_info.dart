/// Central place for app and developer info. Used by About screen and Send feedback.
abstract final class AppInfo {
  static const String appName = 'FMoIP';

  /// Developer email for feedback.
  static const String developerEmail = 'fadiabdulf@gmail.com';

  /// Developer name or team. Optional, for display in About screen.
  static const String? developerName = 'Fadi Hassan'; // e.g. 'Your Name' or 'Your Company'

  /// Privacy policy URL for store listings and in-app link.
  /// Update this when you deploy (e.g. https://yoursite.com/privacy.html).
  static const String privacyPolicyUrl =
      'https://hassanfadi.github.io/FMoIP/privacy-policy.html'; // Or your deployed URL
}
