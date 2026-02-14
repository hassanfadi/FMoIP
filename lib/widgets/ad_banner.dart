import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../ads/ad_config.dart';

class AdBanner extends StatefulWidget {
  const AdBanner({super.key});

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;
  LoadAdError? _loadError;
  static const int _maxRetries = 3;
  int _retryCount = 0;

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  Future<void> _loadAd() async {
    if (Platform.isMacOS || !mounted) return;
    try {
      final canRequest = await ConsentInformation.instance.canRequestAds();
      if (!canRequest || !mounted) return;
    } catch (e) {
      debugPrint('AdMob consent check failed: $e');
      return;
    }
    _bannerAd?.dispose();
    _bannerAd = BannerAd(
      adUnitId: AdConfig.bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) {
            setState(() {
              _isLoaded = true;
              _loadError = null;
            });
          }
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint(
            'AdMob banner failed: code=${error.code}, domain=${error.domain}, '
            'message=${error.message}.',
          );
          ad.dispose();
          if (mounted) {
            setState(() {
              _bannerAd = null;
              _loadError = error;
              _isLoaded = false;
            });
            if (_retryCount < _maxRetries) {
              _retryCount++;
              Future.delayed(const Duration(seconds: 3), () {
                if (mounted) _loadAd();
              });
            }
          }
        },
      ),
    );
    if (mounted) _bannerAd!.load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded || _bannerAd == null) {
      return SizedBox(
        height: AdSize.banner.height.toDouble(),
        child: _loadError != null && _retryCount >= _maxRetries
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    'Ad unavailable (${_loadError!.code})',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : const Center(child: SizedBox.shrink()),
      );
    }
    return SizedBox(
      width: _bannerAd!.size.width.toDouble(),
      height: _bannerAd!.size.height.toDouble(),
      child: AdWidget(ad: _bannerAd!),
    );
  }
}
