import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';

/// Helper for Google Cast functionality (Chromecast).
/// Android/iOS: Native Cast SDK (device picker).
/// macOS: Opens stream in Chrome; user uses View > Cast to cast.
class CastHelper {
  static bool get isSupported =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  static bool _initialized = false;

  /// Initialize Google Cast. Call from main() before runApp.
  static Future<void> initialize() async {
    if (_initialized) return;
    if (Platform.isMacOS) {
      _initialized = true;
      return;
    }
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      const appId = GoogleCastDiscoveryCriteria.kDefaultApplicationId;
      GoogleCastOptions? options;
      if (Platform.isAndroid) {
        options = GoogleCastOptionsAndroid(
          appId: appId,
          stopCastingOnAppTerminated: true,
        );
      } else if (Platform.isIOS) {
        options = IOSGoogleCastOptions(
          GoogleCastDiscoveryCriteriaInitialize.initWithApplicationID(appId),
          stopCastingOnAppTerminated: true,
        );
      }
      if (options != null) {
        await GoogleCastContext.instance.setSharedInstanceWithOptions(options);
        _initialized = true;
      }
    } catch (e) {
      debugPrint('Cast initialization failed: $e');
    }
  }

  /// Show a bottom sheet to pick a Cast device and cast the given station.
  /// Uses displayStation if playing, otherwise selectedStation.
  /// On macOS: opens stream in Chrome; user uses View > Cast.
  static Future<void> showDevicePickerAndCast(
    BuildContext context, {
    required RadioStation? station,
    required String noSourceMessage,
    required String noDevicesMessage,
    required String castingToMessage,
    required String castSuccessMessage,
    required String castFailedMessage,
    String? castOpenInChromeMessage,
  }) async {
    if (!isSupported) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(noSourceMessage)),
        );
      }
      return;
    }
    if (station == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(noSourceMessage)),
        );
      }
      return;
    }

    if (Platform.isMacOS) {
      await _openStreamInChromeForCasting(
        context,
        station.streamUrl,
        castSuccessMessage: castOpenInChromeMessage ?? castSuccessMessage,
        castFailedMessage: castFailedMessage,
      );
      return;
    }

    if (!_initialized) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(noSourceMessage)),
        );
      }
      return;
    }
    await GoogleCastDiscoveryManager.instance.startDiscovery();
    await Future.delayed(const Duration(milliseconds: 1500));
    final devices = GoogleCastDiscoveryManager.instance.devices;
    if (!context.mounted) return;
    GoogleCastDiscoveryManager.instance.stopDiscovery();
    if (devices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(noDevicesMessage)),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                castingToMessage,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            ...devices.map(
              (device) => ListTile(
                leading: const Icon(Icons.cast),
                title: Text(device.friendlyName),
                subtitle: device.modelName != null
                    ? Text(device.modelName!)
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  _castToDevice(
                    device,
                    station,
                    context,
                    castSuccessMessage,
                    castFailedMessage,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _castToDevice(
    GoogleCastDevice device,
    RadioStation station,
    BuildContext context,
    String castSuccessMessage,
    String castFailedMessage,
  ) async {
    try {
      await GoogleCastSessionManager.instance.startSessionWithDevice(device);
      if (!context.mounted) return;
      final contentType = _guessContentType(station.streamUrl);
      final mediaInfo = GoogleCastMediaInformation(
        contentId: station.streamUrl,
        contentUrl: Uri.parse(station.streamUrl),
        streamType: CastMediaStreamType.live,
        contentType: contentType,
        metadata: GoogleCastGenericMediaMetadata(
          title: station.name,
          subtitle: '${station.frequency} • ${station.country}',
        ),
      );
      await GoogleCastRemoteMediaClient.instance.loadMedia(mediaInfo);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(castSuccessMessage)),
        );
      }
    } catch (e) {
      debugPrint('Cast failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(castFailedMessage)),
        );
      }
    }
  }

  static String _guessContentType(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('.aac') || lower.contains('aac')) return 'audio/aac';
    if (lower.contains('.m3u8') || lower.contains('m3u8')) return 'application/x-mpegURL';
    return 'audio/mpeg';
  }

  /// macOS: Open the stream URL in Chrome. User can then use View > Cast.
  static Future<void> _openStreamInChromeForCasting(
    BuildContext context,
    String streamUrl, {
    required String castSuccessMessage,
    required String castFailedMessage,
  }) async {
    try {
      final uri = Uri.parse(streamUrl);
      bool opened = false;

      // Try to open in Chrome first (best for casting)
      final result = await Process.run(
        'open',
        ['-a', 'Google Chrome', streamUrl],
        runInShell: false,
      );
      if (result.exitCode == 0) {
        opened = true;
      }

      // Fallback: open in default browser
      if (!opened) {
        opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(opened ? castSuccessMessage : castFailedMessage),
          ),
        );
      }
    } catch (e) {
      debugPrint('macOS cast (open in Chrome) failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(castFailedMessage)),
        );
      }
    }
  }
}
