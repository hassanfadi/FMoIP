import 'package:flutter/material.dart';

import '../models.dart';

class RecordingListIcon extends StatelessWidget {
  const RecordingListIcon({super.key, required this.item});

  final RecordingItem item;

  bool get _isVoiceNote => item.stationName == 'Voice note';

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            backgroundImage: _isVoiceNote
                ? null
                : const AssetImage('assets/icons/radio_icon.png'),
            child: _isVoiceNote ? const Icon(Icons.mic) : null,
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: CircleAvatar(
              radius: 10,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Icon(
                Icons.save,
                size: 14,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
