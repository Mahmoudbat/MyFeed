import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

enum GallerySort { newest, oldest, nameAsc, nameDesc }

extension GallerySortLabel on GallerySort {
  String get label => switch (this) {
        GallerySort.newest => 'Date (newest first)',
        GallerySort.oldest => 'Date (oldest first)',
        GallerySort.nameAsc => 'Name (A–Z)',
        GallerySort.nameDesc => 'Name (Z–A)',
      };

  bool get byName => this == GallerySort.nameAsc || this == GallerySort.nameDesc;
}

/// Thin wrapper around photo_manager shared by every screen, so the
/// permission is requested once instead of by each tab independently.
class GalleryService {
  GalleryService._();
  static final GalleryService instance = GalleryService._();

  Future<bool>? _permission;
  bool _watching = false;
  Timer? _debounce;

  /// Bumped whenever the device gallery changes (items added/removed by us or
  /// other apps), so open grids can refresh.
  final ValueNotifier<int> changes = ValueNotifier(0);

  /// Requests gallery access once per app run (re-requested only after a denial).
  Future<bool> ensurePermission({bool force = false}) {
    if (force || _permission == null) {
      final request = PhotoManager.requestPermissionExtend().then((s) => s.hasAccess);
      _permission = request;
      request.then((granted) {
        if (!granted) {
          _permission = null;
        } else {
          _startWatching();
        }
      });
    }
    return _permission!;
  }

  void _startWatching() {
    if (_watching) return;
    _watching = true;
    PhotoManager.addChangeCallback((_) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 600), () => changes.value++);
    });
    PhotoManager.startChangeNotify();
  }

  static FilterOptionGroup _filter({bool ascending = false}) => FilterOptionGroup(
        orders: [OrderOption(type: OrderOptionType.createDate, asc: ascending)],
      );

  /// The device-wide "Recent"/"All" album.
  Future<AssetPathEntity?> allMedia({
    RequestType type = RequestType.common,
    bool ascending = false,
  }) async {
    if (!await ensurePermission()) return null;
    final paths = await PhotoManager.getAssetPathList(
      type: type,
      onlyAll: true,
      filterOption: _filter(ascending: ascending),
    );
    return paths.isEmpty ? null : paths.first;
  }

  Future<List<AssetPathEntity>> albums() async {
    if (!await ensurePermission()) return [];
    return PhotoManager.getAssetPathList(type: RequestType.common, filterOption: _filter());
  }

  /// Re-applies a date sort order to an album obtained elsewhere.
  Future<AssetPathEntity> withOrder(AssetPathEntity path, {required bool ascending}) async =>
      await path.fetchPathProperties(filterOptionGroup: _filter(ascending: ascending)) ?? path;

  /// Deletes originals from the device gallery. On Android 11+ the system
  /// asks the user to confirm. Returns the ids actually deleted.
  Future<List<String>> deleteOriginals(List<String> ids) async {
    if (ids.isEmpty) return [];
    return PhotoManager.editor.deleteWithIds(ids);
  }

  Future<AssetEntity> saveImage(File file, String title, DateTime? created) =>
      PhotoManager.editor.saveImageWithPath(file.path, title: title, creationDate: created);

  Future<AssetEntity> saveVideo(File file, String title, DateTime? created) =>
      PhotoManager.editor.saveVideo(file, title: title, creationDate: created);
}
