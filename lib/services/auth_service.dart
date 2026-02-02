import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

class AuthService {
  final LocalAuthentication _localAuth = LocalAuthentication();
  static const String _passwordKey = 'locked_gallery_password';
  static const String _useBiometricKey = 'use_biometric';

  // Check if biometric is available
  Future<bool> isBiometricAvailable() async {
    try {
      final canCheckBiometrics = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      return canCheckBiometrics && isDeviceSupported;
    } catch (e) {
      return false;
    }
  }

  // Get available biometrics
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (e) {
      return [];
    }
  }

  // Authenticate with biometric
  Future<bool> authenticateWithBiometric() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: 'Authenticate to access locked gallery',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
    } on PlatformException catch (e) {
      print('Biometric authentication error: $e');
      return false;
    }
  }

  // Set password
  Future<void> setPassword(String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_passwordKey, password);
  }

  // Check if password is set
  Future<bool> isPasswordSet() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_passwordKey) != null;
  }

  // Verify password
  Future<bool> verifyPassword(String password) async {
    final prefs = await SharedPreferences.getInstance();
    final storedPassword = prefs.getString(_passwordKey);
    return storedPassword == password;
  }

  // Set biometric preference
  Future<void> setUseBiometric(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_useBiometricKey, value);
  }

  // Get biometric preference
  Future<bool> getUseBiometric() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_useBiometricKey) ?? false;
  }

  // Authenticate (biometric or password)
  Future<bool> authenticate() async {
    final useBiometric = await getUseBiometric();
    
    if (useBiometric) {
      final biometricAvailable = await isBiometricAvailable();
      if (biometricAvailable) {
        return await authenticateWithBiometric();
      }
    }
    
    // Fallback to password
    return false; // Will be handled by password dialog
  }

  // Clear all authentication data
  Future<void> clearAuth() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_passwordKey);
    await prefs.remove(_useBiometricKey);
  }
}
