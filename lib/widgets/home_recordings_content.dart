import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../localization.dart';
import '../screens/recording_detail_screen.dart';
import '../state/player_state.dart';
import '../state/recording_state.dart';
import 'recording_list_item.dart';

/// Recordings list content for the home screen.
class HomeRecordingsContent extends StatelessWidget {
  const HomeRecordingsContent({
    super.key,
    required this.strings,
    required this.recordingSearchQuery,
    required this.listController,
    required this.listPaddingBottom,
  });

  final AppLocalizations strings;
  final String recordingSearchQuery;
  final ScrollController listController;
  final double listPaddingBottom;

  @override
  Widget build(BuildContext context) {
    final recorder = context.watch<RecordingState>();
    final player = context.watch<AppPlayerState>();

    if (recorder.visibleRecordings.isEmpty) {
      return Center(child: Text(strings.noRecordings));
    }

    return Column(
      children: [
        Expanded(
          child: Builder(
            builder: (context) {
              final query = recordingSearchQuery.toLowerCase();
              final filtered = recorder.recordings.where((item) {
                final name = item.name.toLowerCase();
                final station = item.stationName.toLowerCase();
                return query.isEmpty ||
                    name.contains(query) ||
                    station.contains(query);
              }).toList();
              final visible = recorder.visibleRecordings;
              final displayList = query.isEmpty
                  ? visible
                  : recorder.sortRecordingsByFavorite(filtered);
              final showLoadMore =
                  query.isEmpty && recorder.hasMoreRecordings;
              if (displayList.isEmpty) {
                return Center(child: Text(strings.noRecordings));
              }
              return Scrollbar(
                controller: listController,
                thumbVisibility: true,
                interactive: true,
                child: RefreshIndicator(
                  onRefresh: () async => recorder.reloadRecordings(),
                  child: ListView.separated(
                    controller: listController,
                    padding: EdgeInsets.only(bottom: listPaddingBottom),
                    itemCount: displayList.length + (showLoadMore ? 1 : 0),
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      if (showLoadMore && index >= displayList.length) {
                        return Center(
                          child: TextButton(
                            onPressed: () => recorder.loadMoreRecordings(),
                            child: Text(strings.loadMore),
                          ),
                        );
                      }
                      final item = displayList[index];
                      return RecordingListItem(
                        item: item,
                        strings: strings,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  RecordingDetailScreen(item: item),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ),
        if (player.currentRecordingPath != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: StreamBuilder<Duration>(
              stream: player.positionStream,
              initialData: Duration.zero,
              builder: (context, positionSnap) {
                return StreamBuilder<Duration?>(
                  stream: player.durationStream,
                  builder: (context, durationSnap) {
                    final position =
                        positionSnap.data ?? Duration.zero;
                    final duration =
                        durationSnap.data ?? Duration.zero;
                    final rawMax =
                        duration.inMilliseconds.toDouble();
                    final max = rawMax < 1 ? 1.0 : rawMax;
                    final rawValue =
                        position.inMilliseconds.toDouble();
                    final value = rawValue > max ? max : rawValue;
                    return Slider(
                      value: value,
                      max: max,
                      onChanged: (v) => player.seekRelative(
                        Duration(milliseconds: v.toInt()) - position,
                      ),
                    );
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}
