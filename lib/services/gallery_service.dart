import 'dart:io';
import 'package:photo_manager/photo_manager.dart';
import 'package:permission_handler/permission_handler.dart';

class GalleryService {
  // Request gallery permissions
  Future<bool> requestPermissions() async {
    final PermissionState result = await PhotoManager.requestPermissionExtend();
    return result.isAuth || result.hasAccess;
  }

  // Get all media from device gallery
  Future<List<AssetEntity>> getAllMedia({
    int page = 0,
    int size = 100,
  }) async {
    final permitted = await requestPermissions();
    if (!permitted) return [];

    final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
      type: RequestType.common, // Gets both images and videos
      onlyAll: true, // Only get the "all" album
    );

    if (albums.isEmpty) return [];

    final recentAlbum = albums.first;
    final assets = await recentAlbum.getAssetListPaged(
      page: page,
      size: size,
    );

    return assets;
  }

  // Get only images
  Future<List<AssetEntity>> getImages({
    int page = 0,
    int size = 100,
  }) async {
    final permitted = await requestPermissions();
    if (!permitted) return [];

    final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: true,
    );

    if (albums.isEmpty) return [];

    final recentAlbum = albums.first;
    final assets = await recentAlbum.getAssetListPaged(
      page: page,
      size: size,
    );

    return assets;
  }

  // Get only videos
  Future<List<AssetEntity>> getVideos({
    int page = 0,
    int size = 100,
  }) async {
    final permitted = await requestPermissions();
    if (!permitted) return [];

    final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
      type: RequestType.video,
      onlyAll: true,
    );

    if (albums.isEmpty) return [];

    final recentAlbum = albums.first;
    final assets = await recentAlbum.getAssetListPaged(
      page: page,
      size: size,
    );

    return assets;
  }

  // Get file from asset
  Future<File?> getFileFromAsset(AssetEntity asset) async {
    return await asset.file;
  }

  // Get thumbnail data
  Future<List<int>?> getThumbnail(
    AssetEntity asset, {
    int width = 200,
    int height = 200,
  }) async {
    return await asset.thumbnailDataWithSize(
      ThumbnailSize(width, height),
    );
  }

  // Get all albums from device
  Future<List<AssetPathEntity>> getAllAlbums() async {
    final permitted = await requestPermissions();
    if (!permitted) return [];

    return await PhotoManager.getAssetPathList(
      type: RequestType.common,
    );
  }

  // Refresh gallery (call when permissions are granted)
  Future<void> refreshGallery() async {
    await PhotoManager.clearFileCache();
  }
}
