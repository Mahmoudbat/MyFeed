import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import '../services/auth_service.dart';
import 'locked_gallery_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final AuthService _authService = AuthService();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  bool _isSettingUp = false;
  bool _isLoading = true;
  bool _biometricAvailable = false;
  bool _useBiometric = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void initState() {
    super.initState();
    _checkSetup();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _checkSetup() async {
    final isPasswordSet = await _authService.isPasswordSet();
    final biometricAvailable = await _authService.isBiometricAvailable();
    final useBiometric = await _authService.getUseBiometric();

    setState(() {
      _isSettingUp = !isPasswordSet;
      _biometricAvailable = biometricAvailable;
      _useBiometric = useBiometric;
      _isLoading = false;
    });

    // If password is already set and biometric is enabled, try biometric auth
    if (!_isSettingUp && _useBiometric && _biometricAvailable) {
      _authenticateWithBiometric();
    }
  }

  Future<void> _authenticateWithBiometric() async {
    try {
      final authenticated = await _authService.authenticateWithBiometric();
      if (authenticated && mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LockedGalleryScreen()),
        );
      } else if (!authenticated && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Biometric authentication failed. Use password instead.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Biometric error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _setupPassword() async {
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (password.isEmpty) {
      _showError('Please enter a password');
      return;
    }

    if (password.length < 4) {
      _showError('Password must be at least 4 characters');
      return;
    }

    if (password != confirmPassword) {
      _showError('Passwords do not match');
      return;
    }

    await _authService.setPassword(password);
    await _authService.setUseBiometric(_useBiometric);

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LockedGalleryScreen()),
      );
    }
  }

  Future<void> _authenticateWithPassword() async {
    final password = _passwordController.text;

    if (password.isEmpty) {
      _showError('Please enter your password');
      return;
    }

    final isCorrect = await _authService.verifyPassword(password);
    if (isCorrect && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LockedGalleryScreen()),
      );
    } else {
      _showError('Incorrect password');
      _passwordController.clear();
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(_isSettingUp ? 'Setup Locked Gallery' : 'Locked Gallery'),
        centerTitle: true,
        backgroundColor: Colors.black,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 40),
            const Icon(
              Icons.lock_outline,
              size: 80,
              color: Colors.white,
            ),
            const SizedBox(height: 32),
            Text(
              _isSettingUp ? 'Create a password to protect\nyour private gallery' : 'Enter your password',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Password',
                labelStyle: const TextStyle(color: Colors.white70),
                enabledBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white30),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white),
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility : Icons.visibility_off,
                    color: Colors.white70,
                  ),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),
            if (_isSettingUp) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _confirmPasswordController,
                obscureText: _obscureConfirmPassword,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Confirm Password',
                  labelStyle: const TextStyle(color: Colors.white70),
                  enabledBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white30),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white),
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirmPassword ? Icons.visibility : Icons.visibility_off,
                      color: Colors.white70,
                    ),
                    onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                  ),
                ),
              ),
            ],
            if (_isSettingUp && _biometricAvailable) ...[
              const SizedBox(height: 24),
              SwitchListTile(
                title: const Text(
                  'Enable biometric authentication',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Use fingerprint or face recognition',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                value: _useBiometric,
                onChanged: (value) => setState(() => _useBiometric = value),
                activeColor: Colors.blue,
              ),
            ],
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSettingUp ? _setupPassword : _authenticateWithPassword,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: Text(
                  _isSettingUp ? 'Create Password' : 'Unlock',
                  style: const TextStyle(fontSize: 16, color: Colors.white),
                ),
              ),
            ),
            if (!_isSettingUp && _biometricAvailable && _useBiometric) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: _authenticateWithBiometric,
                icon: const Icon(Icons.fingerprint, color: Colors.white70),
                label: const Text(
                  'Use biometric',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
