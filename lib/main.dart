import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:provider/provider.dart';

import 'ads/ad_consnt.dart';
import 'ads/app_lifecycle_reactor.dart';
import 'ads/app_open_ad_manager.dart';
import 'cast/cast_helper.dart';
import 'localization.dart';
import 'models.dart';
import 'state/player_state.dart';
import 'state/radio_state.dart';
import 'state/recording_state.dart';
import 'state/settings_state.dart';
import 'state/subscription_state.dart';
import 'utils.dart';
import 'screens/about_screen.dart';
import 'screens/send_feedback_screen.dart';
import 'screens/settings_screen.dart';
import 'widgets/ad_banner.dart';
import 'widgets/home_auto_off_banner.dart';
import 'widgets/home_lcd_section.dart';
import 'widgets/home_main_content.dart';
import 'widgets/lcd_panel.dart';

final _appOpenAdManager = AppOpenAdManager();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Country.loadDefaults(); // Load country codes from JSON
  // Skip AdMob on macOS (not supported)
  if (!Platform.isMacOS) {
    try {
      await AdConsentHelper.ensureConsent();
      await MobileAds.instance.initialize();
      _appOpenAdManager.loadAd();
    } catch (e) {
      debugPrint('AdMob initialization failed: $e');
    }
  }
  // JustAudioBackground is Android-specific, skip on macOS
  if (!Platform.isMacOS) {
    try {
      await JustAudioBackground.init(
        androidNotificationChannelId: 'com.fmoip.audio',
        androidNotificationChannelName: 'FMoIP Playback',
        androidNotificationOngoing: true,
      );
    } catch (e) {
      debugPrint('JustAudioBackground init failed: $e');
    }
  }
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
  await CastHelper.initialize();
  runApp(const FmoipApp());
}

/// Starts the app open ad lifecycle reactor when the app is ready.
class _AppOpenBootstrap extends StatefulWidget {
  const _AppOpenBootstrap({required this.child});

  final Widget child;

  @override
  State<_AppOpenBootstrap> createState() => _AppOpenBootstrapState();
}

class _AppOpenBootstrapState extends State<_AppOpenBootstrap> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final radioState = context.read<RadioState>();
      // Order: 1) select country (restore or location), 2) stations load, 3) combo counts
      await radioState.ensureInitialized();
      await radioState.ensureAutoCountrySelected();
      if (!mounted) return;
      if (!context.read<SettingsState>().dataSaver) {
        radioState.prefetchCountryCountsForDropdown();
      }
      final reactor = AppLifecycleReactor(
        appOpenAdManager: _appOpenAdManager,
        shouldShowAd: () =>
            !context.read<SubscriptionState>().isPro && !Platform.isMacOS,
        onAdShown: () {
          if (!context.read<SettingsState>().dataSaver) {
            context.read<RadioState>().prefetchCountryCountsForDropdown();
          }
        },
      );
      reactor.listenToAppStateChanges();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class FmoipApp extends StatelessWidget {
  const FmoipApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsState()),
        ChangeNotifierProvider(create: (_) => RadioState()),
        ChangeNotifierProvider(create: (_) => AppPlayerState()),
        ChangeNotifierProvider(create: (_) => RecordingState()),
        ChangeNotifierProvider(create: (_) => SubscriptionState()),
      ],
      child: _AppOpenBootstrap(
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
  Timer? _autoOffTimer;
  DateTime? _autoOffStartedAt;
  int _autoOffMinutesWhenStarted = 0;
  late final TextEditingController _stationSearchController;
  late final TextEditingController _recordingSearchController;
  late final ScrollController _stationListController;
  late final ScrollController _recordingsListController;
  late final TabController _tabController;
  String _stationSearchQuery = '';
  String _recordingSearchQuery = '';
  int? _lastListPageSize;
  bool? _lastDataSaver;
  int? _lastMaxRecordingMinutes;
  bool _autoOffListenersAdded = false;
  DateTime? _lastBackPressTime;

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
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_syncTabToRecordings);
    _lcdTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  void _syncTabToRecordings() {
    if (!mounted) return;
    final recorder = context.read<RecordingState>();
    final showRec = _tabController.index == 1;
    recorder.setShowRecordingsList(showRec);
  }

  void _updateAutoOffTimer() {
    if (!mounted) return;
    final player = context.read<AppPlayerState>();
    final settings = context.read<SettingsState>();
    _autoOffTimer?.cancel();
    _autoOffTimer = null;
    if (player.isPlaying && settings.autoOffMinutes > 0) {
      final remaining = _autoOffRemaining;
      if (_autoOffStartedAt == null || remaining == null || remaining <= Duration.zero) {
        _autoOffStartedAt = DateTime.now();
        _autoOffMinutesWhenStarted = settings.autoOffMinutes;
      }
      final duration = _autoOffRemaining ?? Duration(minutes: settings.autoOffMinutes);
      _autoOffTimer = Timer(
        duration,
        () async {
          if (!mounted) return;
          final p = context.read<AppPlayerState>();
          final r = context.read<RecordingState>();
          if (p.isPlaying) {
            if (r.isRecording) {
              await r.stopRecording();
            } else if (r.isVoiceRecording) {
              await r.stopVoiceRecording();
            }
            await p.pause();
          }
          await AudioService.stop();
          _autoOffTimer = null;
          _autoOffStartedAt = null;
          SystemNavigator.pop();
        },
      );
    } else if (settings.autoOffMinutes == 0) {
      _autoOffStartedAt = null;
    }
  }

  double _bottomBannerHeight(bool showAutoOff, bool showAd) {
    var h = 0.0;
    if (showAd) h += AdSize.banner.height.toDouble();
    if (showAutoOff) h += 44; // HomeAutoOffBanner approximate height
    return h;
  }

  Duration? get _autoOffRemaining {
    if (_autoOffStartedAt == null || _autoOffMinutesWhenStarted <= 0) return null;
    final end = _autoOffStartedAt!.add(Duration(minutes: _autoOffMinutesWhenStarted));
    final remaining = end.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  @override
  void dispose() {
    _autoOffTimer?.cancel();
    if (_autoOffListenersAdded) {
      context.read<AppPlayerState>().removeListener(_updateAutoOffTimer);
      context.read<SettingsState>().removeListener(_updateAutoOffTimer);
    }
    _blinkController.dispose();
    _recordingsBlinkController.dispose();
    _voiceBlinkController.dispose();
    _lcdTimer?.cancel();
    _stationSearchController.dispose();
    _recordingSearchController.dispose();
    _stationListController.dispose();
    _recordingsListController.dispose();
    _tabController.removeListener(_syncTabToRecordings);
    _tabController.dispose();
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
      if (_lastMaxRecordingMinutes != settings.maxRecordingMinutes) {
        _lastMaxRecordingMinutes = settings.maxRecordingMinutes;
        recorder.setMaxRecordingMinutes(settings.maxRecordingMinutes);
      }
      if (!_autoOffListenersAdded) {
        _autoOffListenersAdded = true;
        context.read<AppPlayerState>().addListener(_updateAutoOffTimer);
        context.read<SettingsState>().addListener(_updateAutoOffTimer);
        _updateAutoOffTimer();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      final player = context.read<AppPlayerState>();
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
    final recorder = context.watch<RecordingState>();
    final player = context.watch<AppPlayerState>();
    final selectedStation = radioState.selectedStation ?? player.currentStation;
    // When something is playing, LCD and "current" stay on the playing station (don't follow list selection).
    final displayStation = (player.isPlaying && player.currentStation != null)
        ? player.currentStation!
        : (radioState.selectedStation ?? player.currentStation);
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
    final isPowerOn = player.isPlaying && player.currentStation != null;
    final canRecord = selectedStation != null && isPowerOn;
    final canControlRecording = player.currentRecordingPath != null;

    final lcdFrequency = isRecordingPlayback
        ? formatDurationProgress(playbackPosition, playbackDuration)
        : (isLiveRecording
            ? formatDuration(liveDuration)
                : (isRecordingsView
                ? ''
                : (isPowerOn && displayStation != null
                    ? (displayStation!.frequency.trim().isNotEmpty
                        ? displayStation!.frequency
                        : '') // Empty string instead of "--" to avoid double dash
                    : ''))); // Empty string instead of "--" to avoid double dash
    final lcdName = isRecordingPlayback
        ? '${currentRecording.name} • ${currentRecording.stationName}'.trim()
        : (isLiveRecording
            ? (recorder.isVoiceRecording ? 'Voice note' : 'Recording')
            : (isRecordingsView
                ? strings.recordings
                : (isPowerOn && displayStation != null ? displayStation!.name : strings.lcdIdle)));
    final lcdCountry = isRecordingPlayback
        ? strings.recordings
        : (isLiveRecording
            ? ''
            : (isRecordingsView ? '' : (isPowerOn && displayStation != null ? strings.countryDisplayName(displayStation!.country) : '')));
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
                : (isPowerOn && displayStation != null ? displayStation!.language : '')));

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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final now = DateTime.now();
        if (_lastBackPressTime == null ||
            now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
          _lastBackPressTime = now;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(strings.tapAgainToLeave)),
          );
        } else {
          exit(0);
        }
      },
      child: Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        toolbarHeight: 44,
        title: Text(strings.appTitle),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.menu),
            onSelected: (value) {
              if (value == 'settings') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SettingsScreen(),
                  ),
                );
              } else if (value == 'recordings') {
                _tabController.animateTo(1);
              } else if (value == 'about') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AboutScreen(),
                  ),
                );
              } else if (value == 'feedback') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SendFeedbackScreen(),
                  ),
                );
              } else if (value == 'exit') {
                exit(0);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'settings',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.settings, size: 20),
                    const SizedBox(width: 12),
                    Text(strings.settings),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'recordings',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.folder_outlined, size: 20),
                    const SizedBox(width: 12),
                    Text(strings.recordings),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'feedback',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.feedback_outlined, size: 20),
                    const SizedBox(width: 12),
                    Text(strings.sendFeedback),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'about',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.info_outline, size: 20),
                    const SizedBox(width: 12),
                    Text(strings.aboutTitle),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'exit',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.exit_to_app, size: 20),
                    const SizedBox(width: 12),
                    Text(strings.exit),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final lcdData = LcdDisplayData(
                    name: lcdName,
                    frequency: lcdFrequency,
                    country: lcdCountry,
                    language: lcdLanguage,
                    isRecordingPlayback: isRecordingPlayback,
                    sessionDataMb: player.sessionDataMb,
                  );
                  final lcdSection = HomeLcdSection(
                    lcdData: lcdData,
                    strings: strings,
                    selectedStation: selectedStation,
                    displayStation: displayStation,
                    currentRecording: currentRecording,
                    canRecord: canRecord,
                    canControlRecording: canControlRecording,
                    isPowerOn: isPowerOn,
                    blinkController: _blinkController,
                    recordingsBlinkController: _recordingsBlinkController,
                    voiceBlinkController: _voiceBlinkController,
                    tabController: _tabController,
                    stationSearchController: _stationSearchController,
                    recordingSearchController: _recordingSearchController,
                  );
                  final showAutoOff =
                      _autoOffRemaining != null &&
                      _autoOffRemaining!.inSeconds > 0;
                  final subscription = context.watch<SubscriptionState>();
                  final showAd = !subscription.isPro && !Platform.isMacOS;
                  return HomeMainContent(
                    constraints: constraints,
                    lcdSection: lcdSection,
                    strings: strings,
                    tabController: _tabController,
                    stationSearchQuery: _stationSearchQuery,
                    recordingSearchQuery: _recordingSearchQuery,
                    stationListController: _stationListController,
                    recordingsListController: _recordingsListController,
                    listPaddingBottom: _bottomBannerHeight(showAutoOff, showAd),
                  );
                },
              ),
            ),
            Builder(
              builder: (context) {
                final radioState = context.watch<RadioState>();
                final subscription = context.watch<SubscriptionState>();
                final showAd = !subscription.isPro && !Platform.isMacOS;
                final showAutoOff = _autoOffRemaining != null &&
                    _autoOffRemaining!.inSeconds > 0;
                final showPrefetch =
                    radioState.isPrefetchingCountryCounts;
                if (!showAd && !showAutoOff && !showPrefetch) {
                  return const SizedBox.shrink();
                }
                return SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showPrefetch)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              LinearProgressIndicator(
                                value: radioState.prefetchProgress > 0
                                    ? radioState.prefetchProgress
                                    : null,
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHigh,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                strings.updatingStationsInfo,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      if (showAd) const AdBanner(),
                      if (showAutoOff)
                        HomeAutoOffBanner(
                          remaining: _autoOffRemaining!,
                          formattedText: strings.autoOffCountdown(
                            formatDuration(_autoOffRemaining!),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    ),
    );
  }
}

