import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../localization.dart';
import '../models.dart';
import '../state/player_state.dart';
import '../state/recording_state.dart';
import '../utils.dart';
import 'recording_list_icon.dart';

/// Recording list item with swipe-right-to-play/pause and icon actions.
class RecordingListItem extends StatelessWidget {
  const RecordingListItem({
    super.key,
    required this.item,
    required this.strings,
    required this.onTap,
  });

  final RecordingItem item;
  final AppLocalizations strings;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<AppPlayerState>();
    final recorder = context.read<RecordingState>();
    final isCurrentRecording = player.currentRecordingPath == item.path;
    final isPlaying = isCurrentRecording && player.isPlaying;
    final isLoading = isCurrentRecording && player.isLoading;
    final subtitleParts = <String>[
      item.stationName,
      if (item.durationSeconds != null)
        formatDuration(Duration(seconds: item.durationSeconds!)),
    ];
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final playBackground = _RecordingSwipeBackground(
      icon: isPlaying ? Icons.pause : Icons.play_arrow,
      color: isPlaying ? Colors.orange : Colors.green,
    );
    final pauseBackground = _RecordingSwipeBackground(
      icon: Icons.pause,
      color: Colors.orange,
      alignRight: true,
    );
    const emptyBackground = _RecordingSwipeBackground(icon: Icons.arrow_back);
    final playDirection =
        isRtl ? DismissDirection.endToStart : DismissDirection.startToEnd;
    final pauseDirection =
        isRtl ? DismissDirection.startToEnd : DismissDirection.endToStart;
    final secondaryBg = isPlaying ? pauseBackground : emptyBackground;

    return Dismissible(
      key: ValueKey(item.path),
      background: isRtl ? secondaryBg : playBackground,
      secondaryBackground: isRtl ? playBackground : secondaryBg,
      confirmDismiss: (direction) => _confirmDismiss(
        context,
        direction,
        playDirection,
        pauseDirection,
        item,
        isCurrentRecording,
        isPlaying,
        isLoading,
        player,
      ),
      child: ListTile(
      leading: RecordingListIcon(item: item),
      title: Row(
        children: [
          Expanded(
            child: Text(
              item.name,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                style: IconButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.all(6),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                iconSize: 20,
                icon: const Icon(Icons.drive_file_rename_outline),
                tooltip: strings.renameFileTitle,
                onPressed: () => _onRenamePressed(context, item, recorder, strings),
              ),
              IconButton(
                style: IconButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.all(6),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                iconSize: 20,
                icon: const Icon(Icons.delete, color: Colors.redAccent),
                tooltip: strings.delete,
                onPressed: () => _onDeletePressed(context, item, recorder, strings),
              ),
              IconButton(
                style: IconButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.all(6),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                iconSize: 20,
                icon: Icon(
                  recorder.isFavoriteRecording(item)
                      ? Icons.favorite
                      : Icons.favorite_border,
                  color: Colors.redAccent,
                ),
                onPressed: () => recorder.toggleFavoriteRecording(item),
              ),
              IconButton(
                style: IconButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.all(6),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                iconSize: 24,
                icon: (isCurrentRecording && isPlaying)
                    ? const Icon(Icons.pause)
                    : isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow),
                onPressed: () => _onPlayPressed(
                  context,
                  item,
                  isCurrentRecording,
                  isPlaying,
                  isLoading,
                  player,
                ),
              ),
            ],
          ),
        ],
      ),
      subtitle: subtitleParts.isNotEmpty
          ? Text(subtitleParts.join(' • '))
          : null,
      onTap: onTap,
    ),
    );
  }
}

Future<bool> _confirmDismiss(
  BuildContext context,
  DismissDirection direction,
  DismissDirection playDirection,
  DismissDirection pauseDirection,
  RecordingItem item,
  bool isCurrentRecording,
  bool isPlaying,
  bool isLoading,
  AppPlayerState player,
) async {
  if (direction == pauseDirection && isCurrentRecording && isPlaying) {
    WidgetsBinding.instance.addPostFrameCallback((_) => player.pause());
    return false;
  }
  if (direction != playDirection) return false;
  if (isLoading) return false;
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    if (isCurrentRecording && isPlaying) {
      await player.pause();
    } else if (isCurrentRecording && !isPlaying) {
      await player.resume();
    } else {
      await player.playRecording(item.path);
    }
  });
  return false;
}

class _RecordingSwipeBackground extends StatelessWidget {
  const _RecordingSwipeBackground({
    required this.icon,
    this.color = Colors.green,
    this.alignRight = false,
  });

  final IconData icon;
  final Color color;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    final isAction = icon != Icons.arrow_back;
    return Container(
      color: isAction ? color.withValues(alpha: 0.15) : Colors.transparent,
      alignment: isAction
          ? (alignRight ? Alignment.centerRight : Alignment.centerLeft)
          : Alignment.centerRight,
      padding: isAction
          ? (alignRight
              ? const EdgeInsets.only(right: 16)
              : const EdgeInsets.only(left: 16))
          : const EdgeInsets.only(right: 16),
      child: isAction ? Icon(icon, color: color, size: 28) : const SizedBox.shrink(),
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
    builder: (context) {
      return AlertDialog(
        title: Text(strings.renameFileTitle),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(labelText: strings.nameHint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(strings.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(strings.save),
          ),
        ],
      );
    },
  );
  if (result != null) {
    await recorder.renameRecordingFile(item, result);
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
    builder: (context) {
      return AlertDialog(
        title: Text(strings.deleteRecordingTitle),
        content: Text(strings.deleteRecordingBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.delete),
          ),
        ],
      );
    },
  );
  if (confirm == true) {
    recorder.deleteRecording(item);
  }
}

Future<void> _onPlayPressed(
  BuildContext context,
  RecordingItem item,
  bool isCurrentRecording,
  bool isPlaying,
  bool isLoading,
  AppPlayerState player,
) async {
  if (isCurrentRecording && isPlaying) {
    await player.pause();
    return;
  }
  if (isCurrentRecording && !isPlaying) {
    await player.resume();
    return;
  }
  if (isLoading) return;
  await player.playRecording(item.path);
}
