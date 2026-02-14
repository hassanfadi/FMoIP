import 'package:flutter/material.dart';

class MarqueeText extends StatefulWidget {
  const MarqueeText({super.key, required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  double _textWidth = 0;
  double _availableWidth = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void didUpdateWidget(covariant MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.style != widget.style) {
      _restartAnimation();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _restartAnimation() {
    _controller.stop();
    _controller.reset();
    if (_textWidth > _availableWidth && _availableWidth > 0) {
      final overflow = _textWidth - _availableWidth;
      final durationMs = (overflow / 40 * 1000).clamp(3000, 12000).toInt();
      _controller.duration = Duration(milliseconds: durationMs);
      _controller.repeat(reverse: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _availableWidth = constraints.maxWidth;
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout();
        _textWidth = painter.width;
        WidgetsBinding.instance.addPostFrameCallback((_) => _restartAnimation());

        if (_textWidth <= _availableWidth || _availableWidth == 0) {
          return Text(
            widget.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: widget.style,
          );
        }

        final overflow = _textWidth - _availableWidth;
        return ClipRect(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final offset = overflow * _controller.value;
              return Transform.translate(
                offset: Offset(-offset, 0),
                child: child,
              );
            },
            child: Text(
              widget.text,
              maxLines: 1,
              style: widget.style,
            ),
          ),
        );
      },
    );
  }
}
