import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:share_plus/share_plus.dart';

import '../services/gallery_service.dart';
import '../util/format.dart';
import '../widgets/progress_dialog.dart';

/// Everyday gallery actions (share, delete, details) for device media.

Future<void> shareAssets(BuildContext context, List<AssetEntity> assets) async {
  if (assets.isEmpty) return;
  final files = <XFile>[];
  for (final asset in assets) {
    final file = await asset.file;
    if (file != null) files.add(XFile(file.path, mimeType: asset.mimeType));
  }
  if (files.isEmpty) {
    if (context.mounted) showSnack(context, "Couldn't open the selected files", error: true);
    return;
  }
  await SharePlus.instance.share(ShareParams(files: files));
}

/// Moves [assets] to the system Trash (Android 11+, restorable for 30 days),
/// or deletes them permanently after confirmation on older Android.
/// Returns the ids that were removed from the gallery.
Future<Set<String>> deleteAssets(BuildContext context, List<AssetEntity> assets) async {
  if (assets.isEmpty) return {};
  final gallery = GalleryService.instance;
  final noun = assets.length == 1 ? 'item' : '${assets.length} items';

  // Android shows its own "Move to trash?" prompt here.
  final trashed = await gallery.moveToTrash(assets);
  if (trashed != null) {
    if (context.mounted && trashed.isNotEmpty) {
      showSnack(context, 'Moved ${trashed.length == 1 ? 'item' : '${trashed.length} items'} to Trash');
    }
    return trashed.toSet();
  }

  if (!context.mounted) return {};
  final ok = await confirm(
    context,
    title: 'Delete $noun?',
    message: 'This device has no Trash, so this permanently deletes the $noun from your phone.',
    action: 'Delete',
    destructive: true,
  );
  if (!ok) return {};
  try {
    final deleted = await gallery.deleteOriginals(assets.map((a) => a.id).toList());
    if (context.mounted && deleted.isNotEmpty) {
      showSnack(context, 'Deleted ${deleted.length == 1 ? 'item' : '${deleted.length} items'}');
    }
    return deleted.toSet();
  } catch (e) {
    if (context.mounted) showSnack(context, 'Delete failed: $e', error: true);
    return {};
  }
}

Future<void> showAssetDetails(BuildContext context, AssetEntity asset) async {
  final file = await asset.originFile ?? await asset.file;
  final size = file == null ? null : await file.length();
  if (!context.mounted) return;
  String date(DateTime d) => d.toLocal().toString().split('.').first;
  final rows = <(String, String)>[
    ('Name', asset.title ?? file?.uri.pathSegments.last ?? '—'),
    ('Type', asset.type == AssetType.video ? 'Video' : 'Photo'),
    if (asset.mimeType != null) ('Format', asset.mimeType!),
    if (size != null) ('Size', formatBytes(size)),
    if (asset.width > 0) ('Resolution', '${asset.width} × ${asset.height}'),
    if (asset.type == AssetType.video && asset.duration > 0) ('Duration', formatSeconds(asset.duration)),
    ('Taken', date(asset.createDateTime)),
    ('Modified', date(asset.modifiedDateTime)),
    if (asset.relativePath != null && asset.relativePath!.isNotEmpty) ('Folder', asset.relativePath!),
  ];
  await showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Details', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 96, child: Text(label, style: const TextStyle(color: Colors.white60))),
                    Expanded(child: SelectableText(value)),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
