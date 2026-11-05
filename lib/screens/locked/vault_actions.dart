import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../services/app_settings.dart';
import '../../services/gallery_service.dart';
import '../../vault/models.dart';
import '../../vault/vault_session.dart';
import '../../vault/vault_store.dart';
import '../../widgets/progress_dialog.dart';
import 'auth_screen.dart';

VaultSession get _session => VaultSession.instance;

/// Makes sure the vault is unlocked, asking for the password (or setting the
/// vault up) if needed. Returns false if the user backed out.
Future<bool> ensureVaultUnlocked(BuildContext context) async {
  if (_session.isUnlocked) return true;
  final ok = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      settings: const RouteSettings(name: '/auth'),
      builder: (_) => const AuthScreen(returnResult: true),
    ),
  );
  return ok == true && _session.isUnlocked;
}

class LockResult {
  LockResult(this.locked, this.skipped, this.failed, this.removedOriginals);
  final int locked;
  final int skipped;
  final int failed;
  final int removedOriginals;
}

/// Encrypts [assets] into the locked gallery, then (if enabled) asks the
/// system to delete the originals so they no longer appear in the gallery.
/// Returns null if the user cancelled authentication.
Future<LockResult?> lockAssets(BuildContext context, List<AssetEntity> assets) async {
  if (assets.isEmpty) return null;
  final wasUnlocked = _session.isUnlocked;
  if (!await ensureVaultUnlocked(context)) return null;
  if (!context.mounted) return null;

  final store = _session.store;
  final lockedSourceIds = <String>[];
  var skipped = 0, failed = 0;
  try {
    await runWithProgress<void>(context, title: 'Moving to locked gallery', task: (report) {
      return _session.guard(() async {
        final already = store.importedSourceIds;
        for (var i = 0; i < assets.length; i++) {
          final asset = assets[i];
          report(ProgressValue(i, assets.length));
          if (already.contains(asset.id)) {
            skipped++;
            lockedSourceIds.add(asset.id); // still remove the duplicate original
            continue;
          }
          try {
            final file = await asset.originFile ?? await asset.file;
            if (file == null) throw StateError('file unavailable');
            final thumb = await asset.thumbnailDataWithSize(const ThumbnailSize(320, 320), quality: 85);
            final kind = asset.type == AssetType.video ? MediaKind.video : MediaKind.image;
            await store.importFile(
              file,
              kind: kind,
              name: asset.title ?? p.basename(file.path),
              thumbnail: thumb,
              createdAt: asset.createDateTime,
              sourceId: asset.id,
              durationSeconds: asset.duration,
              width: asset.width,
              height: asset.height,
              onProgress: (done, total) =>
                  report(ProgressValue(i, assets.length, total == 0 ? 0 : done / total)),
            );
            lockedSourceIds.add(asset.id);
          } catch (e) {
            debugPrint('lock failed for ${asset.id}: $e');
            failed++;
          }
        }
        report(ProgressValue(assets.length, assets.length));
      });
    });

    var removed = 0;
    if (AppSettings.instance.removeOriginalsAfterLocking && lockedSourceIds.isNotEmpty) {
      try {
        removed = (await GalleryService.instance.deleteOriginals(lockedSourceIds)).length;
      } catch (e) {
        debugPrint('delete originals failed: $e');
      }
    }
    return LockResult(lockedSourceIds.length - skipped, skipped, failed, removed);
  } finally {
    if (!wasUnlocked) _session.lock();
  }
}

String describeLockResult(LockResult r) {
  final parts = <String>['Locked ${r.locked} item${r.locked == 1 ? '' : 's'}'];
  if (r.skipped > 0) parts.add('${r.skipped} already locked');
  if (r.failed > 0) parts.add('${r.failed} failed');
  if (AppSettings.instance.removeOriginalsAfterLocking) {
    parts.add(r.removedOriginals > 0 ? 'originals removed from gallery' : 'originals kept in gallery');
  }
  return parts.join(' · ');
}

/// Decrypts [items] back into the public gallery. Optionally removes them
/// from the vault afterwards (the "delete after export" setting).
Future<void> restoreToGallery(BuildContext context, List<LockedItem> items) async {
  if (items.isEmpty) return;
  if (!await GalleryService.instance.ensurePermission()) {
    if (context.mounted) showSnack(context, 'Gallery access is required to export', error: true);
    return;
  }
  if (!context.mounted) return;
  final store = _session.store;
  final restored = <String>[];
  var failed = 0;
  final tempDir = await Directory(p.join((await getTemporaryDirectory()).path, 'export')).create(recursive: true);
  if (!context.mounted) return;
  try {
    await runWithProgress<void>(context, title: 'Restoring to gallery', task: (report) {
      return _session.guard(() async {
        for (var i = 0; i < items.length; i++) {
          final item = items[i];
          report(ProgressValue(i, items.length));
          // Plaintext must exist briefly as a file for MediaStore to import it;
          // it lives in the app's private cache and is deleted right after.
          final temp = File(p.join(tempDir.path, '${VaultStore.newId()}${item.extension}'));
          try {
            await store.decryptToFile(item.id, temp);
            final title = p.basenameWithoutExtension(item.name).isEmpty ? item.id : item.name;
            if (item.isVideo) {
              await GalleryService.instance.saveVideo(temp, title, item.createdAt);
            } else {
              await GalleryService.instance.saveImage(temp, title, item.createdAt);
            }
            restored.add(item.id);
          } catch (e) {
            debugPrint('restore failed for ${item.id}: $e');
            failed++;
          } finally {
            if (await temp.exists()) await temp.delete();
          }
        }
        if (AppSettings.instance.deleteAfterExport && restored.isNotEmpty) {
          await store.deleteItems(restored);
        }
      });
    });
  } finally {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  }
  if (context.mounted) {
    final removed = AppSettings.instance.deleteAfterExport ? ' and removed from locked gallery' : '';
    showSnack(
      context,
      'Restored ${restored.length} item${restored.length == 1 ? '' : 's'} to gallery$removed'
      '${failed > 0 ? ' · $failed failed' : ''}',
      error: failed > 0,
    );
  }
}
