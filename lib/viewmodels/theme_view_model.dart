import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemePreference { system, light, dark }

abstract class ThemePreferenceStore {
  Future<AppThemePreference> load();

  Future<void> save(AppThemePreference preference);
}

class SharedPreferencesThemePreferenceStore implements ThemePreferenceStore {
  const SharedPreferencesThemePreferenceStore();

  static const _key = 'theme_preference';

  @override
  Future<AppThemePreference> load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_key);
    return AppThemePreference.values.byName(
      value ?? AppThemePreference.system.name,
    );
  }

  @override
  Future<void> save(AppThemePreference preference) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, preference.name);
  }
}

class ThemeViewModel extends ChangeNotifier {
  ThemeViewModel({
    AppThemePreference initialPreference = AppThemePreference.system,
    ThemePreferenceStore? preferenceStore,
  }) : _preference = initialPreference,
       _preferenceStore =
           preferenceStore ?? const SharedPreferencesThemePreferenceStore();

  final ThemePreferenceStore _preferenceStore;

  AppThemePreference _preference;
  bool _isInitialized = false;

  AppThemePreference get preference => _preference;

  bool get isInitialized => _isInitialized;

  ThemeMode get themeMode {
    switch (_preference) {
      case AppThemePreference.system:
        return ThemeMode.system;
      case AppThemePreference.light:
        return ThemeMode.light;
      case AppThemePreference.dark:
        return ThemeMode.dark;
    }
  }

  Future<void> initialize() async {
    _preference = await _preferenceStore.load();
    _isInitialized = true;
    notifyListeners();
  }

  Future<void> setPreference(AppThemePreference preference) async {
    if (_preference == preference && _isInitialized) {
      return;
    }
    _preference = preference;
    _isInitialized = true;
    notifyListeners();
    await _preferenceStore.save(preference);
  }

  String labelFor(AppThemePreference preference) {
    switch (preference) {
      case AppThemePreference.system:
        return 'System';
      case AppThemePreference.light:
        return 'Light';
      case AppThemePreference.dark:
        return 'Dark';
    }
  }
}
