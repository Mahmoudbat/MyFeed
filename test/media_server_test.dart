import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:myfeed/vault/chunked_cipher.dart';
import 'package:myfeed/vault/media_server.dart';
import 'package:myfeed/vault/models.dart';
import 'package:myfeed/vault/vault_store.dart';

void main() {
  group('range parsing', () {
    test('cases', () {
      expect(VaultMediaServer.parseRange(null, 100), isNull);
      expect(VaultMediaServer.parseRange('bytes=0-', 100), const RangeResult(0, 100));
      expect(VaultMediaServer.parseRange('bytes=10-19', 100), const RangeResult(10, 20));
      expect(VaultMediaServer.parseRange('bytes=90-500', 100), const RangeResult(90, 100));
      expect(VaultMediaServer.parseRange('bytes=-10', 100), const RangeResult(90, 100));
      expect(VaultMediaServer.parseRange('bytes=-500', 100), const RangeResult(0, 100));
      expect(VaultMediaServer.parseRange('bytes=100-', 100), RangeResult.unsatisfiable);
      expect(VaultMediaServer.parseRange('bytes=5-2', 100), RangeResult.unsatisfiable);
      expect(VaultMediaServer.parseRange('bytes=0-1,5-6', 100), isNull);
    });
  });

  group('server', () {
    late Directory dir;
    late VaultStore store;
    late VaultMediaServer server;
    late Uint8List plain;
    late LockedItem item;
    final client = HttpClient();

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('server_test');
      store = VaultStore(Directory('${dir.path}/vault'), iterations: 1000, cipher: ChunkedCipher(chunkSize: 1000));
      await store.create('pw123456');
      plain = Uint8List.fromList(List.generate(10500, (i) => (i * 7) % 256));
      final file = File('${dir.path}/clip.mp4')..writeAsBytesSync(plain);
      item = await store.importFile(file, kind: MediaKind.video, name: 'clip.mp4');
      server = VaultMediaServer(store);
      await server.start();
    });

    tearDown(() async {
      await server.stop();
      await dir.delete(recursive: true);
    });

    Future<(int, List<int>, HttpHeaders)> get(Uri uri, {String? range}) async {
      final request = await client.getUrl(uri);
      if (range != null) request.headers.set(HttpHeaders.rangeHeader, range);
      final response = await request.close();
      final body = await response.fold<List<int>>([], (a, b) => a..addAll(b));
      return (response.statusCode, body, response.headers);
    }

    test('serves the full decrypted file', () async {
      final (status, body, headers) = await get(server.urlFor(item.id));
      expect(status, 200);
      expect(body, plain);
      expect(headers.contentType?.mimeType, 'video/mp4');
      expect(headers.value(HttpHeaders.acceptRangesHeader), 'bytes');
    });

    test('serves byte ranges across chunk boundaries', () async {
      final (status, body, headers) = await get(server.urlFor(item.id), range: 'bytes=995-3004');
      expect(status, 206);
      expect(body, plain.sublist(995, 3005));
      expect(headers.value(HttpHeaders.contentRangeHeader), 'bytes 995-3004/10500');
    });

    test('rejects unsatisfiable ranges', () async {
      final (status, _, headers) = await get(server.urlFor(item.id), range: 'bytes=20000-');
      expect(status, 416);
      expect(headers.value(HttpHeaders.contentRangeHeader), 'bytes */10500');
    });

    test('rejects requests without the token', () async {
      final url = server.urlFor(item.id);
      final noToken = url.replace(pathSegments: ['wrong-token', url.pathSegments.last]);
      expect((await get(noToken)).$1, 404);
    });

    test('nothing is served once the vault is locked', () async {
      final url = server.urlFor(item.id);
      store.lock();
      expect((await get(url)).$1, 404);
    });

    test('client disconnecting mid-stream (as players do when seeking) is handled', () async {
      // Bigger file so the response cannot be buffered in one go.
      final big = File('${dir.path}/big.mp4')..writeAsBytesSync(List.generate(3 * 1024 * 1024, (i) => i % 256));
      final bigItem = await store.importFile(big, kind: MediaKind.video, name: 'big.mp4');
      for (var i = 0; i < 5; i++) {
        final request = await client.getUrl(server.urlFor(bigItem.id));
        final response = await request.close();
        final sub = response.listen(null);
        await Future<void>.delayed(const Duration(milliseconds: 5));
        await sub.cancel(); // abort the download
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
      // Server still healthy and serving correct data.
      final (status, body, _) = await get(server.urlFor(item.id), range: 'bytes=0-99');
      expect(status, 206);
      expect(body, plain.sublist(0, 100));
    });

    test('reader close waits for an in-flight read', () async {
      final reader = await store.openReader(item.id);
      final pending = reader.readAll().then((_) => 'read', onError: (Object _) => 'aborted');
      await Future<void>.delayed(Duration.zero); // let the read start
      await reader.close(); // must not throw "async operation is currently pending"
      expect(await pending, anyOf('read', 'aborted'));
      await reader.close(); // idempotent
    });

    test('server binds to loopback only', () {
      expect(server.urlFor(item.id).host, '127.0.0.1');
    });
  });
}
