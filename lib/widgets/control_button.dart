import 'package:flutter/material.dart';

class ControlButton extends StatelessWidget {
  const ControlButton({super.key, required this.child, this.onPressed});

  final Widget child;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final iconColor = Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      width: 40,
      height: 40,
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
          ),
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.35),
                  blurRadius: 4,
                  offset: const Offset(0, -1),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: IconTheme(
              data: IconThemeData(size: 22, color: iconColor),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
