import 'dart:async';

import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter/material.dart';

/// AdMob/UMP consent: request at startup and optionally show privacy options from Settings.
class AdConsentHelper {
  AdConsentHelper._();

  static bool privacyOptionsRequired = false;

  static Future<void> ensureConsent() async {
    final completer = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () async {
        try {
          await ConsentForm.loadAndShowConsentFormIfRequired((FormError? _) {});
          final status = await ConsentInformation.instance.getPrivacyOptionsRequirementStatus();
          privacyOptionsRequired = status == PrivacyOptionsRequirementStatus.required;
        } catch (_) {
          // Continue without blocking app
        }
        if (!completer.isCompleted) completer.complete();
      },
      (FormError error) {
        debugPrint(
          'AdMob consent config failed: code=${error.errorCode}, message=${error.message}. '
          'In AdMob console check Privacy & messaging has a published consent form for this app.',
        );
        if (!completer.isCompleted) completer.complete();
      },
    );
    await completer.future;
  }

  static Future<void> showPrivacyOptionsForm() async {
    await ConsentForm.showPrivacyOptionsForm((FormError? _) {});
  }
}