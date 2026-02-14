import 'package:flutter/material.dart';

import 'localization.dart';

String themeModeLabel(ThemeMode mode, AppLocalizations strings) {
  switch (mode) {
    case ThemeMode.system:
      return strings.themeSystem;
    case ThemeMode.dark:
      return strings.themeDark;
    case ThemeMode.light:
      return strings.themeLight;
  }
}

String formatRecordingTime(DateTime dateTime) {
  final local = dateTime.toLocal();
  final yyyy = local.year.toString().padLeft(4, '0');
  final mm = local.month.toString().padLeft(2, '0');
  final dd = local.day.toString().padLeft(2, '0');
  final hh = local.hour.toString().padLeft(2, '0');
  final min = local.minute.toString().padLeft(2, '0');
  return '$yyyy-$mm-$dd $hh:$min';
}

String formatDuration(Duration duration) {
  final totalSeconds = duration.inSeconds.clamp(0, 24 * 60 * 60);
  final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

String formatDurationProgress(Duration position, Duration? total) {
  if (total == null || total.inSeconds <= 0) {
    return formatDuration(position);
  }
  return '${formatDuration(position)} / ${formatDuration(total)}';
}
