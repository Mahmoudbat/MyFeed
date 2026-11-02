import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_social_media/vault/models.dart';
import 'package:local_social_media/vault/vault_keys.dart';
import 'package:local_social_media/vault/vault_store.dart';

void main() {
  late Directory dir;
  VaultStore newStore() => VaultStore(Directory('${dir.path}/vault'), iterations: 1000);

  setUp(() async => dir = await Directory.systemTemp.createTemp('vault_test'));
  tearDown(() async => dir.delete(recursive: true));

  test('key header: right password unwraps, wrong password fails', () async {
    final (header, dek) = await VaultKeyHeader.create('correct horse', iterations: 1000);
    final restored = VaultKeyHeader.fromJson(jsonDecode(jsonEncode(header.toJson())) as Map<String, dynamic>);
    expect(await (await restored.unwrap('correct horse')).extractBytes(), await dek.extractBytes());
    expect(() => restored.unwrap('wrong'), throwsA(isA<WrongPasswordException>()));
  });

  test('nothing secret is stored in the clear', () async {
    final store = newStore();
    await store.create('hunter22');
    final source = File('${dir.path}/IMG_1234.jpg')..writeAsBytesSync(utf8.encode('SECRET-PIXELS' * 100));
    await store.importFile(source, kind: MediaKind.image, name: 'IMG_1234.jpg', thumbnail: Uint8List(10));

    final allBytes = <int>[];
    for (final f in Directory(store.root.path).listSync(recursive: true).whereType<File>()) {
      // File names are random ids only.
      expect(f.path.contains('IMG_1234'), isFalse);
      allBytes.addAll(f.readAsBytesSync());
    }
    final dump = latin1.decode(allBytes);
    expect(dump.contains('hunter22'), isFalse);
    expect(dump.contains('SECRET-PIXELS'), isFalse);
    expect(dump.contains('IMG_1234'), isFalse);
    expect(dump.contains('.jpg'), isFalse);
  });

  test('items and albums persist across lock/unlock', () async {
    final store = newStore();
    await store.create('pw123456');
    final a = File('${dir.path}/a.mp4')..writeAsBytesSync(List.generate(5000, (i) => i % 251));
    final b = File('${dir.path}/b.png')..writeAsBytesSync([1, 2, 3]);
    final itemA = await store.importFile(a, kind: MediaKind.video, name: 'a.mp4', sourceId: 'src-a', durationSeconds: 12);
    final itemB = await store.importFile(b, kind: MediaKind.image, name: 'b.png', thumbnail: Uint8List.fromList([9, 9]));
    final album = await store.createAlbum('Trips');
    await store.addToAlbum(album.id, [itemA.id, itemB.id, 'missing']);
    await store.renameAlbum(album.id, 'Holidays');

    store.lock();
    expect(store.isUnlocked, isFalse);
    expect(store.items, isEmpty);
    expect(() => store.readAll(itemA.id), throwsA(isA<VaultLockedException>()));

    final reopened = newStore();
    await expectLater(reopened.unlock('nope'), throwsA(isA<WrongPasswordException>()));
    await reopened.unlock('pw123456');
    expect(reopened.items.map((i) => i.id), containsAll([itemA.id, itemB.id]));
    expect(reopened.importedSourceIds, {'src-a'});
    expect(reopened.itemById(itemA.id)!.durationSeconds, 12);
    expect(await reopened.readAll(itemA.id), a.readAsBytesSync());
    expect(await reopened.readThumbnail(itemB.id), [9, 9]);
    expect(await reopened.readThumbnail(itemA.id), isNull);
    final restoredAlbum = reopened.albums.single;
    expect(restoredAlbum.name, 'Holidays');
    expect(restoredAlbum.itemIds, [itemA.id, itemB.id]);

    await reopened.deleteItems([itemA.id]);
    expect(reopened.mediaFile(itemA.id).existsSync(), isFalse);
    expect(reopened.albums.single.itemIds, [itemB.id]);
  });

  test('changing the password keeps the data and rejects the old password', () async {
    final store = newStore();
    await store.create('old-password');
    final item = await store.importBytes(Uint8List.fromList([4, 5, 6]),
        kind: MediaKind.image, name: 'x.jpg', extension: '.jpg');
    await expectLater(store.changePassword('bad', 'new-password'), throwsA(isA<WrongPasswordException>()));
    await store.changePassword('old-password', 'new-password');

    final reopened = newStore();
    await expectLater(reopened.unlock('old-password'), throwsA(isA<WrongPasswordException>()));
    await reopened.unlock('new-password');
    expect(await reopened.readAll(item.id), [4, 5, 6]);
  });

  test('concurrent mutations are all persisted', () async {
    final store = newStore();
    await store.create('pw123456');
    await Future.wait([for (var i = 0; i < 10; i++) store.createAlbum('album $i')]);
    final reopened = newStore();
    await reopened.unlock('pw123456');
    expect(reopened.albums.length, 10);
  });

  test('wipe removes everything', () async {
    final store = newStore();
    await store.create('pw123456');
    await store.wipe();
    expect(await store.exists(), isFalse);
    expect(store.root.existsSync(), isFalse);
  });

  test('media kind detection covers common video containers', () {
    for (final ext in ['.mp4', '.MOV', '.mkv', '.webm', '.3gp']) {
      expect(kindForExtension(ext), MediaKind.video, reason: ext);
    }
    for (final ext in ['.jpg', '.heic', '.png', '.gif', '.webp']) {
      expect(kindForExtension(ext), MediaKind.image, reason: ext);
    }
  });
}
