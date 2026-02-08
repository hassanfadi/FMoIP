import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:geolocator/geolocator.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:http/http.dart' as http;
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:provider/provider.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ad_config.dart';
import 'iap_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MobileAds.instance.initialize();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.fmoip.audio',
    androidNotificationChannelName: 'FMoIP Playback',
    androidNotificationOngoing: true,
  );
  // Allow radio to keep playing (ducked) when recording a voice note instead of pausing.
  try {
    final session = await AudioSession.instance;
    await session.configure(
      AudioSessionConfiguration.music().copyWith(
        androidWillPauseWhenDucked: false,
      ),
    );
  } catch (_) {
    // Use default session if configuration fails (avoids "Media server died" on some devices).
  }
  runApp(const FmoipApp());
}

class FmoipApp extends StatelessWidget {
  const FmoipApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsState()),
        ChangeNotifierProvider(create: (_) => RadioState()),
        ChangeNotifierProvider(create: (_) => PlayerState()),
        ChangeNotifierProvider(create: (_) => RecordingState()),
        ChangeNotifierProvider(create: (_) => SubscriptionState()),
      ],
      child: Consumer<SettingsState>(
        builder: (context, settings, _) {
          return MaterialApp(
            title: 'FMoIP',
            locale: settings.locale,
            themeMode: settings.themeMode,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
              useMaterial3: true,
            ),
            darkTheme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.indigo,
                brightness: Brightness.dark,
              ),
              useMaterial3: true,
            ),
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _blinkController;
  late final AnimationController _recordingsBlinkController;
  late final AnimationController _voiceBlinkController;
  Timer? _lcdTimer;
  late final TextEditingController _stationSearchController;
  late final TextEditingController _recordingSearchController;
  late final ScrollController _stationListController;
  late final ScrollController _recordingsListController;
  String _stationSearchQuery = '';
  String _recordingSearchQuery = '';
  int? _lastListPageSize;
  bool? _lastDataSaver;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _stationSearchController = TextEditingController();
    _stationSearchController.addListener(() {
      final next = _stationSearchController.text.trim();
      if (next != _stationSearchQuery) {
        setState(() {
          _stationSearchQuery = next;
        });
      }
    });
    _recordingSearchController = TextEditingController();
    _recordingSearchController.addListener(() {
      final next = _recordingSearchController.text.trim();
      if (next != _recordingSearchQuery) {
        setState(() {
          _recordingSearchQuery = next;
        });
      }
    });
    _stationListController = ScrollController();
    _recordingsListController = ScrollController();
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
      lowerBound: 0.3,
      upperBound: 1.0,
    );
    _recordingsBlinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
      lowerBound: 0.4,
      upperBound: 1.0,
    );
    _voiceBlinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
      lowerBound: 0.4,
      upperBound: 1.0,
    );
    _lcdTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _blinkController.dispose();
    _recordingsBlinkController.dispose();
    _voiceBlinkController.dispose();
    _lcdTimer?.cancel();
    _stationSearchController.dispose();
    _recordingSearchController.dispose();
    _stationListController.dispose();
    _recordingsListController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = context.watch<SettingsState>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final radioState = context.read<RadioState>();
      final recorder = context.read<RecordingState>();
      if (_lastListPageSize != settings.listPageSize) {
        _lastListPageSize = settings.listPageSize;
        radioState.setStationsPageSize(settings.listPageSize);
        recorder.setRecordingsPageSize(settings.listPageSize);
      }
      if (_lastDataSaver != settings.dataSaver) {
        _lastDataSaver = settings.dataSaver;
        radioState.setDataSaverEnabled(settings.dataSaver);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      final player = context.read<PlayerState>();
      final recorder = context.read<RecordingState>();
      player.stop();
      recorder.stopRecording();
      recorder.stopVoiceRecording();
      AudioService.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final radioState = context.watch<RadioState>();
    radioState.ensureAutoCountrySelected();
    final subscription = context.watch<SubscriptionState>();
    final recorder = context.watch<RecordingState>();
    final player = context.watch<PlayerState>();
    const double controlBoxWidth = 190;
    final selectedStation = radioState.selectedStation ?? player.currentStation;
    final currentRecording = player.currentRecordingPath == null
        ? null
        : recorder.recordings
            .cast<RecordingItem?>()
            .firstWhere(
              (item) => item?.path == player.currentRecordingPath,
              orElse: () => null,
            );
    final isRecordingPlayback = currentRecording != null;
    final isRecordingsView = recorder.showRecordingsList;
    final isLiveRecording = recorder.isRecording || recorder.isVoiceRecording;
    final liveRecordingStartedAt = recorder.isVoiceRecording
        ? recorder.voiceRecordingStartedAt
        : recorder.recordingStartedAt;
    final liveDuration = liveRecordingStartedAt == null
        ? Duration.zero
        : DateTime.now().difference(liveRecordingStartedAt);
    final playbackPosition = player.position;
    final playbackDuration = player.duration;
    final canRecord = selectedStation != null;
    final canControlRecording = player.currentRecordingPath != null;
    final isPowerOn = selectedStation != null &&
        player.isPlaying &&
        player.currentStation == selectedStation;

    final lcdFrequency = isRecordingPlayback
        ? _formatDurationProgress(playbackPosition, playbackDuration)
        : (isLiveRecording
            ? _formatDuration(liveDuration)
            : (isRecordingsView
                ? 'REC'
                : (isPowerOn
                    ? (selectedStation?.frequency.trim().isNotEmpty == true
                        ? selectedStation!.frequency
                        : '--.-')
                    : '--.-')));
    final lcdName = isRecordingPlayback
        ? '${currentRecording.name} • ${currentRecording.stationName}'.trim()
        : (isLiveRecording
            ? (recorder.isVoiceRecording ? 'Voice note' : 'Recording')
            : (isRecordingsView
                ? strings.recordings
                : (isPowerOn ? (selectedStation?.name ?? '') : strings.notPlaying)));
    final lcdCountry = isRecordingPlayback
        ? strings.recordings
        : (isLiveRecording
            ? ''
            : (isRecordingsView ? '' : (isPowerOn ? (selectedStation?.country ?? '') : '')));
    final lcdLanguage = isRecordingPlayback
        ? (currentRecording.mode == RecordingMode.withBackground
            ? strings.recordWithBackground
            : strings.recordStreamOnly)
        : (isLiveRecording
            ? (recorder.isVoiceRecording
                ? 'Voice note'
                : (recorder.activeMode == RecordingMode.withBackground
                    ? strings.recordWithBackground
                    : strings.recordStreamOnly))
            : (isRecordingsView
                ? ''
                : (isPowerOn ? (selectedStation?.language ?? '') : '')));
    final lcdBitrate = isRecordingPlayback
        ? (currentRecording.durationSeconds != null
            ? _formatDuration(Duration(seconds: currentRecording.durationSeconds!))
            : currentRecording.createdAt.toLocal().toString())
        : (isLiveRecording
            ? ''
            : (isRecordingsView ? '' : (isPowerOn ? (selectedStation?.bitrate ?? '') : '')));

    if (recorder.isRecording) {
      if (!_blinkController.isAnimating) {
        _blinkController.repeat(reverse: true);
      }
    } else {
      if (_blinkController.isAnimating) {
        _blinkController.stop();
        _blinkController.value = 1.0;
      }
    }
    if (recorder.showRecordingsList) {
      if (!_recordingsBlinkController.isAnimating) {
        _recordingsBlinkController.repeat(reverse: true);
      }
    } else {
      if (_recordingsBlinkController.isAnimating) {
        _recordingsBlinkController.stop();
        _recordingsBlinkController.value = 1.0;
      }
    }
    if (recorder.isVoiceRecording) {
      if (!_voiceBlinkController.isAnimating) {
        _voiceBlinkController.repeat(reverse: true);
      }
    } else {
      if (_voiceBlinkController.isAnimating) {
        _voiceBlinkController.stop();
        _voiceBlinkController.value = 1.0;
      }
    }

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        toolbarHeight: 44,
        title: Text(strings.appTitle),
      ),
      body: Column(
        children: [
          Padding(
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
                  InkWell(
                    onTap: () {
                      if (currentRecording != null) {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => RecordingDetailScreen(item: currentRecording),
                          ),
                        );
                        return;
                      }
                      if (selectedStation != null && isPowerOn) {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => PlayerScreen(station: selectedStation),
                          ),
                        );
                      }
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFB9F5A6),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF5B8F49), width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF7EC46A).withValues(alpha: 0.6),
                            blurRadius: 12,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF9FE887),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFF5B8F49)),
                                ),
                                child: const Icon(
                                  Icons.radio,
                                  size: 18,
                                  color: Color(0xFF1F3D1A),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _MarqueeText(
                                  key: ValueKey(lcdName),
                                  text: lcdName,
                                  style: const TextStyle(
                                    fontFamily: 'Courier',
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1F3D1A),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 40,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  lcdFrequency,
                                  style: TextStyle(
                                    fontFamily: 'Courier',
                                    fontSize: isRecordingPlayback ? 22 : 36,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF1F3D1A),
                                    letterSpacing: isRecordingPlayback ? 1 : 2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  lcdCountry,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontFamily: 'Courier',
                                    fontSize: 12,
                                    color: Color(0xFF1F3D1A),
                                  ),
                                ),
                              ),
                              if (lcdLanguage.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    lcdLanguage,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontFamily: 'Courier',
                                      fontSize: 12,
                                      color: Color(0xFF1F3D1A),
                                    ),
                                  ),
                                ),
                              ],
                              if (lcdBitrate.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Text(
                                  currentRecording != null
                                      ? lcdBitrate
                                      : '${lcdBitrate}kbps',
                                  style: const TextStyle(
                                    fontFamily: 'Courier',
                                    fontSize: 12,
                                    color: Color(0xFF1F3D1A),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
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
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _ControlButton(
                          child: Icon(
                            Icons.power_settings_new,
                            color: selectedStation == null
                                ? Colors.grey
                                : (isPowerOn ? Colors.red : Colors.grey),
                          ),
                          onPressed: selectedStation == null
                              ? null
                              : () async {
                                  if (player.isPlaying &&
                                      player.currentStation == selectedStation) {
                                    await player.pause();
                                  } else if (selectedStation != null) {
                                    await player.play(selectedStation);
                                  }
                                },
                        ),
                        const SizedBox(width: 8),
                        _ControlButton(
                          child: AnimatedBuilder(
                            animation: _blinkController,
                            builder: (context, child) {
                              final shouldBlink = recorder.isRecording;
                              return Opacity(
                                opacity: shouldBlink ? _blinkController.value : 1.0,
                                child: child,
                              );
                            },
                            child: Icon(
                              recorder.isRecording
                                  ? Icons.stop_circle
                                  : Icons.fiber_manual_record,
                              color: recorder.isRecording ? Colors.red : null,
                            ),
                          ),
                          onPressed: canRecord
                              ? () async {
                                  if (recorder.isRecording) {
                                    await recorder.stopRecording();
                                    if (recorder.shouldResumePlayback &&
                                        selectedStation != null) {
                                      await player.play(selectedStation);
                                    }
                                    return;
                                  }
                                  if (selectedStation == null) {
                                    return;
                                  }
                                  final settings = context.read<SettingsState>();
                                  final mode = settings.recordingMode;
                                  recorder.setShouldResumePlayback(false);
                                  if (mode == RecordingMode.withBackground) {
                                    if (!player.isPlaying ||
                                        player.currentStation != selectedStation) {
                                      await player.play(selectedStation);
                                    }
                                  }
                                  await recorder.startRecording(
                                    selectedStation,
                                    mode: mode,
                                  );
                                }
                              : null,
                        ),
                        const SizedBox(width: 8),
                        _ControlButton(
                          child: const Icon(Icons.refresh),
                          onPressed: radioState.selectedCountry == null
                              ? null
                              : () => radioState.refreshStations(),
                        ),
                        const SizedBox(width: 8),
                        _ControlButton(
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
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHigh,
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
                                      trackShape: const _TaperedSliderTrackShape(
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
                  ),
                  const SizedBox(height: 6),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _ControlButton(
                          child: AnimatedBuilder(
                            animation: _recordingsBlinkController,
                            builder: (context, child) {
                              return Opacity(
                                opacity: recorder.showRecordingsList
                                    ? _recordingsBlinkController.value
                                    : 1.0,
                                child: child,
                              );
                            },
                            child: const Icon(Icons.play_arrow),
                          ),
                          onPressed: () => recorder.toggleRecordingsList(),
                        ),
                        const SizedBox(width: 8),
                        _ControlButton(
                          child: const Icon(Icons.fast_rewind),
                          onPressed: canControlRecording
                              ? () => player.seekRelative(const Duration(seconds: -10))
                              : null,
                        ),
                        const SizedBox(width: 8),
                        _ControlButton(
                          child: const Icon(Icons.fast_forward),
                          onPressed: canControlRecording
                              ? () => player.seekRelative(const Duration(seconds: 10))
                              : null,
                        ),
                        const SizedBox(width: 8),
                        _ControlButton(
                          child: AnimatedBuilder(
                            animation: _voiceBlinkController,
                            builder: (context, child) {
                              return Opacity(
                                opacity: recorder.isVoiceRecording
                                    ? _voiceBlinkController.value
                                    : 1.0,
                                child: child,
                              );
                            },
                            child: Icon(
                              recorder.isVoiceRecording ? Icons.stop : Icons.mic,
                              color: recorder.isVoiceRecording ? Colors.red : null,
                            ),
                          ),
                          onPressed: () async {
                            if (recorder.isVoiceRecording) {
                              await recorder.stopVoiceRecording();
                            } else {
                              final wasRadioPlaying = player.isPlaying;
                              await recorder.startVoiceRecording();
                              // Only resume the radio if it was playing and the system paused it.
                              if (wasRadioPlaying) {
                                Future.delayed(
                                  const Duration(milliseconds: 400),
                                  () async {
                                    if (!context.mounted) return;
                                    final p = context.read<PlayerState>();
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
                            child: TextField(
                              controller: recorder.showRecordingsList
                                  ? _recordingSearchController
                                  : _stationSearchController,
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.search),
                                hintText: recorder.showRecordingsList
                                    ? strings.searchRecordings
                                    : strings.searchStations,
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 8,
                                ),
                                border: const OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (recorder.errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      recorder.errorMessage!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (radioState.isLoading) const LinearProgressIndicator(),
          if (radioState.errorMessage != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                radioState.errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: recorder.showRecordingsList
                ? (recorder.visibleRecordings.isEmpty
                    ? Center(child: Text(strings.noRecordings))
                    : Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: Text(
                              strings.recordings,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          Expanded(
                            child: Builder(
                              builder: (context) {
                                final query = _recordingSearchQuery.toLowerCase();
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
                                  controller: _recordingsListController,
                                  thumbVisibility: true,
                                  interactive: true,
                                  child: RefreshIndicator(
                                    onRefresh: () async {
                                      await recorder.reloadRecordings();
                                    },
                                    child: ListView.separated(
                                      controller: _recordingsListController,
                                      padding: EdgeInsets.only(
                                        bottom: subscription.isPro ? 0 : 56,
                                      ),
                                      itemCount:
                                          displayList.length + (showLoadMore ? 1 : 0),
                                      separatorBuilder: (_, __) =>
                                          const Divider(height: 1),
                                      itemBuilder: (context, index) {
                                        if (showLoadMore &&
                                            index >= displayList.length) {
                                          return Center(
                                            child: TextButton(
                                              onPressed: () =>
                                                  recorder.loadMoreRecordings(),
                                              child: Text(strings.loadMore),
                                            ),
                                          );
                                        }
                                        final item = displayList[index];
                                        final isPlaying =
                                            player.currentRecordingPath == item.path &&
                                                player.isPlaying;
                                        final isLoading = player.isLoading &&
                                            player.currentRecordingPath == item.path;
                                        final subtitleParts = <String>[
                                          item.stationName,
                                          if (item.durationSeconds != null)
                                            _formatDuration(
                                              Duration(seconds: item.durationSeconds!),
                                            ),
                                        ];
                                        final isRtl =
                                            Directionality.of(context) ==
                                                TextDirection.rtl;
                                        final renameBackground = Container(
                                          color: Colors.blue.withValues(alpha: 0.15),
                                          alignment: Alignment.centerLeft,
                                          padding: const EdgeInsets.only(left: 16),
                                          child: const Icon(
                                            Icons.drive_file_rename_outline,
                                            color: Colors.blue,
                                          ),
                                        );
                                        final deleteBackground = Container(
                                          color: Colors.red.withValues(alpha: 0.15),
                                          alignment: Alignment.centerRight,
                                          padding: const EdgeInsets.only(right: 16),
                                          child: const Icon(
                                            Icons.delete,
                                            color: Colors.red,
                                          ),
                                        );
                                        final renameDirection = isRtl
                                            ? DismissDirection.endToStart
                                            : DismissDirection.startToEnd;
                                        final deleteDirection = isRtl
                                            ? DismissDirection.startToEnd
                                            : DismissDirection.endToStart;
                                        return Dismissible(
                                          key: ValueKey(item.path),
                                          background: isRtl
                                              ? deleteBackground
                                              : renameBackground,
                                          secondaryBackground: isRtl
                                              ? renameBackground
                                              : deleteBackground,
                                          confirmDismiss: (direction) async {
                                            if (direction == renameDirection) {
                                              final controller = TextEditingController(
                                                text: item.name,
                                              );
                                              final result =
                                                  await showDialog<String>(
                                                context: context,
                                                builder: (context) {
                                                  return AlertDialog(
                                                    title:
                                                        Text(strings.renameFileTitle),
                                                    content: TextField(
                                                      controller: controller,
                                                      decoration: InputDecoration(
                                                        labelText: strings.nameHint,
                                                      ),
                                                    ),
                                                    actions: [
                                                      TextButton(
                                                        onPressed: () =>
                                                            Navigator.of(context).pop(),
                                                        child: Text(strings.cancel),
                                                      ),
                                                      TextButton(
                                                        onPressed: () =>
                                                            Navigator.of(context)
                                                                .pop(controller.text),
                                                        child: Text(strings.save),
                                                      ),
                                                    ],
                                                  );
                                                },
                                              );
                                              if (result != null) {
                                                await recorder.renameRecordingFile(
                                                    item, result);
                                              }
                                              return false;
                                            }
                                            if (direction != deleteDirection) {
                                              return false;
                                            }
                                            final confirm =
                                                await showDialog<bool>(
                                              context: context,
                                              builder: (context) {
                                                return AlertDialog(
                                                  title:
                                                      Text(strings.deleteRecordingTitle),
                                                  content:
                                                      Text(strings.deleteRecordingBody),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () =>
                                                          Navigator.of(context).pop(false),
                                                      child: Text(strings.cancel),
                                                    ),
                                                    TextButton(
                                                      onPressed: () =>
                                                          Navigator.of(context).pop(true),
                                                      child: Text(strings.delete),
                                                    ),
                                                  ],
                                                );
                                              },
                                            );
                                            if (confirm == true) {
                                              recorder.deleteRecording(item);
                                              return true;
                                            }
                                            return false;
                                          },
                                          child: ListTile(
                                            leading: _RecordingListIcon(item: item),
                                            title: Text(item.name),
                                            subtitle: Text(subtitleParts.join(' • ')),
                                            trailing: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                IconButton(
                                                  icon: Icon(
                                                    recorder.isFavoriteRecording(item)
                                                        ? Icons.favorite
                                                        : Icons.favorite_border,
                                                    color: Colors.redAccent,
                                                  ),
                                                  onPressed: () => recorder
                                                      .toggleFavoriteRecording(item),
                                                ),
                                                IconButton(
                                                  iconSize: 32,
                                                  icon: isLoading
                                                      ? const SizedBox(
                                                          width: 20,
                                                          height: 20,
                                                          child:
                                                              CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                          ),
                                                        )
                                                      : Icon(
                                                          isPlaying
                                                              ? Icons.pause
                                                              : Icons.play_arrow,
                                                        ),
                                                  onPressed: () async {
                                                    if (isLoading) {
                                                      return;
                                                    }
                                                    if (isPlaying) {
                                                      await player.stop();
                                                      return;
                                                    }
                                                    await player.playRecording(item.path);
                                                  },
                                                ),
                                              ],
                                            ),
                                            onTap: () {
                                              Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      RecordingDetailScreen(item: item),
                                                ),
                                              );
                                            },
                                          ),
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
                                      final duration = durationSnap.data ?? Duration.zero;
                                      final rawMax = duration.inMilliseconds.toDouble();
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
                      ))
                : (radioState.stations.isEmpty
                    ? Center(child: Text(strings.noStations))
                    : AnimatedPadding(
                        duration: const Duration(milliseconds: 150),
                        curve: Curves.easeOut,
                        padding: EdgeInsets.only(
                          bottom: MediaQuery.viewInsetsOf(context).bottom,
                        ),
                        child: Builder(
                          builder: (context) {
                            final query = _stationSearchQuery.toLowerCase();
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
                            final showLoadMore =
                                query.isEmpty && radioState.hasMoreStations;
                            final itemCount =
                                displayList.length + (showLoadMore ? 1 : 0);
                            return Scrollbar(
                              controller: _stationListController,
                              thumbVisibility: true,
                              interactive: true,
                              child: RefreshIndicator(
                                onRefresh: () async {
                                  await radioState.refreshStations();
                                },
                                child: ListView.builder(
                                  controller: _stationListController,
                                  keyboardDismissBehavior:
                                      ScrollViewKeyboardDismissBehavior.onDrag,
                                  padding: EdgeInsets.only(
                                    bottom: subscription.isPro ? 0 : 56,
                                  ),
                                  itemCount: itemCount,
                                  itemBuilder: (context, index) {
                                    if (displayList.isEmpty) {
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 24),
                                        child: Center(child: Text(strings.noStations)),
                                      );
                                    }
                                    if (showLoadMore &&
                                        index >= displayList.length) {
                                      return Center(
                                        child: TextButton(
                                          onPressed: () =>
                                              radioState.loadMoreStations(),
                                          child: Text(strings.loadMore),
                                        ),
                                      );
                                    }
                                    final station = displayList[index];
                                    final title = station.frequency.isNotEmpty
                                        ? '${station.name} (${station.frequency})'
                                        : station.name;
                                    final isCurrent =
                                        player.currentStation == station;
                                    final isPlaying = isCurrent && player.isPlaying;
                                    return ListTile(
                                      leading: const CircleAvatar(
                                        child: Icon(Icons.radio),
                                      ),
                                      title: Text(title),
                                      subtitle: Text(
                                        '${station.frequency} • ${station.country}',
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
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
                                              isPlaying
                                                  ? Icons.pause
                                                  : Icons.play_arrow,
                                            ),
                                            onPressed: () async {
                                              if (isPlaying) {
                                                await player.pause();
                                                return;
                                              }
                                              radioState.selectStation(station);
                                              await player.play(station);
                                            },
                                          ),
                                        ],
                                      ),
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
                            );
                          },
                        ))),
          ),
          if (!subscription.isPro) const _AdBanner(),
        ],
      ),
    );
  }
}

class _AdBanner extends StatefulWidget {
  const _AdBanner();

  @override
  State<_AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<_AdBanner> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;
  LoadAdError? _loadError;
  static const int _maxRetries = 3;
  int _retryCount = 0;

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  void _loadAd() {
    _bannerAd?.dispose();
    _bannerAd = BannerAd(
      adUnitId: AdConfig.bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) {
            setState(() {
              _isLoaded = true;
              _loadError = null;
            });
          }
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint(
            'AdMob banner failed: code=${error.code}, domain=${error.domain}, '
            'message=${error.message}',
          );
          ad.dispose();
          if (mounted) {
            setState(() {
              _bannerAd = null;
              _loadError = error;
              _isLoaded = false;
            });
            if (_retryCount < _maxRetries) {
              _retryCount++;
              Future.delayed(const Duration(seconds: 3), () {
                if (mounted) _loadAd();
              });
            }
          }
        },
      ),
    );
    _bannerAd!.load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded || _bannerAd == null) {
      return SafeArea(
        top: false,
        child: SizedBox(
          height: AdSize.banner.height.toDouble(),
          child: _loadError != null && _retryCount >= _maxRetries
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      'Ad unavailable (${_loadError!.code})',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : const Center(child: SizedBox.shrink()),
        ),
      );
    }
    return SafeArea(
      top: false,
      child: SizedBox(
        width: _bannerAd!.size.width.toDouble(),
        height: _bannerAd!.size.height.toDouble(),
        child: AdWidget(ad: _bannerAd!),
      ),
    );
  }
}

/// Leading icon for a recording list item: radio or mic with save badge in corner.
class _RecordingListIcon extends StatelessWidget {
  const _RecordingListIcon({required this.item});

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
            child: Icon(_isVoiceNote ? Icons.mic : Icons.radio),
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

class _ControlButton extends StatelessWidget {
  const _ControlButton({required this.child, this.onPressed});

  final Widget child;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final iconColor = Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      width: 40,
      height: 40,
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
          ),
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.35),
                  blurRadius: 4,
                  offset: const Offset(0, -1),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: IconTheme(
              data: IconThemeData(size: 22, color: iconColor),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key, required this.station});

  final RadioStation station;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final player = context.watch<PlayerState>();
    final recorder = context.watch<RecordingState>();
    final settings = context.watch<SettingsState>();
    final isCurrent = player.currentStation == station;
    final isPlaying = isCurrent && player.isPlaying;
    return Scaffold(
      appBar: AppBar(title: Text(station.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            station.frequency.isNotEmpty ? station.frequency : strings.stationFrequency,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          _InfoTile(label: strings.stationCountry, value: station.country),
          _InfoTile(label: strings.stationLanguage, value: station.language),
          _InfoTile(label: strings.stationTags, value: station.tags),
          _InfoTile(label: strings.stationBitrate, value: station.bitrate),
          _InfoTile(label: strings.stationLink, value: station.streamUrl),
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
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    if (isPlaying) {
                      await player.pause();
                    } else {
                      await player.play(station);
                    }
                  },
                  icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                  label: Text(isPlaying ? strings.pause : strings.play),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: recorder.isRecording
                      ? () => recorder.stopRecording()
                      : () async {
                          recorder.setShouldResumePlayback(false);
                          if (settings.recordingMode == RecordingMode.withBackground) {
                            if (!player.isPlaying || player.currentStation != station) {
                              await player.play(station);
                            }
                          }
                          await recorder.startRecording(
                            station,
                            mode: settings.recordingMode,
                          );
                        },
                  icon: Icon(
                    recorder.isRecording ? Icons.stop_circle : Icons.fiber_manual_record,
                    color: recorder.isRecording ? Colors.red : null,
                  ),
                  label: Text(
                    recorder.isRecording ? strings.stopRecording : strings.startRecording,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class RecordingDetailScreen extends StatelessWidget {
  const RecordingDetailScreen({super.key, required this.item});

  final RecordingItem item;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final player = context.watch<PlayerState>();
    final recorder = context.watch<RecordingState>();
    final isPlaying = player.currentRecordingPath == item.path && player.isPlaying;
    final isLoading = player.isLoading && player.currentRecordingPath == item.path;
    final subtitleParts = <String>[
      item.stationName,
      if (item.durationSeconds != null)
        _formatDuration(Duration(seconds: item.durationSeconds!)),
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
            _InfoTile(label: 'Station', value: item.stationName),
          _InfoTile(label: strings.stationDate, value: _formatRecordingTime(item.createdAt)),
          _InfoTile(label: strings.duration, value: _formatDuration(Duration(seconds: item.durationSeconds ?? 0))),
          _InfoTile(label: strings.recordings, value: item.sizeLabel),
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
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    if (isLoading) {
                      return;
                    }
                    if (isPlaying) {
                      await player.stop();
                    } else {
                      await player.playRecording(item.path);
                    }
                  },
                  icon: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                  label: Text(isPlaying ? strings.pause : strings.play),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.errorContainer,
                    foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                  onPressed: () async {
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
                      await recorder.deleteRecording(item);
                      if (context.mounted) {
                        Navigator.of(context).pop();
                      }
                    }
                  },
                  icon: const Icon(Icons.delete),
                  label: Text(strings.delete),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(child: Text(value.isEmpty ? '-' : value)),
        ],
      ),
    );
  }
}

class _TaperedSliderTrackShape extends SliderTrackShape {
  const _TaperedSliderTrackShape({
    required this.minHeight,
    required this.maxHeight,
    this.horizontalInset = 0,
  });

  final double minHeight;
  final double maxHeight;
  final double horizontalInset;

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final trackHeight = maxHeight;
    final trackLeft = offset.dx + horizontalInset;
    final trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    final width = parentBox.size.width - (horizontalInset * 2);
    return Rect.fromLTWH(trackLeft, trackTop, width, trackHeight);
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 0,
  }) {
    final trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final trackLeft = trackRect.left;
    final trackRight = trackRect.right;
    final trackWidth = trackRect.width;
    if (trackWidth <= 0) {
      return;
    }

    final activePaint = Paint()
      ..color = sliderTheme.activeTrackColor ?? Colors.blue
      ..style = PaintingStyle.fill;
    final inactivePaint = Paint()
      ..color = sliderTheme.inactiveTrackColor ?? Colors.grey
      ..style = PaintingStyle.fill;

    double thicknessAt(double x) {
      final t = ((x - trackLeft) / trackWidth).clamp(0.0, 1.0);
      return minHeight + (maxHeight - minHeight) * t;
    }

    void drawSegment(double x1, double x2, Paint paint) {
      if (x2 <= x1) return;
      final h1 = thicknessAt(x1);
      final h2 = thicknessAt(x2);
      final yCenter = trackRect.center.dy;
      final path = Path()
        ..moveTo(x1, yCenter - h1 / 2)
        ..lineTo(x2, yCenter - h2 / 2)
        ..lineTo(x2, yCenter + h2 / 2)
        ..lineTo(x1, yCenter + h1 / 2)
        ..close();
      context.canvas.drawPath(path, paint);
    }

    final clampedThumbX = thumbCenter.dx.clamp(trackLeft, trackRight);
    if (textDirection == TextDirection.rtl) {
      drawSegment(clampedThumbX, trackRight, activePaint);
      drawSegment(trackLeft, clampedThumbX, inactivePaint);
    } else {
      drawSegment(trackLeft, clampedThumbX, activePaint);
      drawSegment(clampedThumbX, trackRight, inactivePaint);
    }
  }
}

class _MarqueeText extends StatefulWidget {
  const _MarqueeText({super.key, required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  double _textWidth = 0;
  double _availableWidth = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void didUpdateWidget(covariant _MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.style != widget.style) {
      _restartAnimation();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _restartAnimation() {
    _controller.stop();
    _controller.reset();
    if (_textWidth > _availableWidth && _availableWidth > 0) {
      final overflow = _textWidth - _availableWidth;
      final durationMs = (overflow / 40 * 1000).clamp(3000, 12000).toInt();
      _controller.duration = Duration(milliseconds: durationMs);
      _controller.repeat(reverse: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _availableWidth = constraints.maxWidth;
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout();
        _textWidth = painter.width;
        WidgetsBinding.instance.addPostFrameCallback((_) => _restartAnimation());

        if (_textWidth <= _availableWidth || _availableWidth == 0) {
          return Text(
            widget.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: widget.style,
          );
        }

        final overflow = _textWidth - _availableWidth;
        return ClipRect(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final offset = overflow * _controller.value;
              return Transform.translate(
                offset: Offset(-offset, 0),
                child: child,
              );
            },
            child: Text(
              widget.text,
              maxLines: 1,
              style: widget.style,
            ),
          ),
        );
      },
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final settings = context.watch<SettingsState>();
    final subscription = context.watch<SubscriptionState>();
    final settingsTextStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontSize: 14,
        );
    return Scaffold(
      appBar: AppBar(title: Text(strings.settings)),
      body: ListView(
        children: [
          ListTile(
            title: Text(strings.language, style: settingsTextStyle),
            trailing: DropdownButton<Locale>(
              value: settings.locale,
              isDense: true,
              itemHeight: kMinInteractiveDimension,
              style: settingsTextStyle,
              onChanged: (value) {
                if (value != null) {
                  settings.setLocale(value);
                }
              },
              items: AppLocalizations.supportedLocales
                  .map((locale) => DropdownMenuItem(
                        value: locale,
                        child: Text(
                          locale.languageCode.toUpperCase(),
                          style: settingsTextStyle,
                        ),
                      ))
                  .toList(),
            ),
          ),
          ListTile(
            title: Text(strings.themeMode, style: settingsTextStyle),
            trailing: DropdownButton<ThemeMode>(
              value: settings.themeMode,
              style: settingsTextStyle,
              onChanged: (value) {
                if (value != null) {
                  settings.setThemeMode(value);
                }
              },
              items: ThemeMode.values
                  .map((mode) => DropdownMenuItem(
                        value: mode,
                        child: Text(_themeModeLabel(mode, strings), style: settingsTextStyle),
                      ))
                  .toList(),
            ),
          ),
          ListTile(
            title: Text(strings.recordingQuality, style: settingsTextStyle),
            trailing: DropdownButton<RecordingQuality>(
              value: settings.recordingQuality,
              style: settingsTextStyle,
              onChanged: (value) {
                if (value != null) {
                  settings.setRecordingQuality(value);
                }
              },
              items: RecordingQuality.values
                  .map((quality) => DropdownMenuItem(
                        value: quality,
                        child: Text(quality.label(strings), style: settingsTextStyle),
                      ))
                  .toList(),
            ),
          ),
            ListTile(
              title: Text(strings.listPageSize, style: settingsTextStyle),
              trailing: DropdownButton<int>(
                value: settings.listPageSize,
                style: settingsTextStyle,
                onChanged: (value) {
                  if (value != null) {
                    settings.setListPageSize(value);
                  }
                },
                items: const [10, 20, 30, 50, 100]
                    .map((value) => DropdownMenuItem(
                          value: value,
                          child: Text(value.toString(), style: settingsTextStyle),
                        ))
                    .toList(),
              ),
            ),
            SwitchListTile(
            title: Text(strings.dataSaver, style: settingsTextStyle),
              value: settings.dataSaver,
              onChanged: settings.setDataSaver,
            ),
            ListTile(
              title: Text(strings.recordings, style: settingsTextStyle),
              subtitle: Text(
                strings.recordingsCount(
                  context.watch<RecordingState>().recordings.length,
                ),
                style: settingsTextStyle,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                showModalBottomSheet(
                  context: context,
                  builder: (context) {
                    final recordingState = context.watch<RecordingState>();
                    final recordings = recordingState.recordings;
                    if (recordings.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(AppLocalizations.of(context).noRecordings),
                      );
                    }
                    final displayRecordings =
                        recordingState.sortRecordingsByFavorite(
                      recordingState.visibleRecordings,
                    );
                    return Column(
                      children: [
                        if (recordingState.errorMessage != null)
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              recordingState.errorMessage!,
                              style: TextStyle(color: Theme.of(context).colorScheme.error),
                            ),
                          ),
                        Expanded(
                          child: ListView.separated(
                            itemCount: displayRecordings.length +
                                (recordingState.hasMoreRecordings ? 1 : 0),
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              if (index >= displayRecordings.length) {
                                return Center(
                                  child: TextButton(
                                    onPressed: () => recordingState.loadMoreRecordings(),
                                    child: Text(strings.loadMore),
                                  ),
                                );
                              }
                              final item = displayRecordings[index];
                              final player = context.watch<PlayerState>();
                              final isPlaying =
                                  player.currentRecordingPath == item.path && player.isPlaying;
                              return ListTile(
                                leading: _RecordingListIcon(item: item),
                                title: Text(item.name),
                                subtitle: Text(item.stationName),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                                      onPressed: () async {
                                        if (isPlaying) {
                                          await player.stop();
                                          return;
                                        }
                                        await player.playRecording(item.path);
                                      },
                                    ),
                                    Text(item.sizeLabel),
                                    IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red),
                                      onPressed: () async {
                                        final confirm = await showDialog<bool>(
                                          context: context,
                                          builder: (context) {
                                            return AlertDialog(
                                              title: Text(strings.deleteRecordingTitle),
                                              content: Text(strings.deleteRecordingBody),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.of(context).pop(false),
                                                  child: Text(strings.cancel),
                                                ),
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.of(context).pop(true),
                                                  child: Text(strings.delete),
                                                ),
                                              ],
                                            );
                                          },
                                        );
                                        if (confirm == true) {
                                          recordingState.deleteRecording(item);
                                        }
                                      },
                                    ),
                                  ],
                                ),
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => RecordingDetailScreen(item: item),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                      ),
                      ],
                    );
                  },
                );
              },
            ),
          const Divider(),
          if (subscription.errorMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      subscription.errorMessage!,
                      style: settingsTextStyle?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: subscription.clearError,
                    child: const Text('Dismiss'),
                  ),
                ],
              ),
            ),
          ListTile(
            title: Text(strings.subscription, style: settingsTextStyle),
            subtitle: Text(
              subscription.isPro ? strings.subscribed : strings.notSubscribed,
              style: settingsTextStyle,
            ),
            trailing: subscription.isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : ElevatedButton(
                    onPressed: subscription.isLoading
                        ? null
                        : () async {
                            if (subscription.isPro) {
                              await subscription.restorePurchases();
                            } else {
                              await subscription.purchaseSubscription();
                            }
                          },
                    style: ElevatedButton.styleFrom(textStyle: settingsTextStyle),
                    child: Text(
                      subscription.isPro ? strings.manage : strings.subscribe,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class CountryDropdown extends StatelessWidget {
  const CountryDropdown({super.key, required this.selected, required this.onChanged});

  final Country? selected;
  final ValueChanged<Country?> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final textColor = Theme.of(context).colorScheme.onSurface;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: strings.country,
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        labelStyle: TextStyle(
          fontSize: 15,
          color: textColor,
        ),
      ),
      child: InkWell(
        onTap: () async {
          final selectedCountry = await showModalBottomSheet<Country>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (context) {
              final controller = TextEditingController();
              var query = '';
              return SafeArea(
                child: StatefulBuilder(
                  builder: (context, setState) {
                    final q = query.trim().toLowerCase();
                    final items = Country.defaults.where((country) {
                      final localized = strings.countryName(country).toLowerCase();
                      final english = country.name.toLowerCase();
                      final code = country.code.toLowerCase();
                      return q.isEmpty ||
                          localized.contains(q) ||
                          english.contains(q) ||
                          code.contains(q);
                    }).toList();
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          TextField(
                            controller: controller,
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.search),
                              hintText: strings.country,
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (value) => setState(() => query = value),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: ListView.separated(
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              itemCount: items.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final item = items[index];
                                return ListTile(
                                  title: Text(strings.countryName(item)),
                                  onTap: () => Navigator.of(context).pop(item),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          );
          if (selectedCountry != null) {
            onChanged(selectedCountry);
          }
        },
        child: Row(
          children: [
            Expanded(
              child: Text(
                selected == null
                    ? strings.country
                    : strings.countryName(selected!),
                style: TextStyle(fontSize: 16, color: textColor),
              ),
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }
}

class RadioState extends ChangeNotifier {
  Country? selectedCountry;
  RadioStation? selectedStation;
  List<RadioStation> stations = [];
  List<RadioStation> _allStations = [];
  bool isLoading = false;
  String? errorMessage;
  final RadioApiService _service = RadioApiService();
  final Set<String> _favoriteStationIds = {};
  bool _dataSaverEnabled = false;
  bool _autoCountryRequested = false;
  static const String _lastCountryKey = 'last_country_code';
  static const String _favoriteStationsKey = 'favorite_station_ids';
  int _stationsPageSize = 40;
  int _visibleStationCount = 40;

  RadioState() {
    _restoreLastCountry();
    _loadFavoriteStations();
  }

  List<RadioStation> get visibleStations =>
      stations.take(_visibleStationCount).toList();

  List<RadioStation> get allStations => List<RadioStation>.from(_allStations);

  bool get hasMoreStations => stations.length > _visibleStationCount;

  void loadMoreStations() {
    if (!hasMoreStations) {
      return;
    }
    _visibleStationCount =
        min(_visibleStationCount + _stationsPageSize, stations.length);
    notifyListeners();
  }

  void setStationsPageSize(int value) {
    final next = value.clamp(5, 200);
    if (_stationsPageSize == next) {
      return;
    }
    _stationsPageSize = next;
    _reconcileVisibleStations();
    notifyListeners();
  }

  void _reconcileVisibleStations() {
    if (_visibleStationCount <= 0) {
      _visibleStationCount = min(_stationsPageSize, stations.length);
      return;
    }
    if (_visibleStationCount > stations.length) {
      _visibleStationCount = stations.length;
    }
    if (_visibleStationCount < _stationsPageSize) {
      _visibleStationCount = min(_stationsPageSize, stations.length);
    }
  }

  Future<void> _restoreLastCountry() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(_lastCountryKey);
      if (code == null || code.isEmpty) {
        return;
      }
      final match = Country.defaults.firstWhere(
        (country) => country.code.toUpperCase() == code.toUpperCase(),
        orElse: () => Country.defaults.first,
      );
      await selectCountry(match);
    } catch (_) {
      // Ignore restore errors.
    }
  }

  Future<void> _persistSelectedCountry(Country country) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastCountryKey, country.code);
    } catch (_) {
      // Ignore persistence errors.
    }
  }

  Future<void> _loadFavoriteStations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final values = prefs.getStringList(_favoriteStationsKey) ?? [];
      _favoriteStationIds
        ..clear()
        ..addAll(values);
      _applyFavoritesOrdering();
    } catch (_) {
      // Ignore restore errors.
    }
  }

  Future<void> _persistFavoriteStations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_favoriteStationsKey, _favoriteStationIds.toList());
    } catch (_) {
      // Ignore persistence errors.
    }
  }

  Future<File> _stationsCacheFile(Country country) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/stations_${country.code.toLowerCase()}.json');
  }

  Future<List<RadioStation>?> _loadCachedStations(Country country) async {
    try {
      final file = await _stationsCacheFile(country);
      if (!await file.exists()) {
        return null;
      }
      final contents = await file.readAsString();
      final data = jsonDecode(contents);
      if (data is! List) {
        return null;
      }
      return data
          .whereType<Map<String, dynamic>>()
          .map((item) {
            final streamUrl = item['streamUrl']?.toString() ?? '';
            final isFavorite = item['favorite'] == true;
            if (isFavorite && streamUrl.isNotEmpty) {
              _favoriteStationIds.add(streamUrl);
            }
            return RadioStation(
              name: item['name']?.toString() ?? '',
              frequency: item['frequency']?.toString() ?? 'FM',
              streamUrl: streamUrl,
              country: item['country']?.toString() ?? country.name,
              faviconUrl: item['faviconUrl']?.toString() ?? '',
              language: item['language']?.toString() ?? '',
              tags: item['tags']?.toString() ?? '',
              bitrate: item['bitrate']?.toString() ?? '',
            );
          })
          .where((station) => station.name.isNotEmpty && station.streamUrl.isNotEmpty)
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCachedStations(Country country, List<RadioStation> list) async {
    try {
      final file = await _stationsCacheFile(country);
      final data = list
          .map((station) => {
                'name': station.name,
                'frequency': station.frequency,
                'streamUrl': station.streamUrl,
                'country': station.country,
                'faviconUrl': station.faviconUrl,
                'language': station.language,
                'tags': station.tags,
                'bitrate': station.bitrate,
                'favorite': _favoriteStationIds.contains(station.streamUrl),
              })
          .toList();
      await file.writeAsString(jsonEncode(data));
    } catch (_) {
      // Ignore cache write errors.
    }
  }

  void setDataSaverEnabled(bool value) {
    if (_dataSaverEnabled == value) {
      return;
    }
    _dataSaverEnabled = value;
    _applyDataSaverFilter();
    notifyListeners();
  }

  void _applyDataSaverFilter() {
    if (_allStations.isEmpty) {
      return;
    }
    if (!_dataSaverEnabled) {
      stations = List<RadioStation>.from(_allStations);
      _applyFavoritesOrdering();
      _reconcileVisibleStations();
      return;
    }
    final filtered = _allStations.where((station) {
      final bitrate = _parseBitrate(station.bitrate);
      return bitrate != null && bitrate <= 64;
    }).toList();
    stations = filtered.isNotEmpty
        ? filtered
        : List<RadioStation>.from(_allStations);
    _applyFavoritesOrdering();
    _reconcileVisibleStations();
  }

  int? _parseBitrate(String value) {
    if (value.trim().isEmpty) {
      return null;
    }
    final digits = RegExp(r'(\d+)').firstMatch(value);
    if (digits == null) {
      return null;
    }
    return int.tryParse(digits.group(1) ?? '');
  }

  void _applyFavoritesOrdering() {
    if (stations.isEmpty || _favoriteStationIds.isEmpty) {
      return;
    }
    final favs = <RadioStation>[];
    final rest = <RadioStation>[];
    for (final station in stations) {
      if (_favoriteStationIds.contains(station.streamUrl)) {
        favs.add(station);
      } else {
        rest.add(station);
      }
    }
    stations = [...favs, ...rest];
    _reconcileVisibleStations();
    notifyListeners();
  }

  Future<void> selectCountry(Country country) async {
    selectedCountry = country;
    selectedStation = null;
    errorMessage = null;
    notifyListeners();
    await _persistSelectedCountry(country);
    try {
      final cached = await _loadCachedStations(country);
      if (cached != null && cached.isNotEmpty) {
        stations = cached;
        _allStations = List<RadioStation>.from(cached);
        _applyDataSaverFilter();
        _reconcileVisibleStations();
        notifyListeners();
        return;
      }
      isLoading = true;
      notifyListeners();
      stations = await _service.fetchStations(country);
      _allStations = List<RadioStation>.from(stations);
      _applyDataSaverFilter();
      _reconcileVisibleStations();
      await _saveCachedStations(country, _allStations);
    } catch (_) {
      errorMessage = 'Failed to load stations. Please try again.';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshStations() async {
    final country = selectedCountry;
    if (country == null) {
      return;
    }
    final selectedStreamUrl = selectedStation?.streamUrl;
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      stations = await _service.fetchStations(country);
      _allStations = List<RadioStation>.from(stations);
      _applyDataSaverFilter();
      if (selectedStreamUrl != null) {
        final match = _allStations.firstWhere(
          (station) => station.streamUrl == selectedStreamUrl,
          orElse: () => selectedStation!,
        );
        selectedStation = match;
      }
      _reconcileVisibleStations();
      await _saveCachedStations(country, _allStations);
    } catch (_) {
      errorMessage = 'Failed to refresh stations. Please try again.';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> ensureAutoCountrySelected() async {
    if (_autoCountryRequested || selectedCountry != null) {
      return;
    }
    _autoCountryRequested = true;
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
        timeLimit: const Duration(seconds: 10),
      );
      final placemarks = await geocoding.placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isEmpty) {
        return;
      }
      final countryCode = placemarks.first.isoCountryCode;
      if (countryCode == null) {
        return;
      }
      final match = Country.defaults.firstWhere(
        (country) => country.code.toUpperCase() == countryCode.toUpperCase(),
        orElse: () => Country.defaults.first,
      );
      await selectCountry(match);
    } catch (_) {
      // Ignore auto-detect errors and let user select manually.
    }
  }

  void selectStation(RadioStation station) {
    selectedStation = station;
    notifyListeners();
  }

  bool isFavoriteStation(RadioStation station) {
    return _favoriteStationIds.contains(station.streamUrl);
  }

  List<RadioStation> sortStationsByFavorite(List<RadioStation> list) {
    if (_favoriteStationIds.isEmpty) {
      return List<RadioStation>.from(list);
    }
    final favs = <RadioStation>[];
    final rest = <RadioStation>[];
    for (final station in list) {
      if (_favoriteStationIds.contains(station.streamUrl)) {
        favs.add(station);
      } else {
        rest.add(station);
      }
    }
    return [...favs, ...rest];
  }

  Future<void> toggleFavoriteStation(RadioStation station) async {
    if (_favoriteStationIds.contains(station.streamUrl)) {
      _favoriteStationIds.remove(station.streamUrl);
    } else {
      _favoriteStationIds.add(station.streamUrl);
      stations.remove(station);
      stations.insert(0, station);
      _reconcileVisibleStations();
    }
    notifyListeners();
    await _persistFavoriteStations();
    final country = selectedCountry;
    if (country != null) {
      await _saveCachedStations(country, _allStations.isNotEmpty ? _allStations : stations);
    }
  }
}

class PlayerState extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();
  RadioStation? currentStation;
  String? currentRecordingPath;
  bool isPlaying = false;
  bool isLoading = false;
  String? errorMessage;
  double volume = 1.0;

  PlayerState() {
    Future.microtask(() => _player.setLoopMode(LoopMode.off));
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        isPlaying = false;
        currentRecordingPath = null;
        _player.stop();
      } else {
        isPlaying = state.playing;
      }
      notifyListeners();
    });
    volume = _player.volume;
  }

  Future<void> play(RadioStation station) async {
    currentStation = station;
    currentRecordingPath = null;
    errorMessage = null;
    isLoading = true;
    notifyListeners();
    try {
      await _player.stop();
      final source = AudioSource.uri(
        Uri.parse(station.streamUrl),
        tag: MediaItem(
          id: station.streamUrl,
          album: station.country,
          title: station.name,
          artist: station.frequency,
        ),
      );
      await _player.setAudioSource(source);
      await _player.play();
    } catch (error) {
      final message = error.toString();
      final isMediaServerDied = message.contains('Media server died') ||
          message.contains('media server died') ||
          message.contains('AudioFlinger');
      if (isMediaServerDied) {
        try {
          await _player.stop();
          await Future.delayed(const Duration(milliseconds: 300));
          await _player.setAudioSource(AudioSource.uri(
            Uri.parse(station.streamUrl),
            tag: MediaItem(
              id: station.streamUrl,
              album: station.country,
              title: station.name,
              artist: station.frequency,
            ),
          ));
          await _player.play();
          errorMessage = null;
        } catch (retryError) {
          errorMessage = 'Unable to play this station. ${retryError.toString()}';
          debugPrint('Playback error (after retry): $retryError');
        }
      } else {
        errorMessage = 'Unable to play this station. $message';
        debugPrint('Playback error: $error');
      }
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> pause() async {
    await _player.pause();
  }

  Future<void> stop() async {
    await _player.stop();
    isPlaying = false;
    currentRecordingPath = null;
    notifyListeners();
  }

  Future<void> setVolume(double value) async {
    volume = value;
    await _player.setVolume(value);
    notifyListeners();
  }

  Future<void> seekRelative(Duration offset) async {
    final position = _player.position;
    final duration = _player.duration;
    if (duration == null) {
      return;
    }
    final next = position + offset;
    final clamped = next < Duration.zero
        ? Duration.zero
        : (next > duration ? duration : next);
    await _player.seek(clamped);
  }

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Duration get position => _player.position;
  Duration? get duration => _player.duration;

  Future<void> playRecording(String path) async {
    if (isLoading) {
      return;
    }
    currentStation = null;
    currentRecordingPath = path;
    errorMessage = null;
    isLoading = true;
    notifyListeners();
    try {
      await _player.stop();
      final source = AudioSource.uri(
        Uri.file(path),
        tag: MediaItem(
          id: path,
          album: 'Recordings',
          title: path.split('/').last,
          artist: 'FMoIP',
        ),
      );
      await _player.setAudioSource(source);
      await _player.play();
    } catch (error) {
      errorMessage = 'Unable to play this recording. ${error.toString()}';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}

class RecordingState extends ChangeNotifier {
  bool isRecording = false;
  bool isVoiceRecording = false;
  String? errorMessage;
  final List<RecordingItem> recordings = [];
  final Set<String> _favoriteRecordingPaths = {};
  static const String _favoriteRecordingsKey = 'favorite_recording_paths';
  int _recordingsPageSize = 30;
  int _visibleRecordingCount = 30;
  http.Client? _client;
  StreamSubscription<List<int>>? _subscription;
  IOSink? _fileSink;
  File? _currentFile;
  File? _currentVoiceFile;
  bool _shouldResumePlayback = false;
  RecordingMode? _activeMode;
  DateTime? _recordingStartedAt;
  int _recordingBytes = 0;
  bool showRecordingsList = false;
  String? _recordingStationName;
  RecordingMode? _recordingMode;
  DateTime? _voiceRecordingStartedAt;
  AudioRecorder? _voiceRecorder;

  RecordingState() {
    _loadExistingRecordings();
    _initVoiceRecorder();
    _loadFavoriteRecordings();
  }

  Future<void> _loadFavoriteRecordings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final values = prefs.getStringList(_favoriteRecordingsKey) ?? [];
      _favoriteRecordingPaths
        ..clear()
        ..addAll(values);
      _applyFavoriteRecordingsOrdering();
    } catch (_) {
      // Ignore restore errors.
    }
  }

  Future<void> _persistFavoriteRecordings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _favoriteRecordingsKey,
        _favoriteRecordingPaths.toList(),
      );
    } catch (_) {
      // Ignore persistence errors.
    }
  }

  void _applyFavoriteRecordingsOrdering() {
    if (recordings.isEmpty || _favoriteRecordingPaths.isEmpty) {
      return;
    }
    final favs = <RecordingItem>[];
    final rest = <RecordingItem>[];
    for (final item in recordings) {
      if (_favoriteRecordingPaths.contains(item.path)) {
        favs.add(item);
      } else {
        rest.add(item);
      }
    }
    recordings
      ..clear()
      ..addAll([...favs, ...rest]);
    _reconcileVisibleRecordings();
    notifyListeners();
  }

  bool isFavoriteRecording(RecordingItem item) {
    return _favoriteRecordingPaths.contains(item.path);
  }

  List<RecordingItem> sortRecordingsByFavorite(List<RecordingItem> list) {
    if (_favoriteRecordingPaths.isEmpty) {
      return List<RecordingItem>.from(list);
    }
    final favs = <RecordingItem>[];
    final rest = <RecordingItem>[];
    for (final item in list) {
      if (_favoriteRecordingPaths.contains(item.path)) {
        favs.add(item);
      } else {
        rest.add(item);
      }
    }
    return [...favs, ...rest];
  }

  Future<void> toggleFavoriteRecording(RecordingItem item) async {
    if (_favoriteRecordingPaths.contains(item.path)) {
      _favoriteRecordingPaths.remove(item.path);
    } else {
      _favoriteRecordingPaths.add(item.path);
      recordings.removeWhere((recording) => recording.path == item.path);
      recordings.insert(0, item);
      _reconcileVisibleRecordings();
    }
    notifyListeners();
    await _persistFavoriteRecordings();
  }

  List<RecordingItem> get visibleRecordings =>
      recordings.take(_visibleRecordingCount).toList();

  bool get hasMoreRecordings => recordings.length > _visibleRecordingCount;

  void loadMoreRecordings() {
    if (!hasMoreRecordings) {
      return;
    }
    _visibleRecordingCount =
        min(_visibleRecordingCount + _recordingsPageSize, recordings.length);
    notifyListeners();
  }

  void setRecordingsPageSize(int value) {
    final next = value.clamp(5, 200);
    if (_recordingsPageSize == next) {
      return;
    }
    _recordingsPageSize = next;
    _reconcileVisibleRecordings();
    notifyListeners();
  }

  void _reconcileVisibleRecordings() {
    if (_visibleRecordingCount <= 0) {
      _visibleRecordingCount = min(_recordingsPageSize, recordings.length);
      return;
    }
    if (_visibleRecordingCount > recordings.length) {
      _visibleRecordingCount = recordings.length;
    }
    if (_visibleRecordingCount < _recordingsPageSize) {
      _visibleRecordingCount = min(_recordingsPageSize, recordings.length);
    }
  }

  Future<void> _initVoiceRecorder() async {
    _voiceRecorder ??= AudioRecorder();
  }

  Future<File> _metadataFileForRecording(File file) async {
    final base = file.path.replaceAll(RegExp(r'\.[^.]+$'), '');
    return File('$base.json');
  }

  Future<Map<String, dynamic>?> _loadRecordingMetadata(File file) async {
    try {
      final metaFile = await _metadataFileForRecording(file);
      if (!await metaFile.exists()) {
        return null;
      }
      final contents = await metaFile.readAsString();
      final data = jsonDecode(contents);
      return data is Map<String, dynamic> ? data : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveRecordingMetadata(
    File file, {
    required String stationName,
    RecordingMode? mode,
    DateTime? createdAt,
    int? durationSeconds,
    String? displayName,
  }) async {
    try {
      final metaFile = await _metadataFileForRecording(file);
      final data = <String, dynamic>{
        'stationName': stationName,
        'mode': mode?.name,
        'createdAt': (createdAt ?? DateTime.now()).toIso8601String(),
        if (displayName != null && displayName.isNotEmpty) 'displayName': displayName,
        if (durationSeconds != null) 'durationSeconds': durationSeconds,
      };
      await metaFile.writeAsString(jsonEncode(data));
    } catch (_) {
      // Ignore metadata write errors.
    }
  }

  RecordingMode? _modeFromString(String? value) {
    switch (value) {
      case 'withBackground':
        return RecordingMode.withBackground;
      case 'streamOnly':
        return RecordingMode.streamOnly;
      default:
        return null;
    }
  }

  Future<void> _loadExistingRecordings() async {
    final directory = await getApplicationDocumentsDirectory();
    final files = directory
        .listSync()
        .whereType<File>()
        .where(_isRecordingFile)
        .toList();
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    recordings.clear();
    for (final file in files) {
      final meta = await _loadRecordingMetadata(file);
      final stationName = meta?['stationName']?.toString();
      final mode = _modeFromString(meta?['mode']?.toString());
      final durationSeconds = int.tryParse(meta?['durationSeconds']?.toString() ?? '');
      final displayName = meta?['displayName']?.toString();
      recordings.add(
        RecordingItem.fromFile(
          file,
          stationName: stationName,
          mode: mode,
          durationSeconds: durationSeconds,
          displayName: displayName,
        ),
      );
    }
    _reconcileVisibleRecordings();
    _applyFavoriteRecordingsOrdering();
    notifyListeners();
  }

  bool _isRecordingFile(File file) {
    final lower = file.path.toLowerCase();
    return lower.endsWith('.mp3') ||
        lower.endsWith('.aac') ||
        lower.endsWith('.m4a') ||
        lower.endsWith('.ogg') ||
        lower.endsWith('.flac') ||
        lower.endsWith('.wav');
  }

  Future<void> startRecording(RadioStation station, {required RecordingMode mode}) async {
    if (isRecording) {
      return;
    }
    errorMessage = null;
    _activeMode = mode;
    _recordingMode = mode;
    _recordingStationName = station.name;
    isRecording = true;
    notifyListeners();
    final directory = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now();
    _client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(station.streamUrl));
      request.headers['Icy-MetaData'] = '1';
      request.headers['User-Agent'] = 'FMoIP/1.0';
      final response = await _client!.send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        errorMessage = 'Unable to record this station.';
        _client!.close();
        _client = null;
        _activeMode = null;
        notifyListeners();
        return;
      }
        final contentType = response.headers['content-type']?.toLowerCase() ?? '';
        final extension = _extensionFromContentType(contentType) ??
          _extensionFromUrl(station.streamUrl) ??
          'mp3';
      final filePath = '${directory.path}/rec_${timestamp.millisecondsSinceEpoch}.$extension';
      _currentFile = File(filePath);
      _fileSink = _currentFile!.openWrite();
      _recordingStartedAt = null;
      _recordingBytes = 0;
      notifyListeners();
      _subscription = response.stream.listen(
        (data) {
          if (_recordingStartedAt == null) {
            _recordingStartedAt = DateTime.now();
          }
          _recordingBytes += data.length;
          _fileSink!.add(data);
        },
        onError: (_) async {
          await stopRecording();
          errorMessage = 'Recording stopped unexpectedly.';
          notifyListeners();
        },
        onDone: () async {
          await stopRecording();
        },
        cancelOnError: true,
      );
    } catch (_) {
      errorMessage = 'Unable to record this station.';
      _client?.close();
      _client = null;
      _activeMode = null;
      isRecording = false;
      notifyListeners();
    }
  }

  Future<void> startVoiceRecording() async {
    if (isVoiceRecording || isRecording) {
      return;
    }
    await _initVoiceRecorder();
    final hasPermission = await _voiceRecorder!.hasPermission();
    if (!hasPermission) {
      errorMessage = 'Microphone permission required.';
      notifyListeners();
      return;
    }
    final directory = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now();
    final filePath = '${directory.path}/voice_${timestamp.millisecondsSinceEpoch}.m4a';
    _currentVoiceFile = File(filePath);
    _voiceRecordingStartedAt = timestamp;
    errorMessage = null;
    await _voiceRecorder!.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
        androidConfig: AndroidRecordConfig(muteAudio: false),
        audioInterruption: AudioInterruptionMode.none,
      ),
      path: filePath,
    );
    isVoiceRecording = true;
    notifyListeners();
  }

  Future<void> stopVoiceRecording() async {
    if (!isVoiceRecording) {
      return;
    }
    final durationSeconds = _voiceRecordingStartedAt == null
        ? null
        : DateTime.now().difference(_voiceRecordingStartedAt!).inSeconds;
    await _voiceRecorder?.stop();
    isVoiceRecording = false;
    if (_currentVoiceFile != null && await _currentVoiceFile!.exists()) {
      await _saveRecordingMetadata(
        _currentVoiceFile!,
        stationName: 'Voice note',
        mode: null,
        createdAt: _voiceRecordingStartedAt,
        durationSeconds: durationSeconds,
      );
      recordings.insert(
        0,
        RecordingItem.fromFile(
          _currentVoiceFile!,
          stationName: 'Voice note',
          mode: null,
        ),
      );
      if (recordings.length > 50) {
        recordings.removeRange(50, recordings.length);
      }
    }
    _currentVoiceFile = null;
    _voiceRecordingStartedAt = null;
    _reconcileVisibleRecordings();
    notifyListeners();
  }

  Future<void> stopRecording() async {
    if (!isRecording) {
      return;
    }
    isRecording = false;
    notifyListeners();
    final startedAt = _recordingStartedAt ?? DateTime.now();
    final durationSeconds = DateTime.now().difference(startedAt).inSeconds;
    await _subscription?.cancel();
    await _fileSink?.flush();
    await _fileSink?.close();
    _client?.close();
    _subscription = null;
    _fileSink = null;
    _client = null;
    _activeMode = null;
    _shouldResumePlayback = false;
    var discardRecording = false;
    if (_recordingStartedAt != null) {
      final elapsed = DateTime.now().difference(_recordingStartedAt!);
      if (elapsed < const Duration(seconds: 1)) {
        discardRecording = true;
        errorMessage = _recordingBytes == 0
            ? 'This station does not support recording.'
            : 'Recording shorter than 1 second was not saved.';
      }
    }
    if (_currentFile != null && await _currentFile!.exists()) {
      if (discardRecording) {
        await _currentFile!.delete();
      } else {
        await _saveRecordingMetadata(
          _currentFile!,
          stationName: _recordingStationName ?? '-',
          mode: _recordingMode,
          createdAt: _recordingStartedAt,
          durationSeconds: durationSeconds,
        );
        recordings.insert(
          0,
          RecordingItem.fromFile(
            _currentFile!,
            stationName: _recordingStationName,
            mode: _recordingMode,
          ),
        );
        if (recordings.length > 50) {
          recordings.removeRange(50, recordings.length);
        }
      }
    }
    _currentFile = null;
    _recordingStartedAt = null;
    _recordingBytes = 0;
    _recordingStationName = null;
    _recordingMode = null;
    _reconcileVisibleRecordings();
    notifyListeners();
  }

  Future<void> deleteRecording(RecordingItem item) async {
    final file = File(item.path);
    if (await file.exists()) {
      await file.delete();
    }
    try {
      final metaFile = await _metadataFileForRecording(file);
      if (await metaFile.exists()) {
        await metaFile.delete();
      }
    } catch (_) {
      // Ignore metadata delete errors.
    }
    recordings.removeWhere((recording) => recording.path == item.path);
    _favoriteRecordingPaths.remove(item.path);
    await _persistFavoriteRecordings();
    _reconcileVisibleRecordings();
    notifyListeners();
  }

  Future<void> reloadRecordings() async {
    await _loadExistingRecordings();
  }

  Future<void> updateRecordingDisplayName(RecordingItem item, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final file = File(item.path);
    if (!await file.exists()) {
      return;
    }
    await _saveRecordingMetadata(
      file,
      stationName: item.stationName,
      mode: item.mode,
      createdAt: item.createdAt,
      durationSeconds: item.durationSeconds,
      displayName: trimmed,
    );
    final updated = RecordingItem.fromFile(
      file,
      stationName: item.stationName,
      mode: item.mode,
      durationSeconds: item.durationSeconds,
      displayName: trimmed,
    );
    _replaceRecording(item.path, updated);
  }

  Future<void> renameRecordingFile(RecordingItem item, String newBaseName) async {
    final sanitized = _sanitizeFileBaseName(newBaseName);
    if (sanitized.isEmpty) {
      return;
    }
    final file = File(item.path);
    if (!await file.exists()) {
      return;
    }
    final extMatch = RegExp(r'\.([^.]+)$').firstMatch(file.path);
    final ext = extMatch != null ? extMatch.group(1) : null;
    if (ext == null) {
      return;
    }
    final dir = file.parent.path;
    var candidate = '$dir/$sanitized.$ext';
    var counter = 1;
    while (await File(candidate).exists()) {
      candidate = '$dir/${sanitized}_$counter.$ext';
      counter++;
    }
    final renamedFile = await file.rename(candidate);
    try {
      final oldMeta = await _metadataFileForRecording(file);
      final newMeta = await _metadataFileForRecording(renamedFile);
      if (await oldMeta.exists()) {
        await oldMeta.rename(newMeta.path);
      }
    } catch (_) {
      // Ignore metadata rename errors.
    }
    await _saveRecordingMetadata(
      renamedFile,
      stationName: item.stationName,
      mode: item.mode,
      createdAt: item.createdAt,
      durationSeconds: item.durationSeconds,
      displayName: sanitized,
    );
    if (_favoriteRecordingPaths.remove(item.path)) {
      _favoriteRecordingPaths.add(renamedFile.path);
    }
    await _persistFavoriteRecordings();
    final updated = RecordingItem.fromFile(
      renamedFile,
      stationName: item.stationName,
      mode: item.mode,
      durationSeconds: item.durationSeconds,
      displayName: sanitized,
    );
    _replaceRecording(item.path, updated);
  }

  void _replaceRecording(String oldPath, RecordingItem updated) {
    final index = recordings.indexWhere((recording) => recording.path == oldPath);
    if (index == -1) {
      return;
    }
    recordings[index] = updated;
    _reconcileVisibleRecordings();
    notifyListeners();
  }

  String _sanitizeFileBaseName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    return trimmed.replaceAll(RegExp(r'[\\/]+'), '-');
  }

  void setShouldResumePlayback(bool value) {
    _shouldResumePlayback = value;
  }

  bool get shouldResumePlayback => _shouldResumePlayback;

  RecordingMode? get activeMode => _activeMode;

  DateTime? get recordingStartedAt => _recordingStartedAt;

  DateTime? get voiceRecordingStartedAt => _voiceRecordingStartedAt;

  void toggleRecordingsList() {
    showRecordingsList = !showRecordingsList;
    notifyListeners();
  }

  String? _extensionFromContentType(String contentType) {
    if (contentType.contains('aac') || contentType.contains('aacp') || contentType.contains('adts')) {
      return 'aac';
    }
    if (contentType.contains('ogg')) {
      return 'ogg';
    }
    if (contentType.contains('flac')) {
      return 'flac';
    }
    if (contentType.contains('wav')) {
      return 'wav';
    }
    if (contentType.contains('mpeg') || contentType.contains('mp3')) {
      return 'mp3';
    }
    return null;
  }

  String? _extensionFromUrl(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('.mp3')) return 'mp3';
    if (lower.contains('.aac')) return 'aac';
    if (lower.contains('.m4a')) return 'm4a';
    if (lower.contains('.ogg')) return 'ogg';
    if (lower.contains('.flac')) return 'flac';
    if (lower.contains('.wav')) return 'wav';
    return null;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _fileSink?.close();
    _client?.close();
    _voiceRecorder?.dispose();
    super.dispose();
  }
}

class RecordingItem {
  RecordingItem({
    required this.name,
    required this.path,
    required this.sizeBytes,
    required this.createdAt,
    required this.stationName,
    required this.mode,
    required this.durationSeconds,
  });

  final String name;
  final String path;
  final int sizeBytes;
  final DateTime createdAt;
  final String stationName;
  final RecordingMode? mode;
  final int? durationSeconds;

  String get sizeLabel {
    if (sizeBytes >= 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (sizeBytes >= 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$sizeBytes B';
  }

  factory RecordingItem.fromFile(
    File file, {
    String? stationName,
    RecordingMode? mode,
    int? durationSeconds,
    String? displayName,
  }) {
    final stat = file.statSync();
    final rawName = file.uri.pathSegments.last;
    final name = rawName.replaceAll(RegExp(r'\.[^.]+$'), '');
    return RecordingItem(
      name: (displayName != null && displayName.isNotEmpty) ? displayName : name,
      path: file.path,
      sizeBytes: stat.size,
      createdAt: stat.modified,
      stationName: stationName ?? '-',
      mode: mode,
      durationSeconds: durationSeconds,
    );
  }
}

class SubscriptionState extends ChangeNotifier {
  static const String _isProKey = 'subscription_is_pro';

  bool isPro = false;
  bool isLoading = false;
  String? errorMessage;

  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;

  SubscriptionState() {
    Future.microtask(() => _loadAndInit());
  }

  Future<void> _loadAndInit() async {
    final prefs = await SharedPreferences.getInstance();
    isPro = prefs.getBool(_isProKey) ?? false;
    notifyListeners();
    _listenToPurchases();
    // After reinstall we have no local pro flag; ask the store to restore.
    if (!isPro) {
      Future.microtask(() => _restorePurchasesIfAvailable());
    }
  }

  /// Silent restore on startup so reinstalling users get their subscription back.
  Future<void> _restorePurchasesIfAvailable() async {
    final available = await InAppPurchase.instance.isAvailable();
    if (!available) return;
    try {
      await InAppPurchase.instance.restorePurchases();
    } catch (_) {}
  }

  void _listenToPurchases() {
    _purchaseSubscription?.cancel();
    _purchaseSubscription = InAppPurchase.instance.purchaseStream.listen(
      _onPurchaseUpdates,
      onDone: () => _purchaseSubscription = null,
      onError: (Object e) {
        errorMessage = e.toString();
        isLoading = false;
        notifyListeners();
      },
    );
  }

  Future<void> _onPurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.productID != IapConfig.subscriptionProductId) continue;
      switch (purchase.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          isPro = true;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool(_isProKey, true);
          if (purchase.pendingCompletePurchase) {
            await InAppPurchase.instance.completePurchase(purchase);
          }
          break;
        case PurchaseStatus.error:
          errorMessage = purchase.error?.message ?? 'Purchase failed';
          break;
        case PurchaseStatus.canceled:
          break;
        case PurchaseStatus.pending:
          break;
      }
    }
    isLoading = false;
    errorMessage = null;
    notifyListeners();
  }

  Future<void> purchaseSubscription() async {
    if (isLoading) return;
    errorMessage = null;
    isLoading = true;
    notifyListeners();
    final available = await InAppPurchase.instance.isAvailable();
    if (!available) {
      errorMessage = 'Store is not available.';
      isLoading = false;
      notifyListeners();
      return;
    }
    final response = await InAppPurchase.instance.queryProductDetails(
      IapConfig.productIds,
    );
    if (response.notFoundIDs.isNotEmpty) {
      errorMessage = 'Subscription product not found. Add "${IapConfig.subscriptionProductId}" in Play Console / App Store Connect.';
      isLoading = false;
      notifyListeners();
      return;
    }
    final productDetails = response.productDetails;
    if (productDetails.isEmpty) {
      errorMessage = 'Subscription not available.';
      isLoading = false;
      notifyListeners();
      return;
    }
    final product = productDetails.first;
    final success = await InAppPurchase.instance.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: product),
    );
    if (!success) {
      errorMessage = 'Could not start purchase.';
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> restorePurchases() async {
    if (isLoading) return;
    errorMessage = null;
    isLoading = true;
    notifyListeners();
    final available = await InAppPurchase.instance.isAvailable();
    if (!available) {
      errorMessage = 'Store is not available.';
      isLoading = false;
      notifyListeners();
      return;
    }
    try {
      await InAppPurchase.instance.restorePurchases();
    } catch (e) {
      errorMessage = e.toString();
    }
    isLoading = false;
    notifyListeners();
  }

  void clearError() {
    errorMessage = null;
    notifyListeners();
  }
}

class SettingsState extends ChangeNotifier {
  Locale _locale = const Locale('en');
  bool dataSaver = false;
  RecordingQuality recordingQuality = RecordingQuality.high;
  RecordingMode recordingMode = RecordingMode.streamOnly;
  ThemeMode themeMode = ThemeMode.system;
  int listPageSize = 50;

  Locale get locale => _locale;

  void setLocale(Locale value) {
    _locale = value;
    notifyListeners();
  }

  void setDataSaver(bool value) {
    dataSaver = value;
    notifyListeners();
  }

  void setRecordingQuality(RecordingQuality value) {
    recordingQuality = value;
    notifyListeners();
  }

  void setRecordingMode(RecordingMode value) {
    recordingMode = value;
    notifyListeners();
  }

  void setThemeMode(ThemeMode value) {
    themeMode = value;
    notifyListeners();
  }

  void setListPageSize(int value) {
    listPageSize = value;
    notifyListeners();
  }
}
String _themeModeLabel(ThemeMode mode, AppLocalizations strings) {
  switch (mode) {
    case ThemeMode.system:
      return strings.themeSystem;
    case ThemeMode.dark:
      return strings.themeDark;
    case ThemeMode.light:
      return strings.themeLight;
  }
}

String _formatRecordingTime(DateTime dateTime) {
  final local = dateTime.toLocal();
  final yyyy = local.year.toString().padLeft(4, '0');
  final mm = local.month.toString().padLeft(2, '0');
  final dd = local.day.toString().padLeft(2, '0');
  final hh = local.hour.toString().padLeft(2, '0');
  final min = local.minute.toString().padLeft(2, '0');
  return '$yyyy-$mm-$dd $hh:$min';
}

String _formatDuration(Duration duration) {
  final totalSeconds = duration.inSeconds.clamp(0, 24 * 60 * 60);
  final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

String _formatDurationProgress(Duration position, Duration? total) {
  if (total == null || total.inSeconds <= 0) {
    return _formatDuration(position);
  }
  return '${_formatDuration(position)} / ${_formatDuration(total)}';
}

class Country {
  const Country({required this.name, required this.code});

  final String name;
  final String code;

  static const List<Country> defaults = [
    Country(name: 'Afghanistan', code: 'AF'),
    Country(name: 'Albania', code: 'AL'),
    Country(name: 'Algeria', code: 'DZ'),
    Country(name: 'Andorra', code: 'AD'),
    Country(name: 'Angola', code: 'AO'),
    Country(name: 'Antigua and Barbuda', code: 'AG'),
    Country(name: 'Argentina', code: 'AR'),
    Country(name: 'Armenia', code: 'AM'),
    Country(name: 'Australia', code: 'AU'),
    Country(name: 'Austria', code: 'AT'),
    Country(name: 'Azerbaijan', code: 'AZ'),
    Country(name: 'Bahamas', code: 'BS'),
    Country(name: 'Bahrain', code: 'BH'),
    Country(name: 'Bangladesh', code: 'BD'),
    Country(name: 'Barbados', code: 'BB'),
    Country(name: 'Belarus', code: 'BY'),
    Country(name: 'Belgium', code: 'BE'),
    Country(name: 'Belize', code: 'BZ'),
    Country(name: 'Benin', code: 'BJ'),
    Country(name: 'Bhutan', code: 'BT'),
    Country(name: 'Bolivia', code: 'BO'),
    Country(name: 'Bosnia and Herzegovina', code: 'BA'),
    Country(name: 'Botswana', code: 'BW'),
    Country(name: 'Brazil', code: 'BR'),
    Country(name: 'Brunei', code: 'BN'),
    Country(name: 'Bulgaria', code: 'BG'),
    Country(name: 'Burkina Faso', code: 'BF'),
    Country(name: 'Burundi', code: 'BI'),
    Country(name: 'Cabo Verde', code: 'CV'),
    Country(name: 'Cambodia', code: 'KH'),
    Country(name: 'Cameroon', code: 'CM'),
    Country(name: 'Canada', code: 'CA'),
    Country(name: 'Central African Republic', code: 'CF'),
    Country(name: 'Chad', code: 'TD'),
    Country(name: 'Chile', code: 'CL'),
    Country(name: 'China', code: 'CN'),
    Country(name: 'Colombia', code: 'CO'),
    Country(name: 'Comoros', code: 'KM'),
    Country(name: 'Congo (Congo-Brazzaville)', code: 'CG'),
    Country(name: 'Costa Rica', code: 'CR'),
    Country(name: 'Croatia', code: 'HR'),
    Country(name: 'Cuba', code: 'CU'),
    Country(name: 'Cyprus', code: 'CY'),
    Country(name: 'Czechia', code: 'CZ'),
    Country(name: 'Democratic Republic of the Congo', code: 'CD'),
    Country(name: 'Denmark', code: 'DK'),
    Country(name: 'Djibouti', code: 'DJ'),
    Country(name: 'Dominica', code: 'DM'),
    Country(name: 'Dominican Republic', code: 'DO'),
    Country(name: 'Ecuador', code: 'EC'),
    Country(name: 'Egypt', code: 'EG'),
    Country(name: 'El Salvador', code: 'SV'),
    Country(name: 'Equatorial Guinea', code: 'GQ'),
    Country(name: 'Eritrea', code: 'ER'),
    Country(name: 'Estonia', code: 'EE'),
    Country(name: 'Eswatini', code: 'SZ'),
    Country(name: 'Ethiopia', code: 'ET'),
    Country(name: 'Fiji', code: 'FJ'),
    Country(name: 'Finland', code: 'FI'),
    Country(name: 'France', code: 'FR'),
    Country(name: 'Gabon', code: 'GA'),
    Country(name: 'Gambia', code: 'GM'),
    Country(name: 'Georgia', code: 'GE'),
    Country(name: 'Germany', code: 'DE'),
    Country(name: 'Ghana', code: 'GH'),
    Country(name: 'Greece', code: 'GR'),
    Country(name: 'Grenada', code: 'GD'),
    Country(name: 'Guatemala', code: 'GT'),
    Country(name: 'Guinea', code: 'GN'),
    Country(name: 'Guinea-Bissau', code: 'GW'),
    Country(name: 'Guyana', code: 'GY'),
    Country(name: 'Haiti', code: 'HT'),
    Country(name: 'Honduras', code: 'HN'),
    Country(name: 'Hungary', code: 'HU'),
    Country(name: 'Iceland', code: 'IS'),
    Country(name: 'India', code: 'IN'),
    Country(name: 'Indonesia', code: 'ID'),
    Country(name: 'Iran', code: 'IR'),
    Country(name: 'Iraq', code: 'IQ'),
    Country(name: 'Ireland', code: 'IE'),
    Country(name: 'Israel', code: 'IL'),
    Country(name: 'Italy', code: 'IT'),
    Country(name: 'Jamaica', code: 'JM'),
    Country(name: 'Japan', code: 'JP'),
    Country(name: 'Jordan', code: 'JO'),
    Country(name: 'Kazakhstan', code: 'KZ'),
    Country(name: 'Kenya', code: 'KE'),
    Country(name: 'Kiribati', code: 'KI'),
    Country(name: 'Kuwait', code: 'KW'),
    Country(name: 'Kyrgyzstan', code: 'KG'),
    Country(name: 'Laos', code: 'LA'),
    Country(name: 'Latvia', code: 'LV'),
    Country(name: 'Lebanon', code: 'LB'),
    Country(name: 'Lesotho', code: 'LS'),
    Country(name: 'Liberia', code: 'LR'),
    Country(name: 'Libya', code: 'LY'),
    Country(name: 'Liechtenstein', code: 'LI'),
    Country(name: 'Lithuania', code: 'LT'),
    Country(name: 'Luxembourg', code: 'LU'),
    Country(name: 'Madagascar', code: 'MG'),
    Country(name: 'Malawi', code: 'MW'),
    Country(name: 'Malaysia', code: 'MY'),
    Country(name: 'Maldives', code: 'MV'),
    Country(name: 'Mali', code: 'ML'),
    Country(name: 'Malta', code: 'MT'),
    Country(name: 'Marshall Islands', code: 'MH'),
    Country(name: 'Mauritania', code: 'MR'),
    Country(name: 'Mauritius', code: 'MU'),
    Country(name: 'Mexico', code: 'MX'),
    Country(name: 'Micronesia', code: 'FM'),
    Country(name: 'Moldova', code: 'MD'),
    Country(name: 'Monaco', code: 'MC'),
    Country(name: 'Mongolia', code: 'MN'),
    Country(name: 'Montenegro', code: 'ME'),
    Country(name: 'Morocco', code: 'MA'),
    Country(name: 'Mozambique', code: 'MZ'),
    Country(name: 'Myanmar', code: 'MM'),
    Country(name: 'Namibia', code: 'NA'),
    Country(name: 'Nauru', code: 'NR'),
    Country(name: 'Nepal', code: 'NP'),
    Country(name: 'Netherlands', code: 'NL'),
    Country(name: 'New Zealand', code: 'NZ'),
    Country(name: 'Nicaragua', code: 'NI'),
    Country(name: 'Niger', code: 'NE'),
    Country(name: 'Nigeria', code: 'NG'),
    Country(name: 'North Korea', code: 'KP'),
    Country(name: 'North Macedonia', code: 'MK'),
    Country(name: 'Norway', code: 'NO'),
    Country(name: 'Oman', code: 'OM'),
    Country(name: 'Pakistan', code: 'PK'),
    Country(name: 'Palau', code: 'PW'),
    Country(name: 'Palestine', code: 'PS'),
    Country(name: 'Panama', code: 'PA'),
    Country(name: 'Papua New Guinea', code: 'PG'),
    Country(name: 'Paraguay', code: 'PY'),
    Country(name: 'Peru', code: 'PE'),
    Country(name: 'Philippines', code: 'PH'),
    Country(name: 'Poland', code: 'PL'),
    Country(name: 'Portugal', code: 'PT'),
    Country(name: 'Qatar', code: 'QA'),
    Country(name: 'Romania', code: 'RO'),
    Country(name: 'Russia', code: 'RU'),
    Country(name: 'Rwanda', code: 'RW'),
    Country(name: 'Saint Kitts and Nevis', code: 'KN'),
    Country(name: 'Saint Lucia', code: 'LC'),
    Country(name: 'Saint Vincent and the Grenadines', code: 'VC'),
    Country(name: 'Samoa', code: 'WS'),
    Country(name: 'San Marino', code: 'SM'),
    Country(name: 'Sao Tome and Principe', code: 'ST'),
    Country(name: 'Saudi Arabia', code: 'SA'),
    Country(name: 'Senegal', code: 'SN'),
    Country(name: 'Serbia', code: 'RS'),
    Country(name: 'Seychelles', code: 'SC'),
    Country(name: 'Sierra Leone', code: 'SL'),
    Country(name: 'Singapore', code: 'SG'),
    Country(name: 'Slovakia', code: 'SK'),
    Country(name: 'Slovenia', code: 'SI'),
    Country(name: 'Solomon Islands', code: 'SB'),
    Country(name: 'Somalia', code: 'SO'),
    Country(name: 'South Africa', code: 'ZA'),
    Country(name: 'South Korea', code: 'KR'),
    Country(name: 'South Sudan', code: 'SS'),
    Country(name: 'Spain', code: 'ES'),
    Country(name: 'Sri Lanka', code: 'LK'),
    Country(name: 'Sudan', code: 'SD'),
    Country(name: 'Suriname', code: 'SR'),
    Country(name: 'Sweden', code: 'SE'),
    Country(name: 'Switzerland', code: 'CH'),
    Country(name: 'Syria', code: 'SY'),
    Country(name: 'Taiwan', code: 'TW'),
    Country(name: 'Tajikistan', code: 'TJ'),
    Country(name: 'Tanzania', code: 'TZ'),
    Country(name: 'Thailand', code: 'TH'),
    Country(name: 'Timor-Leste', code: 'TL'),
    Country(name: 'Togo', code: 'TG'),
    Country(name: 'Tonga', code: 'TO'),
    Country(name: 'Trinidad and Tobago', code: 'TT'),
    Country(name: 'Tunisia', code: 'TN'),
    Country(name: 'Turkey', code: 'TR'),
    Country(name: 'Turkmenistan', code: 'TM'),
    Country(name: 'Tuvalu', code: 'TV'),
    Country(name: 'Uganda', code: 'UG'),
    Country(name: 'Ukraine', code: 'UA'),
    Country(name: 'United Arab Emirates', code: 'AE'),
    Country(name: 'United Kingdom', code: 'GB'),
    Country(name: 'United States', code: 'US'),
    Country(name: 'Uruguay', code: 'UY'),
    Country(name: 'Uzbekistan', code: 'UZ'),
    Country(name: 'Vanuatu', code: 'VU'),
    Country(name: 'Vatican City', code: 'VA'),
    Country(name: 'Venezuela', code: 'VE'),
    Country(name: 'Vietnam', code: 'VN'),
    Country(name: 'Yemen', code: 'YE'),
    Country(name: 'Zambia', code: 'ZM'),
    Country(name: 'Zimbabwe', code: 'ZW'),
  ];
}

class RadioStation {
  RadioStation({
    required this.name,
    required this.frequency,
    required this.streamUrl,
    required this.country,
    required this.faviconUrl,
    required this.language,
    required this.tags,
    required this.bitrate,
  });

  final String name;
  final String frequency;
  final String streamUrl;
  final String country;
  final String faviconUrl;
  final String language;
  final String tags;
  final String bitrate;

  @override
  bool operator ==(Object other) {
    return other is RadioStation && other.streamUrl == streamUrl;
  }

  @override
  int get hashCode => streamUrl.hashCode;
}

class RadioApiService {
  Future<List<RadioStation>> fetchStations(Country country) async {
    final uri = Uri.parse(
      'https://de1.api.radio-browser.info/json/stations/bycountry/${Uri.encodeComponent(country.name)}',
    );
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Request failed');
    }
    final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
    final mapped = data
        .whereType<Map<String, dynamic>>()
        .map((item) {
          final name = (item['name'] as String?)?.trim();
          final url = (item['url_resolved'] as String?)?.trim();
          final frequency = (item['frequency'] as String?)?.trim();
          final favicon = (item['favicon'] as String?)?.trim();
          final language = (item['language'] as String?)?.trim();
          final tags = (item['tags'] as String?)?.trim();
          final bitrate = (item['bitrate']?.toString())?.trim();
          if (name == null || name.isEmpty || url == null || url.isEmpty) {
            return null;
          }
          return RadioStation(
            name: name,
            frequency: frequency?.isNotEmpty == true ? frequency! : 'FM',
            streamUrl: url,
            country: country.name,
            faviconUrl: favicon ?? '',
            language: language ?? '',
            tags: tags ?? '',
            bitrate: bitrate ?? '',
          );
        })
        .whereType<RadioStation>();
    return mapped.toList();
  }
}

enum RecordingQuality { low, medium, high }

enum RecordingMode { withBackground, streamOnly }

extension RecordingQualityLabel on RecordingQuality {
  String label(AppLocalizations strings) {
    switch (this) {
      case RecordingQuality.low:
        return strings.low;
      case RecordingQuality.medium:
        return strings.medium;
      case RecordingQuality.high:
        return strings.high;
    }
  }
}

extension RecordingModeLabel on RecordingMode {
  String label(AppLocalizations strings) {
    switch (this) {
      case RecordingMode.withBackground:
        return strings.recordWithBackground;
      case RecordingMode.streamOnly:
        return strings.recordStreamOnly;
    }
  }
}

class AppLocalizations {
  AppLocalizations(this.locale);

  final Locale locale;

  static const supportedLocales = [
    Locale('en'),
    Locale('ar'),
    Locale('es'),
    Locale('zh'),
  ];

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const Map<String, Map<String, String>> _localizedValues = {
    'en': {
      'appTitle': 'FMoIP',
      'country': 'Country',
      'noStations': 'Select a country to load stations.',
      'play': 'Play',
      'pause': 'Pause',
      'startRecording': 'Record',
      'stopRecording': 'Stop',
      'nowPlaying': 'Now playing',
      'notPlaying': 'Not playing',
      'settings': 'Settings',
      'language': 'Language',
      'dataSaver': 'Data saver',
      'recordingQuality': 'Recording quality',
      'recordingMode': 'Default recording',
      'recordWithBackground': 'Record with background playback',
      'recordStreamOnly': 'Record stream only (mute playback)',
      'recordBgShort': 'REC BG',
      'themeMode': 'Theme mode',
      'themeSystem': 'System',
      'themeDark': 'Dark',
      'themeLight': 'Light',
      'stationMetadata': 'Station metadata',
      'stationName': 'Name',
      'stationCountry': 'Country',
      'stationFrequency': 'Frequency',
      'stationLanguage': 'Language',
      'stationTags': 'Tags',
      'stationBitrate': 'Bitrate',
      'duration': 'Duration',
      'stationLink': 'Station link',
      'stationDate': 'Date',
      'recordings': 'Recordings',
      'noRecordings': 'No recordings yet.',
      'recordingsCount': 'Recordings: {count}',
      'subscription': 'Subscription',
      'subscribed': 'Ad-free enabled',
      'notSubscribed': 'Free tier',
      'subscribe': 'Subscribe',
      'manage': 'Manage',
      'adPlaceholder': 'Ad banner',
      'loadMore': 'Load more',
      'searchStations': 'Search',
      'searchRecordings': 'Search',
      'editNameTitle': 'Edit name',
      'renameFileTitle': 'Rename file',
      'nameHint': 'Name',
      'save': 'Save',
      'deleteRecordingTitle': 'Delete recording?',
      'deleteRecordingBody': 'This recording will be permanently deleted.',
      'cancel': 'Cancel',
      'delete': 'Delete',
      'listPageSize': 'Rows per list',
      'low': 'Low',
      'medium': 'Medium',
      'high': 'High',
    },
    'ar': {
      'appTitle': 'FMoIP',
      'country': 'الدولة',
      'noStations': 'اختر دولة لتحميل المحطات.',
      'play': 'تشغيل',
      'pause': 'إيقاف مؤقت',
      'startRecording': 'تسجيل',
      'stopRecording': 'إيقاف',
      'nowPlaying': 'يتم التشغيل الآن',
      'notPlaying': 'غير مشغل',
      'settings': 'الإعدادات',
      'language': 'اللغة',
      'dataSaver': 'توفير البيانات',
      'recordingQuality': 'جودة التسجيل',
      'recordingMode': 'التسجيل الافتراضي',
      'recordWithBackground': 'التسجيل مع تشغيل الخلفية',
      'recordStreamOnly': 'تسجيل البث فقط (كتم التشغيل)',
      'recordBgShort': 'REC BG',
      'themeMode': 'وضع المظهر',
      'themeSystem': 'النظام',
      'themeDark': 'داكن',
      'themeLight': 'فاتح',
      'stationMetadata': 'بيانات المحطة',
      'stationName': 'الاسم',
      'stationCountry': 'الدولة',
      'stationFrequency': 'التردد',
      'stationLanguage': 'اللغة',
      'stationTags': 'الوسوم',
      'stationBitrate': 'معدل البت',
      'duration': 'المدة',
      'stationLink': 'رابط المحطة',
      'stationDate': 'التاريخ',
      'recordings': 'التسجيلات',
      'noRecordings': 'لا توجد تسجيلات بعد.',
      'recordingsCount': 'التسجيلات: {count}',
      'subscription': 'الاشتراك',
      'subscribed': 'بدون إعلانات',
      'notSubscribed': 'مجاني',
      'subscribe': 'اشترك',
      'manage': 'إدارة',
      'adPlaceholder': 'إعلان',
      'loadMore': 'تحميل المزيد',
      'searchStations': 'بحث',
      'searchRecordings': 'بحث',
      'editNameTitle': 'تعديل الاسم',
      'renameFileTitle': 'إعادة تسمية الملف',
      'nameHint': 'الاسم',
      'save': 'حفظ',
      'deleteRecordingTitle': 'حذف التسجيل؟',
      'deleteRecordingBody': 'سيتم حذف هذا التسجيل نهائيًا.',
      'cancel': 'إلغاء',
      'delete': 'حذف',
      'listPageSize': 'عدد الصفوف في القائمة',
      'low': 'منخفض',
      'medium': 'متوسط',
      'high': 'مرتفع',
    },
    'es': {
      'appTitle': 'FMoIP',
      'country': 'País',
      'noStations': 'Selecciona un país para cargar estaciones.',
      'play': 'Reproducir',
      'pause': 'Pausar',
      'startRecording': 'Grabar',
      'stopRecording': 'Detener',
      'nowPlaying': 'Reproduciendo',
      'notPlaying': 'Sin reproducción',
      'settings': 'Ajustes',
      'language': 'Idioma',
      'dataSaver': 'Ahorro de datos',
      'recordingQuality': 'Calidad de grabación',
      'recordingMode': 'Grabación predeterminada',
      'recordWithBackground': 'Grabar con reproducción en segundo plano',
      'recordStreamOnly': 'Grabar solo el stream (silenciar reproducción)',
      'recordBgShort': 'REC BG',
      'themeMode': 'Modo de tema',
      'themeSystem': 'Sistema',
      'themeDark': 'Oscuro',
      'themeLight': 'Claro',
      'stationMetadata': 'Metadatos de la emisora',
      'stationName': 'Nombre',
      'stationCountry': 'País',
      'stationFrequency': 'Frecuencia',
      'stationLanguage': 'Idioma',
      'stationTags': 'Etiquetas',
      'stationBitrate': 'Bitrate',
      'duration': 'Duración',
      'stationLink': 'Enlace de la emisora',
      'stationDate': 'Fecha',
      'recordings': 'Grabaciones',
      'noRecordings': 'Aún no hay grabaciones.',
      'recordingsCount': 'Grabaciones: {count}',
      'subscription': 'Suscripción',
      'subscribed': 'Sin anuncios',
      'notSubscribed': 'Gratis',
      'subscribe': 'Suscribirse',
      'manage': 'Administrar',
      'adPlaceholder': 'Anuncio',
      'loadMore': 'Cargar más',
      'searchStations': 'Buscar',
      'searchRecordings': 'Buscar',
      'editNameTitle': 'Editar nombre',
      'renameFileTitle': 'Renombrar archivo',
      'nameHint': 'Nombre',
      'save': 'Guardar',
      'deleteRecordingTitle': '¿Eliminar grabación?',
      'deleteRecordingBody': 'Esta grabación se eliminará permanentemente.',
      'cancel': 'Cancelar',
      'delete': 'Eliminar',
      'listPageSize': 'Filas por lista',
      'low': 'Baja',
      'medium': 'Media',
      'high': 'Alta',
    },
    'zh': {
      'appTitle': 'FMoIP',
      'country': '国家',
      'noStations': '选择国家以加载电台。',
      'play': '播放',
      'pause': '暂停',
      'startRecording': '录音',
      'stopRecording': '停止',
      'nowPlaying': '正在播放',
      'notPlaying': '未播放',
      'settings': '设置',
      'language': '语言',
      'dataSaver': '省流量',
      'recordingQuality': '录音质量',
      'recordingMode': '默认录音',
      'recordWithBackground': '录音时后台播放',
      'recordStreamOnly': '仅录制流（静音播放）',
      'recordBgShort': 'REC BG',
      'themeMode': '主题模式',
      'themeSystem': '系统',
      'themeDark': '深色',
      'themeLight': '浅色',
      'stationMetadata': '电台元数据',
      'stationName': '名称',
      'stationCountry': '国家',
      'stationFrequency': '频率',
      'stationLanguage': '语言',
      'stationTags': '标签',
      'stationBitrate': '比特率',
      'duration': '时长',
      'stationLink': '电台链接',
      'stationDate': '日期',
      'recordings': '录音',
      'noRecordings': '暂无录音。',
      'recordingsCount': '录音：{count}',
      'subscription': '订阅',
      'subscribed': '无广告',
      'notSubscribed': '免费',
      'subscribe': '订阅',
      'manage': '管理',
      'adPlaceholder': '广告',
      'loadMore': '加载更多',
      'searchStations': '搜索',
      'searchRecordings': '搜索',
      'editNameTitle': '编辑名称',
      'renameFileTitle': '重命名文件',
      'nameHint': '名称',
      'save': '保存',
      'deleteRecordingTitle': '删除录音？',
      'deleteRecordingBody': '该录音将被永久删除。',
      'cancel': '取消',
      'delete': '删除',
      'listPageSize': '列表行数',
      'low': '低',
      'medium': '中',
      'high': '高',
    },
  };

  static const Map<String, Map<String, String>> _countryNames = {
    'ar': {
      'US': 'الولايات المتحدة',
      'GB': 'المملكة المتحدة',
      'CA': 'كندا',
      'DE': 'ألمانيا',
      'AT': 'النمسا',
      'BE': 'بلجيكا',
      'BG': 'بلغاريا',
      'HR': 'كرواتيا',
      'CY': 'قبرص',
      'CZ': 'التشيك',
      'DK': 'الدنمارك',
      'EE': 'إستونيا',
      'FI': 'فنلندا',
      'FR': 'فرنسا',
      'GR': 'اليونان',
      'HU': 'المجر',
      'IE': 'أيرلندا',
      'IT': 'إيطاليا',
      'LV': 'لاتفيا',
      'LT': 'ليتوانيا',
      'LU': 'لوكسمبورغ',
      'MT': 'مالطا',
      'NL': 'هولندا',
      'PL': 'بولندا',
      'PT': 'البرتغال',
      'RO': 'رومانيا',
      'SK': 'سلوفاكيا',
      'SI': 'سلوفينيا',
      'ES': 'إسبانيا',
      'SE': 'السويد',
      'DZ': 'الجزائر',
      'BH': 'البحرين',
      'KM': 'جزر القمر',
      'DJ': 'جيبوتي',
      'EG': 'مصر',
      'IQ': 'العراق',
      'JO': 'الأردن',
      'KW': 'الكويت',
      'LB': 'لبنان',
      'LY': 'ليبيا',
      'MR': 'موريتانيا',
      'MA': 'المغرب',
      'OM': 'عُمان',
      'PS': 'فلسطين',
      'QA': 'قطر',
      'SA': 'السعودية',
      'SO': 'الصومال',
      'SD': 'السودان',
      'SY': 'سوريا',
      'TN': 'تونس',
      'AE': 'الإمارات',
      'YE': 'اليمن',
      'CN': 'الصين',
    },
    'es': {
      'US': 'Estados Unidos',
      'GB': 'Reino Unido',
      'CA': 'Canadá',
      'DE': 'Alemania',
      'AT': 'Austria',
      'BE': 'Bélgica',
      'BG': 'Bulgaria',
      'HR': 'Croacia',
      'CY': 'Chipre',
      'CZ': 'Chequia',
      'DK': 'Dinamarca',
      'EE': 'Estonia',
      'FI': 'Finlandia',
      'FR': 'Francia',
      'GR': 'Grecia',
      'HU': 'Hungría',
      'IE': 'Irlanda',
      'IT': 'Italia',
      'LV': 'Letonia',
      'LT': 'Lituania',
      'LU': 'Luxemburgo',
      'MT': 'Malta',
      'NL': 'Países Bajos',
      'PL': 'Polonia',
      'PT': 'Portugal',
      'RO': 'Rumanía',
      'SK': 'Eslovaquia',
      'SI': 'Eslovenia',
      'ES': 'España',
      'SE': 'Suecia',
      'EG': 'Egipto',
      'CN': 'China',
    },
    'zh': {
      'US': '美国',
      'GB': '英国',
      'CA': '加拿大',
      'DE': '德国',
      'AT': '奥地利',
      'BE': '比利时',
      'BG': '保加利亚',
      'HR': '克罗地亚',
      'CY': '塞浦路斯',
      'CZ': '捷克',
      'DK': '丹麦',
      'EE': '爱沙尼亚',
      'FI': '芬兰',
      'FR': '法国',
      'GR': '希腊',
      'HU': '匈牙利',
      'IE': '爱尔兰',
      'IT': '意大利',
      'LV': '拉脱维亚',
      'LT': '立陶宛',
      'LU': '卢森堡',
      'MT': '马耳他',
      'NL': '荷兰',
      'PL': '波兰',
      'PT': '葡萄牙',
      'RO': '罗马尼亚',
      'SK': '斯洛伐克',
      'SI': '斯洛文尼亚',
      'ES': '西班牙',
      'SE': '瑞典',
      'EG': '埃及',
      'CN': '中国',
    },
  };

  String _t(String key) => _localizedValues[locale.languageCode]?[key] ??
      _localizedValues['en']![key]!;

  String get appTitle => _t('appTitle');
  String get country => _t('country');
  String get noStations => _t('noStations');
  String get play => _t('play');
  String get pause => _t('pause');
  String get startRecording => _t('startRecording');
  String get stopRecording => _t('stopRecording');
  String get nowPlaying => _t('nowPlaying');
  String get notPlaying => _t('notPlaying');
  String get settings => _t('settings');
  String get language => _t('language');
  String get dataSaver => _t('dataSaver');
  String get recordingQuality => _t('recordingQuality');
  String get recordingMode => _t('recordingMode');
  String get recordWithBackground => _t('recordWithBackground');
  String get recordStreamOnly => _t('recordStreamOnly');
  String get recordBgShort => _t('recordBgShort');
  String get themeMode => _t('themeMode');
  String get themeSystem => _t('themeSystem');
  String get themeDark => _t('themeDark');
  String get themeLight => _t('themeLight');
  String get stationMetadata => _t('stationMetadata');
  String get stationName => _t('stationName');
  String get stationCountry => _t('stationCountry');
  String get stationFrequency => _t('stationFrequency');
  String get stationLanguage => _t('stationLanguage');
  String get stationTags => _t('stationTags');
  String get stationBitrate => _t('stationBitrate');
  String get duration => _t('duration');
  String get stationLink => _t('stationLink');
  String get stationDate => _t('stationDate');
  String get recordings => _t('recordings');
  String get noRecordings => _t('noRecordings');
  String recordingsCount(int count) =>
      _t('recordingsCount').replaceAll('{count}', count.toString());
  String get subscription => _t('subscription');
  String get subscribed => _t('subscribed');
  String get notSubscribed => _t('notSubscribed');
  String get subscribe => _t('subscribe');
  String get manage => _t('manage');
  String get adPlaceholder => _t('adPlaceholder');
  String get loadMore => _t('loadMore');
  String get searchStations => _t('searchStations');
  String get searchRecordings => _t('searchRecordings');
  String get editNameTitle => _t('editNameTitle');
  String get renameFileTitle => _t('renameFileTitle');
  String get nameHint => _t('nameHint');
  String get save => _t('save');
  String get deleteRecordingTitle => _t('deleteRecordingTitle');
  String get deleteRecordingBody => _t('deleteRecordingBody');
  String get cancel => _t('cancel');
  String get delete => _t('delete');
  String get listPageSize => _t('listPageSize');
  String get low => _t('low');
  String get medium => _t('medium');
  String get high => _t('high');

  String countryName(Country country) {
    return _countryNames[locale.languageCode]?[country.code] ?? country.name;
  }
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      AppLocalizations.supportedLocales.any((l) => l.languageCode == locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
