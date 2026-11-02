import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'chunked_cipher.dart';
import 'models.dart';
import 'vault_keys.dart';

class VaultLockedException implements Exception {
  @override
  String toString() => 'The vault is locked';
}

/// Encrypted on-disk media vault.
///
/// ```
/// <root>/vault.json      key header (salt, KDF params, wrapped DEK) – no secrets in the clear
/// <root>/index.mfv       encrypted JSON index: item metadata and albums
/// <root>/media/<id>.mfv  encrypted media (ChunkedCipher format)
/// <root>/thumbs/<id>.mfv encrypted thumbnails
/// ```
class VaultStore extends ChangeNotifier {
  VaultStore(
    this.root, {
    ChunkedCipher? cipher,
    this.iterations = VaultKeyHeader.defaultIterations,
  }) : cipher = cipher ?? ChunkedCipher();

  final Directory root;
  final ChunkedCipher cipher;
  final int iterations;

  SecretKey? _dek;
  final List<LockedItem> _items = [];
  final List<LockedAlbum> _albums = [];
  Future<void> _writeQueue = Future.value();

  File get _headerFile => File(p.join(root.path, 'vault.json'));
  File get _indexFile => File(p.join(root.path, 'index.mfv'));
  Directory get _mediaDir => Directory(p.join(root.path, 'media'));
  Directory get _thumbDir => Directory(p.join(root.path, 'thumbs'));

  File mediaFile(String id) => File(p.join(_mediaDir.path, '$id.mfv'));
  File _thumbFile(String id) => File(p.join(_thumbDir.path, '$id.mfv'));

  bool get isUnlocked => _dek != null;

  SecretKey get dek => _dek ?? (throw VaultLockedException());

  Future<bool> exists() => _headerFile.exists();

  /// Items, newest first.
  List<LockedItem> get items => List.unmodifiable(_items);
  List<LockedAlbum> get albums => List.unmodifiable(_albums);

  LockedItem? itemById(String id) {
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  LockedAlbum? albumById(String id) {
    for (final album in _albums) {
      if (album.id == id) return album;
    }
    return null;
  }

  List<LockedItem> itemsOf(LockedAlbum album) =>
      album.itemIds.map(itemById).whereType<LockedItem>().toList();

  Set<String> get importedSourceIds =>
      _items.map((i) => i.sourceId).whereType<String>().toSet();

  static String newId() {
    final random = Random.secure();
    return List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  Future<void> create(String password) async {
    if (await exists()) throw StateError('vault already exists');
    await root.create(recursive: true);
    await _mediaDir.create();
    await _thumbDir.create();
    final (header, dek) = await VaultKeyHeader.create(password, iterations: iterations);
    _dek = dek;
    _items.clear();
    _albums.clear();
    await _writeIndex();
    await _atomicWrite(_headerFile, utf8.encode(jsonEncode(header.toJson())));
    notifyListeners();
  }

  Future<VaultKeyHeader> _readHeader() async =>
      VaultKeyHeader.fromJson(jsonDecode(await _headerFile.readAsString()) as Map<String, dynamic>);

  /// Throws [WrongPasswordException] on a bad password.
  Future<void> unlock(String password) async {
    final header = await _readHeader();
    await unlockWithKey(await header.unwrap(password));
  }

  Future<void> unlockWithKey(SecretKey key) async {
    final data = await _indexFile.readAsBytes();
    final plain = await cipher.decryptBytes(key, data); // authenticates the key
    final json = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
    _items
      ..clear()
      ..addAll((json['items'] as List).map((e) => LockedItem.fromJson(e as Map<String, dynamic>)));
    _albums
      ..clear()
      ..addAll((json['albums'] as List).map((e) => LockedAlbum.fromJson(e as Map<String, dynamic>)));
    _sortItems();
    _dek = key;
    notifyListeners();
  }

  /// Forgets the key and all decrypted metadata.
  void lock() {
    _dek = null;
    _items.clear();
    _albums.clear();
    notifyListeners();
  }

  /// Verifies [currentPassword] and re-wraps the existing key under
  /// [newPassword]. Media files do not need to be re-encrypted.
  Future<void> changePassword(String currentPassword, String newPassword) async {
    final header = await _readHeader();
    final key = await header.unwrap(currentPassword);
    final newHeader = await VaultKeyHeader.rewrap(key, newPassword, iterations: iterations);
    await _atomicWrite(_headerFile, utf8.encode(jsonEncode(newHeader.toJson())));
  }

  /// Irreversibly deletes the whole vault.
  Future<void> wipe() async {
    lock();
    if (await root.exists()) await root.delete(recursive: true);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Items
  // ---------------------------------------------------------------------------

  void _sortItems() => _items.sort((a, b) => b.addedAt.compareTo(a.addedAt));

  Future<LockedItem> importFile(
    File source, {
    required MediaKind kind,
    required String name,
    Uint8List? thumbnail,
    DateTime? createdAt,
    String? sourceId,
    int durationSeconds = 0,
    int width = 0,
    int height = 0,
    void Function(int done, int total)? onProgress,
  }) async {
    final key = dek;
    final id = newId();
    final destination = mediaFile(id);
    await _mediaDir.create(recursive: true);
    await cipher.encryptFile(key, source, destination, onProgress: onProgress);
    return _addItem(
      id: id,
      kind: kind,
      name: name,
      size: await source.length(),
      extension: p.extension(source.path).toLowerCase(),
      thumbnail: thumbnail,
      createdAt: createdAt,
      sourceId: sourceId,
      durationSeconds: durationSeconds,
      width: width,
      height: height,
    );
  }

  Future<LockedItem> importBytes(
    Uint8List plain, {
    required MediaKind kind,
    required String name,
    required String extension,
    Uint8List? thumbnail,
    DateTime? createdAt,
    String? sourceId,
  }) async {
    final key = dek;
    final id = newId();
    await _mediaDir.create(recursive: true);
    await _atomicWrite(mediaFile(id), await cipher.encryptBytes(key, plain));
    return _addItem(
      id: id,
      kind: kind,
      name: name,
      size: plain.length,
      extension: extension.toLowerCase(),
      thumbnail: thumbnail,
      createdAt: createdAt,
      sourceId: sourceId,
    );
  }

  Future<LockedItem> _addItem({
    required String id,
    required MediaKind kind,
    required String name,
    required int size,
    required String extension,
    Uint8List? thumbnail,
    DateTime? createdAt,
    String? sourceId,
    int durationSeconds = 0,
    int width = 0,
    int height = 0,
  }) async {
    if (thumbnail != null) {
      await _thumbDir.create(recursive: true);
      await _atomicWrite(_thumbFile(id), await cipher.encryptBytes(dek, thumbnail));
    }
    final item = LockedItem(
      id: id,
      kind: kind,
      extension: extension,
      name: name,
      size: size,
      addedAt: DateTime.now(),
      createdAt: createdAt,
      sourceId: sourceId,
      durationSeconds: durationSeconds,
      width: width,
      height: height,
      hasThumbnail: thumbnail != null,
    );
    _items.add(item);
    _sortItems();
    try {
      await _writeIndex();
    } catch (_) {
      _items.remove(item);
      await _deleteFiles(id);
      rethrow;
    }
    notifyListeners();
    return item;
  }

  Future<void> deleteItems(Iterable<String> ids) async {
    final remove = ids.toSet();
    if (remove.isEmpty) return;
    dek; // must be unlocked
    _items.removeWhere((i) => remove.contains(i.id));
    for (final album in _albums) {
      album.itemIds.removeWhere(remove.contains);
    }
    await _writeIndex();
    for (final id in remove) {
      await _deleteFiles(id);
    }
    notifyListeners();
  }

  Future<void> _deleteFiles(String id) async {
    for (final file in [mediaFile(id), _thumbFile(id)]) {
      if (await file.exists()) await file.delete();
    }
  }

  Future<Uint8List?> readThumbnail(String id) async {
    final file = _thumbFile(id);
    if (!await file.exists()) return null;
    return cipher.decryptBytes(dek, await file.readAsBytes());
  }

  Future<EncryptedFileReader> openReader(String id) => cipher.openReader(dek, mediaFile(id));

  Future<Uint8List> readAll(String id) async {
    final reader = await openReader(id);
    try {
      return await reader.readAll();
    } finally {
      await reader.close();
    }
  }

  /// Decrypts an item to [destination] (used only when exporting back to the
  /// public gallery, which needs a real file).
  Future<void> decryptToFile(String id, File destination) async {
    final reader = await openReader(id);
    final sink = destination.openWrite();
    try {
      await sink.addStream(reader.read(0, reader.length));
      await sink.flush();
    } finally {
      await sink.close();
      await reader.close();
    }
  }

  // ---------------------------------------------------------------------------
  // Albums
  // ---------------------------------------------------------------------------

  Future<LockedAlbum> createAlbum(String name) async {
    dek;
    final album = LockedAlbum(id: newId(), name: name.trim(), createdAt: DateTime.now());
    _albums.add(album);
    await _writeIndex();
    notifyListeners();
    return album;
  }

  Future<void> renameAlbum(String albumId, String name) async {
    albumById(albumId)?.name = name.trim();
    await _writeIndex();
    notifyListeners();
  }

  Future<void> deleteAlbum(String albumId) async {
    _albums.removeWhere((a) => a.id == albumId);
    await _writeIndex();
    notifyListeners();
  }

  Future<void> addToAlbum(String albumId, Iterable<String> itemIds) async {
    final album = albumById(albumId);
    if (album == null) return;
    for (final id in itemIds) {
      if (!album.itemIds.contains(id) && itemById(id) != null) album.itemIds.add(id);
    }
    await _writeIndex();
    notifyListeners();
  }

  Future<void> removeFromAlbum(String albumId, Iterable<String> itemIds) async {
    final remove = itemIds.toSet();
    albumById(albumId)?.itemIds.removeWhere(remove.contains);
    await _writeIndex();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  /// Serialises index writes so concurrent mutations never interleave.
  Future<void> _writeIndex() {
    final key = dek;
    final snapshot = utf8.encode(jsonEncode({
      'items': _items.map((e) => e.toJson()).toList(),
      'albums': _albums.map((e) => e.toJson()).toList(),
    }));
    final next = _writeQueue.then((_) async {
      await _atomicWrite(_indexFile, await cipher.encryptBytes(key, Uint8List.fromList(snapshot)));
    });
    _writeQueue = next.catchError((_) {});
    return next;
  }

  static Future<void> _atomicWrite(File file, List<int> bytes) async {
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(file.path);
  }
}
