import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../localization.dart';
import '../state/radio_state.dart';
import '../state/recording_state.dart';
import 'data_saver_suggestion_banner.dart';
import 'home_recordings_content.dart';
import 'home_stations_content.dart';

/// Main content area: LCD section, loading/error, and tabs (stations | recordings).
class HomeMainContent extends StatelessWidget {
  const HomeMainContent({
    super.key,
    required this.constraints,
    required this.lcdSection,
    required this.strings,
    required this.tabController,
    required this.stationSearchQuery,
    required this.recordingSearchQuery,
    required this.stationListController,
    required this.recordingsListController,
    required this.listPaddingBottom,
  });

  final BoxConstraints constraints;
  final Widget lcdSection;
  final double listPaddingBottom;
  final AppLocalizations strings;
  final TabController tabController;
  final String stationSearchQuery;
  final String recordingSearchQuery;
  final ScrollController stationListController;
  final ScrollController recordingsListController;

  @override
  Widget build(BuildContext context) {
    final radioState = context.watch<RadioState>();
    final recorder = context.watch<RecordingState>();
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    return Column(
      children: [
        isLandscape
            ? ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight * 0.48,
                ),
                child: SingleChildScrollView(child: lcdSection),
              )
            : lcdSection,
        const DataSaverSuggestionBanner(),
        if (radioState.isLoading) const LinearProgressIndicator(),
        if (radioState.errorMessage != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              radioState.errorMessage!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        Expanded(
          child: Column(
            children: [
              TabBar(
                controller: tabController,
                tabs: [
                  Tab(text: strings.stationsCount(radioState.stations.length)),
                  Tab(text: strings.recordingsCount(recorder.recordings.length)),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: tabController,
                  children: [
                    HomeStationsContent(
                      strings: strings,
                      stationSearchQuery: stationSearchQuery,
                      listController: stationListController,
                      listPaddingBottom: listPaddingBottom,
                    ),
                    HomeRecordingsContent(
                      strings: strings,
                      recordingSearchQuery: recordingSearchQuery,
                      listController: recordingsListController,
                      listPaddingBottom: listPaddingBottom,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
