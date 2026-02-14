import 'package:flutter/material.dart';

/// Banner showing the auto-off countdown when the radio timer is active.
class HomeAutoOffBanner extends StatelessWidget {
  const HomeAutoOffBanner({
    super.key,
    required this.remaining,
    required this.formattedText,
  });

  final Duration remaining;
  final String formattedText;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          child: Center(
            child: Text(
              formattedText,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w500,
              ),
            ),
        ),
      ),
    );
  }
}
