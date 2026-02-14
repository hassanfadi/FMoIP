import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../localization.dart';
import '../models.dart';
import '../state/player_state.dart';
import '../state/radio_state.dart';
import '../state/recording_state.dart';
import '../widgets/widgets.dart';

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key, required this.station});

  final RadioStation station;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final player = context.watch<AppPlayerState>();
    final radioState = context.watch<RadioState>();
    final isCurrent = player.currentStation == station;
    final isPlaying = isCurrent && player.isPlaying;

    return Scaffold(
      appBar: AppBar(title: Text(station.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StationFavicon(
                faviconUrl: station.faviconUrl,
                size: 64,
                borderRadius: 8,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  station.frequency.isNotEmpty
                      ? station.frequency
                      : strings.stationFrequency,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          InfoTile(
            label: strings.stationFrequency,
            value: station.frequency.isNotEmpty
                ? station.frequency
                : '-',
          ),
          InfoTile(
            label: strings.stationCountry,
            value: strings.countryDisplayName(station.country),
          ),
          InfoTile(label: strings.stationLanguage, value: station.language),
          InfoTile(label: strings.stationTags, value: station.tags),
          InfoTile(label: strings.stationBitrate, value: station.bitrate),
          InfoTile(label: strings.stationLink, value: station.streamUrl),
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
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(
                  radioState.isFavoriteStation(station)
                      ? Icons.favorite
                      : Icons.favorite_border,
                  color: Colors.redAccent,
                  size: 28,
                ),
                iconSize: 28,
                onPressed: () => radioState.toggleFavoriteStation(station),
                tooltip: strings.favorite,
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                iconSize: 28,
                onPressed: () async {
                  if (isPlaying) {
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
