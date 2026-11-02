import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Thrown when an encrypted blob is malformed, truncated or was tampered with.
class VaultCorruptedException implements Exception {
  VaultCorruptedException(this.message);
  final String message;
  @override
  String toString() => 'VaultCorruptedException: $message';
}

/// Chunked AES-256-GCM container format.
///
/// Layout:
/// ```
/// header  = "MFV2" | version:u8 | chunkSize:u32be | plainLength:u64be   (17 bytes)
/// chunk_i = nonce:12 | ciphertext:min(chunkSize, remaining) | tag:16
/// ```
///
/// Every chunk uses a fresh random 96-bit nonce and authenticates
/// `header || chunkIndex:u64be` as associated data, so chunks cannot be
/// reordered, moved between files or truncated without detection, and the
/// header (including the length) cannot be altered.
///
/// Fixed-size chunks give O(1) random access, which lets videos be streamed
/// without decrypting the whole file or writing plaintext to disk.
class ChunkedCipher {
  ChunkedCipher({AesGcm? algorithm, this.chunkSize = defaultChunkSize})
      : algorithm = algorithm ?? Cryptography.instance.aesGcm(secretKeyLength: 32),
        assert(chunkSize > 0);

  static const int defaultChunkSize = 512 * 1024;
  static const List<int> magic = [0x4D, 0x46, 0x56, 0x32]; // "MFV2"
  static const int version = 1;
  static const int headerLength = 17;
  static const int nonceLength = 12;
  static const int tagLength = 16;
  static const int overhead = nonceLength + tagLength;

  final AesGcm algorithm;
  final int chunkSize;

  static Uint8List buildHeader(int chunkSize, int plainLength) {
    final header = ByteData(headerLength);
    for (var i = 0; i < 4; i++) {
      header.setUint8(i, magic[i]);
    }
    header.setUint8(4, version);
    header.setUint32(5, chunkSize);
    header.setUint64(9, plainLength);
    return header.buffer.asUint8List();
  }

  static Uint8List _aad(Uint8List header, int index) {
    final aad = Uint8List(headerLength + 8);
    aad.setRange(0, headerLength, header);
    ByteData.sublistView(aad).setUint64(headerLength, index);
    return aad;
  }

  static int chunkCount(int plainLength, int chunkSize) =>
      plainLength == 0 ? 0 : (plainLength + chunkSize - 1) ~/ chunkSize;

  static int encryptedLength(int plainLength, int chunkSize) =>
      headerLength + plainLength + chunkCount(plainLength, chunkSize) * overhead;

  Future<Uint8List> _encryptChunk(
    SecretKey key,
    Uint8List header,
    int index,
    List<int> plain,
  ) async {
    final box = await algorithm.encrypt(
      plain,
      secretKey: key,
      nonce: algorithm.newNonce(),
      aad: _aad(header, index),
    );
    final out = Uint8List(nonceLength + box.cipherText.length + tagLength);
    out.setRange(0, nonceLength, box.nonce);
    out.setRange(nonceLength, nonceLength + box.cipherText.length, box.cipherText);
    out.setRange(nonceLength + box.cipherText.length, out.length, box.mac.bytes);
    return out;
  }

  Future<List<int>> _decryptChunk(
    SecretKey key,
    Uint8List header,
    int index,
    Uint8List raw,
  ) async {
    if (raw.length < overhead) {
      throw VaultCorruptedException('chunk $index is truncated');
    }
    final box = SecretBox(
      Uint8List.sublistView(raw, nonceLength, raw.length - tagLength),
      nonce: Uint8List.sublistView(raw, 0, nonceLength),
      mac: Mac(Uint8List.sublistView(raw, raw.length - tagLength)),
    );
    try {
      return await algorithm.decrypt(box, secretKey: key, aad: _aad(header, index));
    } on SecretBoxAuthenticationError {
      throw VaultCorruptedException('chunk $index failed authentication');
    }
  }

  /// Encrypts an in-memory buffer (thumbnails, the index, small files).
  Future<Uint8List> encryptBytes(SecretKey key, Uint8List plain) async {
    final header = buildHeader(chunkSize, plain.length);
    final builder = BytesBuilder(copy: false)..add(header);
    final count = chunkCount(plain.length, chunkSize);
    for (var i = 0; i < count; i++) {
      final start = i * chunkSize;
      final end = min(start + chunkSize, plain.length);
      builder.add(await _encryptChunk(key, header, i, Uint8List.sublistView(plain, start, end)));
    }
    return builder.takeBytes();
  }

  /// Decrypts a buffer produced by [encryptBytes] (or a file produced by
  /// [encryptFile] that has been read into memory).
  Future<Uint8List> decryptBytes(SecretKey key, Uint8List data) async {
    final info = parseHeader(data);
    if (data.length != encryptedLength(info.plainLength, info.chunkSize)) {
      throw VaultCorruptedException('unexpected encrypted length');
    }
    final header = Uint8List.sublistView(data, 0, headerLength);
    final out = Uint8List(info.plainLength);
    final count = chunkCount(info.plainLength, info.chunkSize);
    var offset = headerLength;
    for (var i = 0; i < count; i++) {
      final plainLen = min(info.chunkSize, info.plainLength - i * info.chunkSize);
      final raw = Uint8List.sublistView(data, offset, offset + plainLen + overhead);
      out.setRange(i * info.chunkSize, i * info.chunkSize + plainLen,
          await _decryptChunk(key, header, i, raw));
      offset += plainLen + overhead;
    }
    return out;
  }

  /// Streams [source] into [destination] chunk by chunk, so memory use stays
  /// at roughly one chunk regardless of file size. The destination is written
  /// to a temporary `.part` file and renamed into place on success.
  Future<void> encryptFile(
    SecretKey key,
    File source,
    File destination, {
    void Function(int done, int total)? onProgress,
  }) async {
    final plainLength = await source.length();
    final header = buildHeader(chunkSize, plainLength);
    final part = File('${destination.path}.part');
    final input = await source.open();
    final output = await part.open(mode: FileMode.write);
    try {
      await output.writeFrom(header);
      final count = chunkCount(plainLength, chunkSize);
      for (var i = 0; i < count; i++) {
        final want = min(chunkSize, plainLength - i * chunkSize);
        final plain = await _readFully(input, want);
        if (plain.length != want) {
          throw FileSystemException('source changed while encrypting', source.path);
        }
        await output.writeFrom(await _encryptChunk(key, header, i, plain));
        onProgress?.call(i * chunkSize + want, plainLength);
      }
      await output.flush();
    } catch (_) {
      await output.close();
      await input.close();
      if (await part.exists()) await part.delete();
      rethrow;
    }
    await output.close();
    await input.close();
    await part.rename(destination.path);
  }

  static HeaderInfo parseHeader(Uint8List data) {
    if (data.length < headerLength) {
      throw VaultCorruptedException('missing header');
    }
    for (var i = 0; i < 4; i++) {
      if (data[i] != magic[i]) throw VaultCorruptedException('bad magic');
    }
    final view = ByteData.sublistView(data, 0, headerLength);
    if (view.getUint8(4) != version) {
      throw VaultCorruptedException('unsupported version ${view.getUint8(4)}');
    }
    final chunkSize = view.getUint32(5);
    if (chunkSize == 0) throw VaultCorruptedException('bad chunk size');
    return HeaderInfo(chunkSize, view.getUint64(9));
  }

  static Future<Uint8List> _readFully(RandomAccessFile file, int length) async {
    final buffer = Uint8List(length);
    var read = 0;
    while (read < length) {
      final n = await file.readInto(buffer, read, length);
      if (n == 0) break;
      read += n;
    }
    return read == length ? buffer : Uint8List.sublistView(buffer, 0, read);
  }

  /// Opens an encrypted file for random-access reads of its plaintext.
  Future<EncryptedFileReader> openReader(SecretKey key, File file) async {
    final raf = await file.open();
    try {
      final header = await _readFully(raf, headerLength);
      final info = parseHeader(header);
      final expected = encryptedLength(info.plainLength, info.chunkSize);
      if (await raf.length() != expected) {
        throw VaultCorruptedException('unexpected encrypted length');
      }
      return EncryptedFileReader._(this, key, raf, header, info);
    } catch (_) {
      await raf.close();
      rethrow;
    }
  }
}

class HeaderInfo {
  const HeaderInfo(this.chunkSize, this.plainLength);
  final int chunkSize;
  final int plainLength;
}

/// Random-access plaintext reader over a [ChunkedCipher] file.
class EncryptedFileReader {
  EncryptedFileReader._(this._cipher, this._key, this._raf, this._header, HeaderInfo info)
      : chunkSize = info.chunkSize,
        length = info.plainLength;

  final ChunkedCipher _cipher;
  final SecretKey _key;
  final RandomAccessFile _raf;
  final Uint8List _header;
  final int chunkSize;

  /// Plaintext length in bytes.
  final int length;

  int? _cachedIndex;
  List<int>? _cachedChunk;
  Future<void> _pending = Future.value();

  Future<List<int>> _chunk(int index) async {
    if (_cachedIndex == index) return _cachedChunk!;
    if (_closed) throw StateError('reader closed');
    final plainLen = min(chunkSize, length - index * chunkSize);
    final offset = ChunkedCipher.headerLength + index * (chunkSize + ChunkedCipher.overhead);
    // RandomAccessFile does not allow overlapping operations; serialise them.
    final previous = _pending;
    final done = previous.then((_) async {
      await _raf.setPosition(offset);
      return ChunkedCipher._readFully(_raf, plainLen + ChunkedCipher.overhead);
    });
    _pending = done.then((_) {}, onError: (_) {});
    final raw = await done;
    final plain = await _cipher._decryptChunk(_key, _header, index, raw);
    _cachedIndex = index;
    _cachedChunk = plain;
    return plain;
  }

  /// Yields plaintext bytes in `[start, end)` as a stream of chunk slices.
  Stream<List<int>> read(int start, int end) async* {
    if (start < 0 || end > length || start > end) {
      throw RangeError('invalid range $start-$end of $length');
    }
    var position = start;
    while (position < end) {
      final index = position ~/ chunkSize;
      final chunk = await _chunk(index);
      final chunkStart = index * chunkSize;
      final from = position - chunkStart;
      final to = min(chunk.length, end - chunkStart);
      yield chunk.sublist(from, to);
      position = chunkStart + to;
    }
  }

  Future<Uint8List> readAll() async {
    final builder = BytesBuilder(copy: false);
    await for (final part in read(0, length)) {
      builder.add(part);
    }
    return builder.takeBytes();
  }

  bool _closed = false;

  /// Closes the file once any in-flight read has finished (closing a
  /// RandomAccessFile with a pending operation throws). Safe to call twice.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _pending;
    await _raf.close();
  }
}
