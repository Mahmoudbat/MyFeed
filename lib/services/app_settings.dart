import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User preferences, loaded once at startup and observable so every screen
/// reacts immediately when a setting changes.
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  static const _verticalKey = 'scroll_direction_vertical';
  static const _removeOriginalsKey = 'delete_after_import';
  static const _deleteAfterExportKey = 'delete_after_export';

  SharedPreferences? _prefs;

  bool _verticalScrolling = true;
  bool _removeOriginalsAfterLocking = true;
  bool _deleteAfterExport = false;

  /// Swipe direction in the full-screen media viewer.
  bool get verticalScrolling => _verticalScrolling;

  /// Delete the gallery originals (with the system's confirmation) after they
  /// were encrypted into the locked gallery. Without this nothing is hidden.
  bool get removeOriginalsAfterLocking => _removeOriginalsAfterLocking;

  /// Remove items from the locked gallery after restoring them to the gallery.
  bool get deleteAfterExport => _deleteAfterExport;

  Future<void> load() async {
    final prefs = _prefs = await SharedPreferences.getInstance();
    _verticalScrolling = prefs.getBool(_verticalKey) ?? true;
    _removeOriginalsAfterLocking = prefs.getBool(_removeOriginalsKey) ?? true;
    _deleteAfterExport = prefs.getBool(_deleteAfterExportKey) ?? false;
    notifyListeners();
  }

  Future<void> _set(String key, bool value) async {
    notifyListeners();
    await _prefs?.setBool(key, value);
  }

  Future<void> setVerticalScrolling(bool value) {
    _verticalScrolling = value;
    return _set(_verticalKey, value);
  }

  Future<void> setRemoveOriginalsAfterLocking(bool value) {
    _removeOriginalsAfterLocking = value;
    return _set(_removeOriginalsKey, value);
  }

  Future<void> setDeleteAfterExport(bool value) {
    _deleteAfterExport = value;
    return _set(_deleteAfterExportKey, value);
  }
}
