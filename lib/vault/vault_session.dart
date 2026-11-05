import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'media_server.dart';
import 'vault_keys.dart';
import 'vault_store.dart';

enum VaultState { loading, notSetUp, locked, unlocked }

class VaultThrottledException implements Exception {
  VaultThrottledException(this.remaining);
  final Duration remaining;
}

/// App-wide owner of the vault: unlocking, locking, biometrics, brute-force
/// throttling, auto-lock when the app is backgrounded, and screenshot
/// protection while the vault is open.
class VaultSession extends ChangeNotifier with WidgetsBindingObserver {
  VaultSession._();
  static final VaultSession instance = VaultSession._();

  static const minPasswordLength = 6;
  static const _failedKey = 'vault_failed_attempts';
  static const _lockoutKey = 'vault_lockout_until';
  static const _biometricKey = 'vault_dek_biometric';
  static const _freeAttempts = 5;

  static const _platform = MethodChannel('myfeed/platform');

  late VaultStore store;
  late VaultMediaServer mediaServer;
  late SharedPreferences _prefs;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final LocalAuthentication _localAuth = LocalAuthentication();

  VaultState _state = VaultState.loading;
  VaultState get state => _state;
  bool get isUnlocked => _state == VaultState.unlocked;

  /// Routes for locked content register here so they can be torn down on lock.
  final VaultRouteObserver routeObserver = VaultRouteObserver();

  int _busy = 0;
  bool _lockWhenIdle = false;
  bool _clearSecureOnResume = false;
  bool _biometricEnabled = false;
  bool get biometricEnabled => _biometricEnabled;


  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final support = await getApplicationSupportDirectory();
    store = VaultStore(Directory(p.join(support.path, 'vault')));
    mediaServer = VaultMediaServer(store);
    _biometricEnabled = await _secureStorage.containsKey(key: _biometricKey);
    _state = await store.exists() ? VaultState.locked : VaultState.notSetUp;
    WidgetsBinding.instance.addObserver(this);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Setup / unlock
  // ---------------------------------------------------------------------------

  static String? validateNewPassword(String password, String confirm) {
    if (password.length < minPasswordLength) {
      return 'Password must be at least $minPasswordLength characters';
    }
    if (password != confirm) return 'Passwords do not match';
    return null;
  }

  Future<void> setUp(String password, {bool enableBiometric = false}) async {
    await store.create(password);
    await _onUnlocked();
    await _resetThrottle();
    if (enableBiometric) await _storeBiometricKey();
  }

  Duration? get lockoutRemaining {
    final until = _prefs.getInt(_lockoutKey);
    if (until == null) return null;
    final remaining = DateTime.fromMillisecondsSinceEpoch(until).difference(DateTime.now());
    return remaining.isNegative ? null : remaining;
  }

  /// Throws [WrongPasswordException] or [VaultThrottledException].
  Future<void> unlockWithPassword(String password) async {
    final wait = lockoutRemaining;
    if (wait != null) throw VaultThrottledException(wait);
    try {
      await store.unlock(password);
    } on WrongPasswordException {
      final failed = (_prefs.getInt(_failedKey) ?? 0) + 1;
      await _prefs.setInt(_failedKey, failed);
      if (failed >= _freeAttempts) {
        final seconds = min(3600, 30 * pow(2, failed - _freeAttempts).toInt());
        await _prefs.setInt(
          _lockoutKey,
          DateTime.now().add(Duration(seconds: seconds)).millisecondsSinceEpoch,
        );
      }
      rethrow;
    }
    await _resetThrottle();
    await _onUnlocked();
  }

  Future<void> _resetThrottle() async {
    await _prefs.remove(_failedKey);
    await _prefs.remove(_lockoutKey);
  }

  Future<bool> isBiometricAvailable() async {
    try {
      return await _localAuth.isDeviceSupported() && await _localAuth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _authenticateBiometric(String reason) async {
    try {
      return await _localAuth.authenticate(localizedReason: reason, biometricOnly: true);
    } on LocalAuthException catch (e) {
      debugPrint('biometric auth failed: ${e.code}');
      return false;
    } on PlatformException catch (e) {
      debugPrint('biometric auth failed: $e');
      return false;
    }
  }

  Future<bool> unlockWithBiometric() async {
    if (!_biometricEnabled) return false;
    if (!await _authenticateBiometric('Unlock your locked gallery')) return false;
    final encoded = await _secureStorage.read(key: _biometricKey);
    if (encoded == null) {
      _biometricEnabled = false;
      notifyListeners();
      return false;
    }
    try {
      await store.unlockWithKey(SecretKey(base64Decode(encoded)));
    } catch (e) {
      // Stale key (e.g. vault was reset): disable biometrics.
      await _secureStorage.delete(key: _biometricKey);
      _biometricEnabled = false;
      notifyListeners();
      return false;
    }
    await _resetThrottle();
    await _onUnlocked();
    return true;
  }

  /// Biometric unlock keeps a copy of the vault key in Android Keystore-backed
  /// secure storage, released only after a successful biometric check.
  Future<bool> setBiometricEnabled(bool enabled) async {
    if (enabled) {
      if (!await _authenticateBiometric('Confirm to enable biometric unlock')) return false;
      await _storeBiometricKey();
    } else {
      await _secureStorage.delete(key: _biometricKey);
      _biometricEnabled = false;
    }
    notifyListeners();
    return true;
  }

  Future<void> _storeBiometricKey() async {
    final bytes = await store.dek.extractBytes();
    await _secureStorage.write(key: _biometricKey, value: base64Encode(Uint8List.fromList(bytes)));
    _biometricEnabled = true;
    notifyListeners();
  }

  Future<void> changePassword(String current, String next) => store.changePassword(current, next);

  Future<void> _onUnlocked() async {
    _state = VaultState.unlocked;
    _clearSecureOnResume = false;
    await _setSecure(true);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Locking
  // ---------------------------------------------------------------------------

  /// Runs [operation] while preventing an auto-lock from pulling the key out
  /// from under it; a lock requested meanwhile happens when it finishes.
  Future<T> guard<T>(Future<T> Function() operation) async {
    _busy++;
    try {
      return await operation();
    } finally {
      _busy--;
      if (_busy == 0 && _lockWhenIdle) {
        _lockWhenIdle = false;
        lock();
      }
    }
  }

  void lock() {
    if (_state != VaultState.unlocked) return;
    if (_busy > 0) {
      _lockWhenIdle = true;
      return;
    }
    store.lock();
    unawaited(mediaServer.stop());
    _state = VaultState.locked;
    // Drop decrypted pixels from the image cache.
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    routeObserver.removeVaultRoutes();
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _setSecure(false));
    } else {
      // Keep FLAG_SECURE until we're visible again so the recents snapshot
      // cannot capture vault content.
      _clearSecureOnResume = true;
    }
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      lock();
    } else if (state == AppLifecycleState.resumed && _clearSecureOnResume && !isUnlocked) {
      _clearSecureOnResume = false;
      _setSecure(false);
    }
  }

  /// Deletes the vault and everything in it.
  Future<void> resetVault() async {
    _busy = 0;
    _lockWhenIdle = false;
    lock();
    await store.wipe();
    await _secureStorage.delete(key: _biometricKey);
    _biometricEnabled = false;
    await _resetThrottle();
    _state = VaultState.notSetUp;
    notifyListeners();
  }

  /// Debug-only escape hatch for visual testing on an emulator
  /// (`--dart-define=MYFEED_ALLOW_SCREENSHOTS=true`). Ignored in release builds.
  static const _allowScreenshots = kDebugMode && bool.fromEnvironment('MYFEED_ALLOW_SCREENSHOTS');

  Future<void> _setSecure(bool secure) async {
    if (secure && _allowScreenshots) return;
    try {
      await _platform.invokeMethod('setSecure', secure);
    } on MissingPluginException {
      // Not on Android (tests).
    } catch (e) {
      debugPrint('setSecure failed: $e');
    }
  }
}

/// Tracks the navigator stack so every route showing vault content (named
/// with the `/vault` prefix) and anything above it can be removed on lock.
class VaultRouteObserver extends NavigatorObserver {
  final List<Route<dynamic>> _stack = [];

  static bool isVaultRoute(Route<dynamic> route) => route.settings.name?.startsWith('/vault') ?? false;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _stack.add(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _stack.remove(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _stack.remove(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _stack.indexOf(oldRoute);
    if (index >= 0 && newRoute != null) {
      _stack[index] = newRoute;
    } else if (newRoute != null) {
      _stack.add(newRoute);
    }
  }

  void removeVaultRoutes() {
    final nav = navigator;
    if (nav == null) return;
    final first = _stack.indexWhere(isVaultRoute);
    if (first < 0) return;
    for (final route in _stack.sublist(first).reversed.toList()) {
      if (route.isActive) nav.removeRoute(route);
    }
  }
}
