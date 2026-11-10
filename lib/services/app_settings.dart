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
  static const _vaultAutoLockKey = 'vault_auto_lock_seconds';
  static const defaultVaultAutoLockSeconds = 15;
  static const vaultAutoLockOff = -1;
  static const vaultAutoLockImmediate = 0;

  SharedPreferences? _prefs;

  bool _verticalScrolling = true;
  bool _removeOriginalsAfterLocking = true;
  bool _deleteAfterExport = false;
  int _vaultAutoLockSeconds = defaultVaultAutoLockSeconds;

  /// Background grace period: -1 disables auto-lock, 0 locks immediately.
  int get vaultAutoLockSeconds => _vaultAutoLockSeconds;

  Duration? get vaultAutoLockDelay => _vaultAutoLockSeconds == vaultAutoLockOff
      ? null
      : Duration(seconds: _vaultAutoLockSeconds);

  String get vaultAutoLockDescription => switch (_vaultAutoLockSeconds) {
        vaultAutoLockOff => 'Off — lock manually when you are done',
        vaultAutoLockImmediate => 'Lock immediately after leaving the app',
        _ => 'Lock $_vaultAutoLockSeconds seconds after leaving the app',
      };

  static bool isValidVaultAutoLockSeconds(int seconds) =>
      seconds == vaultAutoLockOff ||
      (seconds >= 0 && seconds < 60 && seconds % 5 == 0);

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
    final seconds = prefs.getInt(_vaultAutoLockKey);
    _vaultAutoLockSeconds =
        seconds != null && isValidVaultAutoLockSeconds(seconds)
            ? seconds
            : defaultVaultAutoLockSeconds;
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

  Future<void> setVaultAutoLockSeconds(int seconds) async {
    if (!isValidVaultAutoLockSeconds(seconds)) {
      throw ArgumentError.value(seconds, 'seconds',
          'Must be -1 (off), 0 (immediately), or 5–55 in steps of 5');
    }
    _vaultAutoLockSeconds = seconds;
    notifyListeners();
    await _prefs?.setInt(_vaultAutoLockKey, seconds);
  }
}
