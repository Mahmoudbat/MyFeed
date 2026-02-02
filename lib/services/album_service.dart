
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/album.dart';

class AlbumService {
  Future<File> get _albumsFile async {
    final Directory appDir = await getApplicationDocumentsDirectory();
    return File(path.join(appDir.path, 'albums.json'));
  }

  Future<List<Album>> loadAlbums() async {
    final File file = await _albumsFile;
    if (!await file.exists()) {
      return [];
    }
    final String content = await file.readAsString();
    final List<dynamic> jsonList = jsonDecode(content);

    // First, get all media files from the root directory
    final Directory appDir = await getApplicationDocumentsDirectory();
    final List<File> allFiles = appDir.listSync().whereType<File>().toList();

    final List<Album> customAlbums = jsonList.map((json) => Album.fromJson(json, allFiles)).toList();

    // Now, create the virtual "All", "Images", and "Videos" albums
    final images = allFiles.where((f) => path.extension(f.path).toLowerCase().contains(RegExp(r'(jpg|jpeg|png|gif)$'))).toList();
    final videos = allFiles.where((f) => path.extension(f.path).toLowerCase().contains(RegExp(r'(mp4|mov|avi)$'))).toList();

    return [
      Album(name: 'All Media', files: allFiles),
      if (images.isNotEmpty) Album(name: 'Images', files: images),
      if (videos.isNotEmpty) Album(name: 'Videos', files: videos),
      ...customAlbums,
    ];
  }

  Future<void> saveAlbums(List<Album> albums) async {
    final File file = await _albumsFile;
    final List<Map<String, dynamic>> jsonList = albums
        .where((album) => album.isDeletable) // Only save custom albums
        .map((album) => album.toJson())
        .toList();
    await file.writeAsString(jsonEncode(jsonList));
  }

  Future<void> createAlbum(String name) async {
    final albums = await loadAlbums();
    if (albums.any((album) => album.name == name)) {
      return; // Album already exists
    }
    final newAlbum = Album(name: name, isDeletable: true);
    await saveAlbums([ ...albums, newAlbum ]);
  }

  Future<void> deleteAlbum(String name) async {
    final albums = await loadAlbums();
    albums.removeWhere((album) => album.name == name);
    await saveAlbums(albums);
  }

  Future<void> addFilesToAlbum(String albumName, List<File> filesToAdd) async {
    final albums = await loadAlbums();
    final Album album = albums.firstWhere((a) => a.name == albumName);
    album.files.addAll(filesToAdd);
    await saveAlbums(albums);
  }

  Future<void> removeFileFromAllAlbums(File fileToRemove) async {
    final albums = await loadAlbums();
    for (final album in albums) {
      if (album.isDeletable) {
        album.files.removeWhere((f) => f.path == fileToRemove.path);
      }
    }
    await saveAlbums(albums);
  }

  /// Remove specific files from a custom album only.
  Future<void> removeFilesFromAlbum(String albumName, List<File> filesToRemove) async {
    final albums = await loadAlbums();
    final pathsToRemove = filesToRemove.map((f) => f.path).toSet();
    for (final album in albums) {
      if (album.isDeletable && album.name == albumName) {
        album.files.removeWhere((f) => pathsToRemove.contains(f.path));
        break;
      }
    }
    await saveAlbums(albums);
  }
}
