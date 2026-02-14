import 'package:flutter/material.dart';

class TaperedSliderTrackShape extends SliderTrackShape {
  const TaperedSliderTrackShape({
    required this.minHeight,
    required this.maxHeight,
    this.horizontalInset = 0,
  });

  final double minHeight;
  final double maxHeight;
  final double horizontalInset;

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final trackHeight = maxHeight;
    final trackLeft = offset.dx + horizontalInset;
    final trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    final width = parentBox.size.width - (horizontalInset * 2);
    return Rect.fromLTWH(trackLeft, trackTop, width, trackHeight);
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 0,
  }) {
    final trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final trackLeft = trackRect.left;
    final trackRight = trackRect.right;
    final trackWidth = trackRect.width;
    if (trackWidth <= 0) {
      return;
    }

    final activePaint = Paint()
      ..color = sliderTheme.activeTrackColor ?? Colors.blue
      ..style = PaintingStyle.fill;
    final inactivePaint = Paint()
      ..color = sliderTheme.inactiveTrackColor ?? Colors.grey
      ..style = PaintingStyle.fill;

    double thicknessAt(double x) {
      final t = ((x - trackLeft) / trackWidth).clamp(0.0, 1.0);
      return minHeight + (maxHeight - minHeight) * t;
    }

    void drawSegment(double x1, double x2, Paint paint) {
      if (x2 <= x1) return;
      final h1 = thicknessAt(x1);
      final h2 = thicknessAt(x2);
      final yCenter = trackRect.center.dy;
      final path = Path()
        ..moveTo(x1, yCenter - h1 / 2)
        ..lineTo(x2, yCenter - h2 / 2)
        ..lineTo(x2, yCenter + h2 / 2)
        ..lineTo(x1, yCenter + h1 / 2)
        ..close();
      context.canvas.drawPath(path, paint);
    }

    final clampedThumbX = thumbCenter.dx.clamp(trackLeft, trackRight);
    if (textDirection == TextDirection.rtl) {
      drawSegment(clampedThumbX, trackRight, activePaint);
      drawSegment(trackLeft, clampedThumbX, inactivePaint);
    } else {
      drawSegment(trackLeft, clampedThumbX, activePaint);
      drawSegment(clampedThumbX, trackRight, inactivePaint);
    }
  }
}
