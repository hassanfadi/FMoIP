import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../localization.dart';
import '../screens/player_screen.dart';
import '../state/radio_state.dart';
import 'station_list_item.dart';

/// Stations list content for the home screen.
class HomeStationsContent extends StatelessWidget {
  const HomeStationsContent({
    super.key,
    required this.strings,
    required this.stationSearchQuery,
    required this.listController,
    required this.listPaddingBottom,
  });

  final AppLocalizations strings;
  final String stationSearchQuery;
  final ScrollController listController;
  final double listPaddingBottom;

  @override
  Widget build(BuildContext context) {
    final radioState = context.watch<RadioState>();

    if (radioState.stations.isEmpty) {
      return Center(child: Text(strings.noStations));
    }

    final query = stationSearchQuery.toLowerCase();
    final sourceStations = radioState.allStations;
    final filtered = sourceStations.where((station) {
      final name = station.name.toLowerCase();
      final freq = station.frequency.toLowerCase();
      final tags = station.tags.toLowerCase();
      return query.isEmpty ||
          name.contains(query) ||
          freq.contains(query) ||
          tags.contains(query);
    }).toList();
    final visible = radioState.visibleStations;
    final displayList = query.isEmpty
        ? visible
        : radioState.sortStationsByFavorite(filtered);
    final showLoadMore = query.isEmpty && radioState.hasMoreStations;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: AnimatedPadding(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Scrollbar(
              controller: listController,
              thumbVisibility: true,
              interactive: true,
              child: RefreshIndicator(
                onRefresh: () async => radioState.refreshStations(),
                child: ListView.separated(
                  controller: listController,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.only(bottom: listPaddingBottom),
                  itemCount: displayList.isEmpty ? 1 : displayList.length + (showLoadMore ? 1 : 0),
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    if (displayList.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: Center(
                          child: Text(strings.noStations),
                        ),
                      );
                    }
                    if (showLoadMore && index >= displayList.length) {
                      return Center(
                        child: TextButton(
                          onPressed: () => radioState.loadMoreStations(),
                          child: Text(strings.loadMore),
                        ),
                      );
                    }
                    final station = displayList[index];
                    return StationListItem(
                          station: station,
                          strings: strings,
                          onTap: () {
                            radioState.selectStation(station);
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    PlayerScreen(station: station),
                              ),
                            );
                          },
                        );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
