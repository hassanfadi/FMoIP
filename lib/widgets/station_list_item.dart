import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../localization.dart';
import '../models.dart';
import '../state/player_state.dart';
import '../state/radio_state.dart';
import '../state/recording_state.dart';
import 'station_favicon.dart';

/// A dismissible station list item with swipe-right-to-play action.
class StationListItem extends StatelessWidget {
  const StationListItem({
    super.key,
    required this.station,
    required this.strings,
    required this.onTap,
  });

  final RadioStation station;
  final AppLocalizations strings;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radioState = context.watch<RadioState>();
    final player = context.watch<AppPlayerState>();
    final isCurrent = player.currentStation == station;
    final isPlaying = isCurrent && player.isPlaying;
    final isRtl =
        Directionality.of(context) == TextDirection.rtl;
    final swipeBackground = _SwipeBackground(
      color: isPlaying ? Colors.orange : Colors.green,
      icon: isPlaying ? Icons.pause : Icons.play_arrow,
      alignment: isRtl ? Alignment.centerRight : Alignment.centerLeft,
      padding: isRtl
          ? const EdgeInsets.only(right: 16)
          : const EdgeInsets.only(left: 16),
    );
    final playDirection =
        isRtl ? DismissDirection.endToStart : DismissDirection.startToEnd;

    return Dismissible(
      key: ValueKey(station.streamUrl),
      direction: playDirection,
      background: swipeBackground,
      secondaryBackground: null,
      confirmDismiss: (direction) => _confirmDismiss(
        context,
        direction,
        playDirection,
        station,
        isPlaying,
        radioState,
        player,
      ),
      child: ListTile(
        leading: StationFavicon(
          faviconUrl: station.faviconUrl,
          size: 40,
          borderRadius: 8,
        ),
        title: Text(
          station.frequency.isNotEmpty
              ? '${station.name} (${station.frequency})'
              : station.name,
        ),
        subtitle: Text(
          '${station.frequency} • ${strings.countryDisplayName(station.country)}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              icon: Icon(
                radioState.isFavoriteStation(station)
                    ? Icons.favorite
                    : Icons.favorite_border,
                color: Colors.redAccent,
              ),
              onPressed: () =>
                  radioState.toggleFavoriteStation(station),
            ),
            IconButton(
              icon: Icon(
                isPlaying ? Icons.pause : Icons.play_arrow,
              ),
              onPressed: () => _onPlayPressed(
                context,
                station,
                isPlaying,
                radioState,
                player,
              ),
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

Future<bool> _confirmDismiss(
  BuildContext context,
  DismissDirection direction,
  DismissDirection playDirection,
  RadioStation station,
  bool isPlaying,
  RadioState radioState,
  AppPlayerState player,
) async {
  if (direction != playDirection) return false;
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    if (!context.mounted) return;
    radioState.selectStation(station);
    if (player.currentStation == station && player.isPlaying) {
      await player.pause();
    } else {
      final recorder = context.read<RecordingState>();
      if (player.currentStation != null &&
          player.currentStation != station &&
          recorder.isRecording) {
        await recorder.stopRecording();
      }
      await player.play(station);
    }
  });
  return false;
}

Future<void> _onPlayPressed(
  BuildContext context,
  RadioStation station,
  bool isPlaying,
  RadioState radioState,
  AppPlayerState player,
) async {
  if (isPlaying) {
    await player.pause();
    return;
  }
  radioState.selectStation(station);
  final recorder = context.read<RecordingState>();
  if (player.currentStation != null &&
      player.currentStation != station &&
      recorder.isRecording) {
    await recorder.stopRecording();
  }
  await player.play(station);
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.color,
    required this.icon,
    required this.alignment,
    required this.padding,
  });

  final Color color;
  final IconData icon;
  final Alignment alignment;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color == Colors.transparent
          ? Colors.transparent
          : color.withValues(alpha: 0.15),
      alignment: alignment,
      padding: padding,
      child: color == Colors.transparent
          ? const SizedBox.shrink()
          : Icon(icon, color: color, size: 28),
    );
  }
}
