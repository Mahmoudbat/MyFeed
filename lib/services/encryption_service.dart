import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;

class EncryptionService {
  static const String _keyPrefsKey = 'encryption_key';
  static const String _ivPrefsKey = 'encryption_iv';
  
  encrypt.Key? _key;
  encrypt.IV? _iv;
  encrypt.Encrypter? _encrypter;

  // Initialize or retrieve encryption keys
  // If password is provided, derive key from it
  Future<void> initialize({String? password}) async {
    final prefs = await SharedPreferences.getInstance();
    
    if (password != null && password.isNotEmpty) {
      // Derive key from password using SHA-256
      final passwordBytes = utf8.encode(password);
      final digest = sha256.convert(passwordBytes);
      _key = encrypt.Key(Uint8List.fromList(digest.bytes));
      
      // Use first 16 bytes of password hash as IV
      final ivDigest = sha256.convert(utf8.encode('iv_$password'));
      _iv = encrypt.IV(Uint8List.fromList(ivDigest.bytes.sublist(0, 16)));
      
      // Save for later use
      await prefs.setString(_keyPrefsKey, _key!.base64);
      await prefs.setString(_ivPrefsKey, _iv!.base64);
    } else {
      String? keyString = prefs.getString(_keyPrefsKey);
      String? ivString = prefs.getString(_ivPrefsKey);
      
      if (keyString == null || ivString == null) {
        // Generate new keys
        _key = encrypt.Key.fromSecureRandom(32);
        _iv = encrypt.IV.fromSecureRandom(16);
        
        // Save keys
        await prefs.setString(_keyPrefsKey, _key!.base64);
        await prefs.setString(_ivPrefsKey, _iv!.base64);
      } else {
        // Load existing keys
        _key = encrypt.Key.fromBase64(keyString);
        _iv = encrypt.IV.fromBase64(ivString);
      }
    }
    
    _encrypter = encrypt.Encrypter(encrypt.AES(_key!));
  }

  // Get the locked directory
  Future<Directory> getLockedDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final lockedDir = Directory(path.join(appDir.path, 'locked'));
    if (!await lockedDir.exists()) {
      await lockedDir.create(recursive: true);
    }
    return lockedDir;
  }

  // Encrypt and save a file to the locked directory
  Future<File> encryptFile(File sourceFile) async {
    if (_encrypter == null) await initialize();
    
    // Read the source file
    final bytes = await sourceFile.readAsBytes();
    
    // Encrypt the bytes
    final encrypted = _encrypter!.encryptBytes(bytes, iv: _iv!);
    
    // Generate a unique filename
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final extension = path.extension(sourceFile.path);
    final lockedDir = await getLockedDirectory();
    final encryptedFile = File(path.join(lockedDir.path, '$timestamp$extension.enc'));
    
    // Write encrypted data
    await encryptedFile.writeAsBytes(encrypted.bytes);
    
    // Save metadata (original extension)
    await _saveMetadata(encryptedFile.path, extension);
    
    return encryptedFile;
  }

  // Decrypt a file (in memory, for display)
  Future<Uint8List> decryptFile(File encryptedFile) async {
    if (_encrypter == null) await initialize();
    
    // Read encrypted bytes
    final encryptedBytes = await encryptedFile.readAsBytes();
    
    // Decrypt
    final decrypted = _encrypter!.decryptBytes(
      encrypt.Encrypted(encryptedBytes),
      iv: _iv!,
    );
    
    return Uint8List.fromList(decrypted);
  }

  // Save file metadata
  Future<void> _saveMetadata(String encryptedPath, String originalExtension) async {
    final prefs = await SharedPreferences.getInstance();
    final metadataKey = 'metadata_$encryptedPath';
    await prefs.setString(metadataKey, originalExtension);
  }

  // Get file metadata
  Future<String> getOriginalExtension(String encryptedPath) async {
    final prefs = await SharedPreferences.getInstance();
    final metadataKey = 'metadata_$encryptedPath';
    return prefs.getString(metadataKey) ?? '';
  }

  // List all encrypted files
  Future<List<File>> listEncryptedFiles() async {
    final lockedDir = await getLockedDirectory();
    if (!await lockedDir.exists()) return [];
    
    final entities = lockedDir.listSync();
    return entities.whereType<File>().toList();
  }

  // Delete an encrypted file
  Future<void> deleteEncryptedFile(File file) async {
    if (await file.exists()) {
      await file.delete();
      
      // Remove metadata
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('metadata_${file.path}');
    }
  }

  // Check if a file is a video based on metadata
  Future<bool> isVideo(File encryptedFile) async {
    final extension = await getOriginalExtension(encryptedFile.path);
    return extension.toLowerCase().contains('.mp4') ||
           extension.toLowerCase().contains('.mov') ||
           extension.toLowerCase().contains('.avi');
  }

  // Check if a file is an image based on metadata
  Future<bool> isImage(File encryptedFile) async {
    final extension = await getOriginalExtension(encryptedFile.path);
    return extension.toLowerCase().contains('.jpg') ||
           extension.toLowerCase().contains('.jpeg') ||
           extension.toLowerCase().contains('.png') ||
           extension.toLowerCase().contains('.gif');
  }
}
