import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../localization.dart';
import '../models.dart';
import '../state/player_state.dart';
import '../state/recording_state.dart';
import '../utils.dart';
import '../widgets/widgets.dart';

class RecordingDetailScreen extends StatelessWidget {
  const RecordingDetailScreen({super.key, required this.item});

  final RecordingItem item;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final player = context.watch<AppPlayerState>();
    final recorder = context.watch<RecordingState>();
    final isPlaying =
        player.currentRecordingPath == item.path && player.isPlaying;
    final isLoading =
        player.isLoading && player.currentRecordingPath == item.path;
    final subtitleParts = <String>[
      item.stationName,
      if (item.durationSeconds != null)
        formatDuration(Duration(seconds: item.durationSeconds!)),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(item.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            subtitleParts.join(' • '),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          if (item.stationName.isNotEmpty && item.stationName != 'Voice note')
            InfoTile(label: 'Station', value: item.stationName),
          InfoTile(
            label: strings.stationDate,
            value: formatRecordingTime(item.createdAt),
          ),
          InfoTile(
            label: strings.duration,
            value: formatDuration(Duration(seconds: item.durationSeconds ?? 0)),
          ),
          InfoTile(label: strings.recordings, value: item.sizeLabel),
          const SizedBox(height: 16),
          if (player.errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                player.errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(Icons.drive_file_rename_outline, size: 28),
                onPressed: () => _onRenamePressed(context, item, recorder, strings),
                tooltip: strings.renameFileTitle,
              ),
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.redAccent, size: 28),
                onPressed: () => _onDeletePressed(context, item, recorder, strings),
                tooltip: strings.delete,
              ),
              IconButton(
                icon: Icon(
                  recorder.isFavoriteRecording(item)
                      ? Icons.favorite
                      : Icons.favorite_border,
                  color: Colors.redAccent,
                  size: 28,
                ),
                onPressed: () => recorder.toggleFavoriteRecording(item),
              ),
              IconButton(
                iconSize: 32,
                icon: (isLoading && !isPlaying)
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(isPlaying ? Icons.pause : Icons.play_arrow, size: 28),
                onPressed: () async {
                  if (isLoading && !isPlaying) return;
                  if (isPlaying) {
                    await player.pause();
                    return;
                  }
                  if (player.currentRecordingPath == item.path) {
                    await player.resume();
                    return;
                  }
                  await player.playRecording(item.path);
                },
                tooltip: isPlaying ? strings.pause : strings.play,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> _onRenamePressed(
  BuildContext context,
  RecordingItem item,
  RecordingState recorder,
  AppLocalizations strings,
) async {
  final controller = TextEditingController(text: item.name);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: Text(strings.renameFileTitle),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(labelText: strings.nameHint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(strings.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: Text(strings.save),
          ),
        ],
      );
    },
  );
  if (result != null) {
    await recorder.renameRecordingFile(item, result);
    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }
}

Future<void> _onDeletePressed(
  BuildContext context,
  RecordingItem item,
  RecordingState recorder,
  AppLocalizations strings,
) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: Text(strings.deleteRecordingTitle),
        content: Text(strings.deleteRecordingBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(strings.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(strings.delete),
          ),
        ],
      );
    },
  );
  if (confirm == true) {
    recorder.deleteRecording(item);
    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }
}
