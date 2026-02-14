import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../cast/cast_helper.dart';
import '../localization.dart';
import '../models.dart';
import '../screens/player_screen.dart';
import '../screens/recording_detail_screen.dart';
import '../screens/settings_screen.dart';
import '../state/player_state.dart';
import '../state/radio_state.dart';
import '../state/recording_state.dart';
import '../state/settings_state.dart';
import 'control_button.dart';
import 'country_dropdown.dart';
import 'lcd_panel.dart';
import 'tapered_slider.dart';

/// LCD panel section with controls for the home screen.
class HomeLcdSection extends StatelessWidget {
  const HomeLcdSection({
    super.key,
    required this.lcdData,
    required this.strings,
    required this.selectedStation,
    required this.displayStation,
    required this.currentRecording,
    required this.canRecord,
    required this.canControlRecording,
    required this.isPowerOn,
    required this.blinkController,
    required this.recordingsBlinkController,
    required this.voiceBlinkController,
    required this.tabController,
    required this.stationSearchController,
    required this.recordingSearchController,
  });

  final LcdDisplayData lcdData;
  final AppLocalizations strings;
  final RadioStation? selectedStation;
  final RadioStation? displayStation;
  final RecordingItem? currentRecording;
  final bool canRecord;
  final bool canControlRecording;
  final bool isPowerOn;
  final AnimationController blinkController;
  final AnimationController recordingsBlinkController;
  final AnimationController voiceBlinkController;
  final TabController tabController;
  final TextEditingController stationSearchController;
  final TextEditingController recordingSearchController;

  @override
  Widget build(BuildContext context) {
    final radioState = context.watch<RadioState>();
    final recorder = context.watch<RecordingState>();
    final player = context.watch<AppPlayerState>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context)
                .colorScheme
                .outline
                .withValues(alpha: 0.4),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LcdPanel(
              data: lcdData,
              castTooltip: strings.castTo,
              onCastTap: CastHelper.isSupported
                  ? () async {
                      final station = displayStation ?? selectedStation;
                      await CastHelper.showDevicePickerAndCast(
                        context,
                        station: station,
                        noSourceMessage: strings.castNoSource,
                        noDevicesMessage: strings.castNoDevices,
                        castingToMessage: strings.castTo,
                        castSuccessMessage: station != null
                            ? '${strings.castTo} ${station.name}'
                            : strings.castTo,
                        castFailedMessage: strings.castFailed,
                        castOpenInChromeMessage: strings.castOpenInChrome,
                      );
                    }
                  : () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(strings.castComingSoon)),
                      );
                    },
              onTap: () {
                if (currentRecording != null) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          RecordingDetailScreen(item: currentRecording!),
                    ),
                  );
                  return;
                }
                if (displayStation != null && isPowerOn) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          PlayerScreen(station: displayStation!),
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: 8),
            CountryDropdown(
              selected: radioState.selectedCountry,
              onChanged: (country) {
                if (country != null) {
                  radioState.selectCountry(country);
                }
              },
            ),
            const SizedBox(height: 6),
            _buildTopControlsRow(context, radioState, recorder, player),
            const SizedBox(height: 6),
            _buildBottomControlsRow(context, recorder, player),
            if (recorder.errorMessageKey != null) ...[
              const SizedBox(height: 8),
              Text(
                strings.recordingErrorMessage(recorder.errorMessageKey)!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTopControlsRow(
    BuildContext context,
    RadioState radioState,
    RecordingState recorder,
    AppPlayerState player,
  ) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ControlButton(
            child: Icon(
              Icons.power_settings_new,
              color: selectedStation == null
                  ? Colors.grey
                  : (isPowerOn ? Colors.red : Colors.grey),
            ),
            onPressed: selectedStation == null
                ? null
                : () async {
                    if (player.isPlaying) {
                      if (recorder.isRecording) {
                        await recorder.stopRecording();
                      } else if (recorder.isVoiceRecording) {
                        await recorder.stopVoiceRecording();
                      }
                      await player.pause();
                    } else {
                      if (player.currentStation != null &&
                          player.currentStation != selectedStation &&
                          recorder.isRecording) {
                        await recorder.stopRecording();
                      }
                      await player.play(selectedStation!);
                    }
                  },
          ),
          const SizedBox(width: 8),
          ControlButton(
            child: AnimatedBuilder(
              animation: blinkController,
              builder: (context, child) {
                final shouldBlink = recorder.isRecording;
                return Opacity(
                  opacity: shouldBlink ? blinkController.value : 1.0,
                  child: child,
                );
              },
              child: Icon(
                Icons.fiber_manual_record,
                color: recorder.isRecording ? Colors.red : null,
              ),
            ),
            onPressed: canRecord
                ? () async {
                    if (recorder.isRecording) {
                      await recorder.stopRecording();
                      if (recorder.shouldResumePlayback &&
                          selectedStation != null) {
                        await player.play(selectedStation!);
                      }
                      return;
                    }
                    final station = selectedStation;
                    if (station == null) {
                      return;
                    }
                    final settings = context.read<SettingsState>();
                    final mode = settings.recordingMode;
                    recorder.setShouldResumePlayback(false);
                    final playWithRecordingTee = mode == RecordingMode.withBackground && !kIsWeb
                        ? (void Function(Map<String, String>) onHeaders,
                                void Function(List<int>) onChunk) =>
                            player.play(
                              station,
                              recordOnHeaders: onHeaders,
                              recordOnChunk: onChunk,
                              onProxyFallback: () => recorder.stopRecording(),
                            )
                        : null;
                    if (mode == RecordingMode.withBackground && playWithRecordingTee == null) {
                      if (!player.isPlaying || player.currentStation != station) {
                        await player.play(station);
                      }
                    }
                    await recorder.startRecording(
                      station,
                      mode: mode,
                      onDataUsage: mode == RecordingMode.streamOnly
                          ? (bytes) => player.addSessionBytes(bytes)
                          : null,
                      playWithRecordingTee: playWithRecordingTee,
                    );
                  }
                : null,
          ),
          const SizedBox(width: 8),
          ControlButton(
            child: const Icon(Icons.refresh),
            onPressed: radioState.selectedCountry == null
                ? null
                : () => radioState.refreshStations(),
          ),
          const SizedBox(width: 8),
          ControlButton(
            child: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const SettingsScreen(),
                ),
              );
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context)
                      .colorScheme
                      .outline
                      .withValues(alpha: 0.5),
                ),
              ),
              alignment: Alignment.center,
              child: ClipRect(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: SizedBox(
                    height: 20,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 4,
                        overlayShape: SliderComponentShape.noOverlay,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                          disabledThumbRadius: 6,
                        ),
                        trackShape: const TaperedSliderTrackShape(
                          minHeight: 2,
                          maxHeight: 4,
                          horizontalInset: 2,
                        ),
                      ),
                      child: Slider(
                        value: player.volume,
                        min: 0,
                        max: 1,
                        onChanged: player.setVolume,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControlsRow(
    BuildContext context,
    RecordingState recorder,
    AppPlayerState player,
  ) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ControlButton(
            child: AnimatedBuilder(
              animation: recordingsBlinkController,
              builder: (context, child) {
                return Opacity(
                  opacity: tabController.index == 1
                      ? recordingsBlinkController.value
                      : 1.0,
                  child: child,
                );
              },
              child: const Icon(Icons.folder),
            ),
            onPressed: () => tabController.animateTo(
              tabController.index == 1 ? 0 : 1,
            ),
          ),
          const SizedBox(width: 8),
          ControlButton(
            child: const Icon(Icons.fast_rewind),
            onPressed: canControlRecording
                ? () =>
                    player.seekRelative(const Duration(seconds: -10))
                : null,
          ),
          const SizedBox(width: 8),
          ControlButton(
            child: const Icon(Icons.fast_forward),
            onPressed: canControlRecording
                ? () => player.seekRelative(const Duration(seconds: 10))
                : null,
          ),
          const SizedBox(width: 8),
          ControlButton(
            child: AnimatedBuilder(
              animation: voiceBlinkController,
              builder: (context, child) {
                return Opacity(
                  opacity: recorder.isVoiceRecording
                      ? voiceBlinkController.value
                      : 1.0,
                  child: child,
                );
              },
              child: Icon(
                recorder.isVoiceRecording
                    ? Icons.fiber_manual_record
                    : Icons.mic,
                color: recorder.isVoiceRecording ? Colors.red : null,
              ),
            ),
            onPressed: () async {
              if (recorder.isVoiceRecording) {
                await recorder.stopVoiceRecording();
              } else {
                final wasRadioPlaying = player.isPlaying;
                await recorder.startVoiceRecording();
                if (wasRadioPlaying) {
                  Future.delayed(
                    const Duration(milliseconds: 400),
                    () async {
                      if (!context.mounted) return;
                      final p = context.read<AppPlayerState>();
                      final r = context.read<RecordingState>();
                      final station = context
                          .read<RadioState>()
                          .selectedStation ??
                          p.currentStation;
                      if (r.isVoiceRecording &&
                          station != null &&
                          !p.isPlaying) {
                        await p.play(station);
                      }
                    },
                  );
                }
              }
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 40,
              child: AnimatedBuilder(
                animation: tabController,
                builder: (context, _) {
                  final isRecordings = tabController.index == 1;
                  return TextField(
                    controller: isRecordings
                        ? recordingSearchController
                        : stationSearchController,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: isRecordings
                          ? strings.searchRecordings
                          : strings.searchStations,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  border: const OutlineInputBorder(),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
