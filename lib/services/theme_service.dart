import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/storage/local_database.dart';

class ThemeService extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.light;
  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;

  Future<void> load() async {
    final stored = LocalDatabase.settingsBox.get(AppConstants.settingsThemeKey);
    if (stored == 'dark') {
      _mode = ThemeMode.dark;
    } else {
      _mode = ThemeMode.light;
    }
    notifyListeners();
  }

  Future<void> toggle() async {
    _mode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    await LocalDatabase.settingsBox.put(
      AppConstants.settingsThemeKey,
      _mode == ThemeMode.dark ? 'dark' : 'light',
    );
    notifyListeners();
  }
}
