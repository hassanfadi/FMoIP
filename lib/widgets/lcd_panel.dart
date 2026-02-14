import 'package:flutter/material.dart';

import 'marquee_text.dart';

/// Display data for the LCD-style radio panel.
class LcdDisplayData {
  const LcdDisplayData({
    required this.name,
    required this.frequency,
    required this.country,
    required this.language,
    required this.isRecordingPlayback,
    this.sessionDataMb = 0,
  });

  final String name;
  final String frequency;
  final String country;
  final String language;
  final bool isRecordingPlayback;
  /// Data used this session (MB), for users with limited internet.
  final double sessionDataMb;
}

/// The green LCD-style display only (no outer container).
/// Use this when embedding inside another container.
class LcdPanel extends StatelessWidget {
  const LcdPanel({
    super.key,
    required this.data,
    required this.onTap,
    this.onCastTap,
    this.castTooltip,
  });

  final LcdDisplayData data;
  final VoidCallback? onTap;
  final VoidCallback? onCastTap;
  final String? castTooltip;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: _LcdDisplayContent(
        data: data,
        onCastTap: onCastTap,
        castTooltip: castTooltip,
      ),
    );
  }
}

class _LcdDisplayContent extends StatelessWidget {
  const _LcdDisplayContent({
    required this.data,
    this.onCastTap,
    this.castTooltip,
  });

  final LcdDisplayData data;
  final VoidCallback? onCastTap;
  final String? castTooltip;

  static const _lcdStyle = TextStyle(
    fontFamily: 'Courier',
    fontWeight: FontWeight.bold,
    color: Color(0xFF1F3D1A),
  );

  @override
  Widget build(BuildContext context) {
    final dataUsageDisplay = '${data.sessionDataMb.toStringAsFixed(1)} MB';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      decoration: BoxDecoration(
        color: const Color(0xFFB9F5A6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF5B8F49), width: 2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7EC46A).withValues(alpha: 0.6),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Transform.translate(
                offset: const Offset(-4, 0),
                child: Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  child: Image.asset(
                  'assets/icons/lcd_radio_icon.png',
                  width: 20,
                  height: 20,
                  fit: BoxFit.contain,
                ),
              ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: MarqueeText(
                  key: ValueKey(data.name),
                  text: data.name,
                  style: _lcdStyle.copyWith(fontSize: 16),
                ),
              ),
              if (onCastTap != null)
                Transform.translate(
                  offset: const Offset(4, 0),
                  child: IconButton(
                  icon: const Icon(Icons.cast, size: 20),
                  color: const Color(0xFF1F3D1A),
                  style: IconButton.styleFrom(
                    minimumSize: const Size(32, 32),
                    padding: EdgeInsets.zero,
                  ),
                  tooltip: castTooltip,
                  onPressed: onCastTap,
                ),
                ),
            ],
          ),
          const SizedBox(height: 0),
          SizedBox(
            height: 20,
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  data.frequency,
                  style: _lcdStyle.copyWith(
                    fontSize: data.isRecordingPlayback ? 22 : 32,
                    letterSpacing: data.isRecordingPlayback ? 1 : 2,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 0),
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        data.country,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _lcdStyle.copyWith(fontSize: 15),
                      ),
                    ),
                    if (data.language.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          data.language,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _lcdStyle.copyWith(fontSize: 15),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                dataUsageDisplay,
                style: _lcdStyle.copyWith(fontSize: 15),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
