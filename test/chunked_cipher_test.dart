import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myfeed/vault/chunked_cipher.dart';

Uint8List randomBytes(int n, [int seed = 1]) {
  final r = Random(seed);
  return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
}

void main() {
  final key = SecretKey(randomBytes(32, 7));
  const chunk = 64;
  final cipher = ChunkedCipher(chunkSize: chunk);
  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('cipher_test'));
  tearDown(() async => dir.delete(recursive: true));

  group('bytes round trip', () {
    for (final size in [0, 1, chunk - 1, chunk, chunk + 1, 3 * chunk + 5]) {
      test('size $size', () async {
        final plain = randomBytes(size, size);
        final enc = await cipher.encryptBytes(key, plain);
        expect(enc.length, ChunkedCipher.encryptedLength(size, chunk));
        expect(await cipher.decryptBytes(key, enc), plain);
      });
    }
  });

  test('same plaintext encrypts differently each time (fresh nonces)', () async {
    final plain = randomBytes(200);
    final a = await cipher.encryptBytes(key, plain);
    final b = await cipher.encryptBytes(key, plain);
    expect(a, isNot(equals(b)));
  });

  test('ciphertext does not contain the plaintext', () async {
    final plain = Uint8List.fromList(List.filled(300, 0x41));
    final enc = await cipher.encryptBytes(key, plain);
    final asString = String.fromCharCodes(enc);
    expect(asString.contains('AAAAAAAAAAAAAAAA'), isFalse);
  });

  test('wrong key is rejected', () async {
    final enc = await cipher.encryptBytes(key, randomBytes(100));
    expect(() => cipher.decryptBytes(SecretKey(randomBytes(32, 99)), enc), throwsA(isA<VaultCorruptedException>()));
  });

  test('any flipped bit is detected', () async {
    final enc = await cipher.encryptBytes(key, randomBytes(150));
    for (final position in [0, 5, 10, ChunkedCipher.headerLength + 3, enc.length - 1]) {
      final tampered = Uint8List.fromList(enc)..[position] ^= 0x01;
      await expectLater(cipher.decryptBytes(key, tampered), throwsA(isA<VaultCorruptedException>()),
          reason: 'byte $position');
    }
  });

  test('swapping chunks is detected', () async {
    final enc = await cipher.encryptBytes(key, randomBytes(chunk * 2));
    const h = ChunkedCipher.headerLength;
    const c = chunk + ChunkedCipher.overhead;
    final swapped = Uint8List.fromList(enc)
      ..setRange(h, h + c, enc.sublist(h + c, h + 2 * c))
      ..setRange(h + c, h + 2 * c, enc.sublist(h, h + c));
    expect(() => cipher.decryptBytes(key, swapped), throwsA(isA<VaultCorruptedException>()));
  });

  test('truncation is detected', () async {
    final enc = await cipher.encryptBytes(key, randomBytes(chunk * 2));
    final truncated = enc.sublist(0, enc.length - chunk - ChunkedCipher.overhead);
    expect(() => cipher.decryptBytes(key, truncated), throwsA(isA<VaultCorruptedException>()));
  });

  test('file encryption streams and supports random access', () async {
    final plain = randomBytes(chunk * 10 + 17, 3);
    final source = File('${dir.path}/plain.bin')..writeAsBytesSync(plain);
    final dest = File('${dir.path}/enc.mfv');
    final progress = <int>[];
    await cipher.encryptFile(key, source, dest, onProgress: (done, _) => progress.add(done));
    expect(progress.last, plain.length);
    expect(File('${dest.path}.part').existsSync(), isFalse);

    final reader = await cipher.openReader(key, dest);
    expect(reader.length, plain.length);
    expect(await reader.readAll(), plain);
    for (final (start, end) in [(0, 1), (63, 65), (100, 400), (plain.length - 5, plain.length), (10, 10)]) {
      final parts = await reader.read(start, end).toList();
      expect(parts.expand((p) => p).toList(), plain.sublist(start, end), reason: '$start-$end');
    }
    await reader.close();
  });

  test('a failed encryption leaves no partial output', () async {
    final dest = File('${dir.path}/enc.mfv');
    await expectLater(cipher.encryptFile(key, File('${dir.path}/missing'), dest), throwsA(isA<FileSystemException>()));
    expect(dest.existsSync(), isFalse);
    expect(File('${dest.path}.part').existsSync(), isFalse);
  });
}
