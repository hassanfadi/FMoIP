import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Displays a station's favicon with local caching, or the default radio icon.
class StationFavicon extends StatelessWidget {
  const StationFavicon({
    super.key,
    required this.faviconUrl,
    this.size = 40,
    this.borderRadius = 8,
  });

  final String faviconUrl;
  final double size;
  final double borderRadius;

  static bool _hasValidFavicon(String url) {
    final trimmed = url.trim();
    return trimmed.isNotEmpty && trimmed.toLowerCase() != 'null';
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: _hasValidFavicon(faviconUrl)
          ? ClipRRect(
              borderRadius: BorderRadius.circular(borderRadius),
              child: CachedNetworkImage(
                imageUrl: faviconUrl,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Image.asset(
                  'assets/icons/radio_icon.png',
                  fit: BoxFit.contain,
                ),
              ),
            )
          : Image.asset(
              'assets/icons/radio_icon.png',
              fit: BoxFit.contain,
            ),
    );
  }
}
