import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../iap_config.dart';

class SubscriptionState extends ChangeNotifier {
  static const String _isProKey = 'subscription_is_pro';

  bool isPro = false;
  bool isLoading = false;
  String? errorMessage;

  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;

  SubscriptionState() {
    Future.microtask(() => _loadAndInit());
  }

  Future<void> _loadAndInit() async {
    final prefs = await SharedPreferences.getInstance();
    isPro = prefs.getBool(_isProKey) ?? false;
    notifyListeners();
    _listenToPurchases();
    if (!isPro) {
      Future.microtask(() => _restorePurchasesIfAvailable());
    }
  }

  Future<void> _restorePurchasesIfAvailable() async {
    final available = await InAppPurchase.instance.isAvailable();
    if (!available) return;
    try {
      await InAppPurchase.instance.restorePurchases();
    } catch (_) {}
  }

  void _listenToPurchases() {
    _purchaseSubscription?.cancel();
    _purchaseSubscription = InAppPurchase.instance.purchaseStream.listen(
      _onPurchaseUpdates,
      onDone: () => _purchaseSubscription = null,
      onError: (Object e) {
        errorMessage = e.toString();
        isLoading = false;
        notifyListeners();
      },
    );
  }

  Future<void> _onPurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.productID != IapConfig.subscriptionProductId) continue;
      switch (purchase.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          isPro = true;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool(_isProKey, true);
          if (purchase.pendingCompletePurchase) {
            await InAppPurchase.instance.completePurchase(purchase);
          }
          break;
        case PurchaseStatus.error:
          errorMessage = purchase.error?.message ?? 'Purchase failed';
          break;
        case PurchaseStatus.canceled:
          break;
        case PurchaseStatus.pending:
          break;
      }
      notifyListeners();
    }
  }

  Future<void> restorePurchases() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      await InAppPurchase.instance.restorePurchases();
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> purchaseSubscription() async {
    if (isLoading) return;
    errorMessage = null;
    isLoading = true;
    notifyListeners();
    final available = await InAppPurchase.instance.isAvailable();
    if (!available) {
      errorMessage = 'Store is not available.';
      isLoading = false;
      notifyListeners();
      return;
    }
    final response =
        await InAppPurchase.instance.queryProductDetails(IapConfig.productIds);
    if (response.notFoundIDs.isNotEmpty) {
      errorMessage = Platform.isIOS
          ? 'Subscription product not found. Add "${IapConfig.subscriptionProductId}" in App Store Connect.'
          : 'Subscription product not found. Add "${IapConfig.subscriptionProductId}" in Play Console.';
      isLoading = false;
      notifyListeners();
      return;
    }
    final productDetails = response.productDetails;
    if (productDetails.isEmpty) {
      errorMessage = 'Subscription not available.';
      isLoading = false;
      notifyListeners();
      return;
    }
    final product = productDetails.first;
    final success = await InAppPurchase.instance.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: product),
    );
    if (!success) {
      errorMessage = 'Could not start purchase.';
      isLoading = false;
      notifyListeners();
    }
  }

  void clearError() {
    errorMessage = null;
    notifyListeners();
  }

  /// Opens the platform's subscription management page (Play Store or App Store).
  Future<void> openSubscriptionManagement() async {
    final url = Platform.isAndroid
        ? Uri.parse(
            'https://play.google.com/store/account/subscriptions?sku=${IapConfig.subscriptionProductId}&package=com.fmoip.app',
          )
        : Uri.parse(
            'https://buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/manageSubscriptions',
          );
    try {
      // canLaunchUrl can return false on Android 11+ even when launch works; try launch anyway
      final launched = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!launched) {
        errorMessage = 'Could not open subscription management.';
        notifyListeners();
      }
    } catch (e) {
      errorMessage = 'Could not open subscription management.';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _purchaseSubscription?.cancel();
    super.dispose();
  }
}
