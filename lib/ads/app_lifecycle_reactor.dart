import 'dart:io';

import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'app_open_ad_manager.dart';

/// Listens for app foreground events and shows app open ads.
class AppLifecycleReactor {
  AppLifecycleReactor({
    required AppOpenAdManager appOpenAdManager,
    required bool Function() shouldShowAd,
    void Function()? onAdShown,
  })  : _appOpenAdManager = appOpenAdManager,
        _shouldShowAd = shouldShowAd,
        _onAdShown = onAdShown;

  final AppOpenAdManager _appOpenAdManager;
  final bool Function() _shouldShowAd;
  final void Function()? _onAdShown;
  bool _listening = false;

  /// Start listening to app state changes and show ads on foreground.
  Future<void> listenToAppStateChanges() async {
    if (Platform.isMacOS || _listening) return;
    _listening = true;
    await AppStateEventNotifier.startListening();
    AppStateEventNotifier.appStateStream.listen(_onAppStateChanged);
  }

  void _onAppStateChanged(AppState appState) {
    if (appState == AppState.foreground && _shouldShowAd()) {
      _appOpenAdManager.showAdIfAvailable();
      _onAdShown?.call();
    }
  }
}
