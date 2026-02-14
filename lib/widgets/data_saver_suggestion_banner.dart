import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../localization.dart';
import '../screens/settings_screen.dart';
import '../state/settings_state.dart';

/// Shown when user is on mobile data and Data saver is off.
class DataSaverSuggestionBanner extends StatefulWidget {
  const DataSaverSuggestionBanner({super.key});

  @override
  State<DataSaverSuggestionBanner> createState() =>
      _DataSaverSuggestionBannerState();
}

class _DataSaverSuggestionBannerState extends State<DataSaverSuggestionBanner> {
  bool _isOnMobileData = false;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
    Connectivity().onConnectivityChanged.listen((_) => _checkConnectivity());
  }

  Future<void> _checkConnectivity() async {
    try {
      final result = await Connectivity().checkConnectivity();
      final onMobile = result.contains(ConnectivityResult.mobile) &&
          !result.contains(ConnectivityResult.wifi);
      if (mounted && _isOnMobileData != onMobile) {
        setState(() => _isOnMobileData = onMobile);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsState>();
    final strings = AppLocalizations.of(context);

    if (_dismissed ||
        !_isOnMobileData ||
        settings.dataSaver ||
        !mounted) {
      return const SizedBox.shrink();
    }

    return Material(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: SafeArea(
        top: false,
        child: Dismissible(
          key: const Key('data_saver_suggestion'),
          direction: DismissDirection.up,
          onDismissed: (_) => setState(() => _dismissed = true),
          child: InkWell(
            onTap: () {
              setState(() => _dismissed = true);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const SettingsScreen(),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    Icons.data_usage,
                    size: 20,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      strings.dataSaverSuggestion,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
