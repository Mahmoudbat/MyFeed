
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:local_social_media/models/album.dart';
import 'package:local_social_media/services/album_service.dart';
import 'package:local_social_media/services/settings_service.dart';
import 'package:local_social_media/services/thumbnail_service.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import '../widgets/media_grid_item.dart';
import 'full_screen_viewer.dart';

enum SortBy {
  newest,
  oldest,
  nameAsc,
  nameDesc,
}

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  final SettingsService _settingsService = SettingsService();
  final ThumbnailService _thumbnailService = ThumbnailService();
  final AlbumService _albumService = AlbumService();
  List<File> _mediaFiles = [];
  bool _isLoading = true;
  SortBy _sortBy = SortBy.newest;
  bool _selectionMode = false;
  final Set<String> _selectedPaths = {};

  @override
  void initState() {
    super.initState();
    _loadSavedMedia();
  }

  Future<void> _loadSavedMedia() async {
    setState(() => _isLoading = true);
    final Directory appDir = await getApplicationDocumentsDirectory();
    final List<FileSystemEntity> entities = appDir.listSync();
    final List<File> files = entities
        .whereType<File>()
        .where((f) => path.basename(f.path) != 'albums.json')
        .toList();

    switch (_sortBy) {
      case SortBy.newest:
        files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
        break;
      case SortBy.oldest:
        files.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
        break;
      case SortBy.nameAsc:
        files.sort((a, b) => path.basename(a.path).compareTo(path.basename(b.path)));
        break;
      case SortBy.nameDesc:
        files.sort((a, b) => path.basename(b.path).compareTo(path.basename(a.path)));
        break;
    }

    setState(() {
      _mediaFiles = files;
      _isLoading = false;
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedPaths.clear();
    });
  }

  void _enterSelectionMode(String path) {
    setState(() {
      _selectionMode = true;
      _selectedPaths.add(path);
    });
  }

  void _toggleSelect(String filePath) {
    setState(() {
      if (_selectedPaths.contains(filePath)) {
        _selectedPaths.remove(filePath);
      } else {
        _selectedPaths.add(filePath);
      }
    });
  }

  void _selectAll() {
    setState(() {
      for (final f in _mediaFiles) {
        _selectedPaths.add(f.path);
      }
    });
  }

  List<File> get _selectedFiles =>
      _mediaFiles.where((f) => _selectedPaths.contains(f.path)).toList();

  Future<void> _deleteSelected() async {
    final files = _selectedFiles;
    if (files.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete selected?'),
        content: Text(
            'Permanently delete ${files.length} item${files.length == 1 ? '' : 's'}? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    for (final file in files) {
      if (await file.exists()) await file.delete();
      final thumb = await _thumbnailService.getThumbnailFile(file);
      if (await thumb.exists()) await thumb.delete();
      await _albumService.removeFileFromAllAlbums(file);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Deleted ${files.length} item(s).')));
      _exitSelectionMode();
      await _loadSavedMedia();
    }
  }

  Future<void> _exportSelected() async {
    final files = _selectedFiles;
    if (files.isEmpty) return;
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null || !mounted) return;
    for (final file in files) {
      final name = path.basename(file.path);
      await file.copy(path.join(dir, name));
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported ${files.length} item(s) to $dir'), backgroundColor: Colors.green),
      );
      _exitSelectionMode();
    }
  }

  Future<void> _moveToAlbum() async {
    final files = _selectedFiles;
    if (files.isEmpty) return;
    final albums = await _albumService.loadAlbums();
    final customAlbums = albums.where((a) => a.isDeletable).toList();
    if (customAlbums.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Create an album first (Albums tab → +)')),
        );
      }
      return;
    }
    if (!mounted) return;
    final chosen = await showDialog<Album>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Move to album'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: customAlbums
                .map((a) => ListTile(
                      title: Text(a.name),
                      subtitle: Text('${a.files.length} items'),
                      onTap: () => Navigator.pop(ctx, a),
                    ))
                .toList(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ],
      ),
    );
    if (chosen == null || !mounted) return;
    await _albumService.addFilesToAlbum(chosen.name, files);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added ${files.length} item(s) to ${chosen.name}'), backgroundColor: Colors.green),
      );
      _exitSelectionMode();
    }
  }

  Future<void> _pickAndCopyMedia() async {
    final List<AssetEntity>? assets = await AssetPicker.pickAssets(
      context,
      pickerConfig: const AssetPickerConfig(
        maxAssets: 100,
        requestType: RequestType.common,
      ),
    );

    if (assets == null) return;

    setState(() => _isLoading = true);
    final Directory appDir = await getApplicationDocumentsDirectory();
    final bool deleteOriginals = await _settingsService.getDeleteAfterImport();

    for (final AssetEntity asset in assets) {
      final File? file = await asset.file;
      if (file != null) {
        final String fileName = path.basename(file.path);
        final String savePath = path.join(appDir.path, fileName);
        final newFile = await file.copy(savePath);
        final bool isVideo = ['.mp4', '.mov', '.avi'].any((ext) => fileName.toLowerCase().endsWith(ext));
        if (isVideo) {
          await _thumbnailService.generateAndSaveThumbnail(newFile);
        }
        if (deleteOriginals) {
          await PhotoManager.editor.deleteWithIds([asset.id]);
        }
      }
    }

    await _loadSavedMedia();
  }

  void _showSortDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sort By'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Date (Newest First)'),
              onTap: () {
                setState(() => _sortBy = SortBy.newest);
                _loadSavedMedia();
                Navigator.of(context).pop();
              },
            ),
            ListTile(
              title: const Text('Date (Oldest First)'),
              onTap: () {
                setState(() => _sortBy = SortBy.oldest);
                _loadSavedMedia();
                Navigator.of(context).pop();
              },
            ),
            ListTile(
              title: const Text('Name (A-Z)'),
              onTap: () {
                setState(() => _sortBy = SortBy.nameAsc);
                _loadSavedMedia();
                Navigator.of(context).pop();
              },
            ),
            ListTile(
              title: const Text('Name (Z-A)'),
              onTap: () {
                setState(() => _sortBy = SortBy.nameDesc);
                _loadSavedMedia();
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _selectionMode
          ? AppBar(
              backgroundColor: Colors.black,
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: _exitSelectionMode,
              ),
              title: Text('${_selectedPaths.length} selected'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.select_all),
                  onPressed: _selectAll,
                  tooltip: 'Select all',
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) {
                    if (value == 'delete') _deleteSelected();
                    if (value == 'export') _exportSelected();
                    if (value == 'move') _moveToAlbum();
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(value: 'export', child: Row(children: [Icon(Icons.folder_open), SizedBox(width: 8), Text('Export')])),
                    const PopupMenuItem(value: 'move', child: Row(children: [Icon(Icons.drive_file_move), SizedBox(width: 8), Text('Move to album')])),
                    const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, color: Colors.red), SizedBox(width: 8), Text('Delete', style: TextStyle(color: Colors.red))])),
                  ],
                ),
              ],
            )
          : AppBar(
              title: const Text('My Private Vault'),
              centerTitle: true,
              backgroundColor: Colors.black,
              actions: [
                IconButton(icon: const Icon(Icons.sort), onPressed: _showSortDialog),
              ],
            ),
      backgroundColor: Colors.black,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _mediaFiles.isEmpty
              ? Center(
                  child: Text(
                    'Your vault is empty.\nPress the + button to add photos and videos.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withOpacity(0.7)),
                  ),
                )
              : GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 2,
                    mainAxisSpacing: 2,
                  ),
                  itemCount: _mediaFiles.length,
                  itemBuilder: (context, index) {
                    final file = _mediaFiles[index];
                    final pathStr = file.path;
                    return MediaGridItem(
                      file: file,
                      index: index,
                      isSelectionMode: _selectionMode,
                      isSelected: _selectedPaths.contains(pathStr),
                      onLongPress: () => _enterSelectionMode(pathStr),
                      onToggleSelect: () => _toggleSelect(pathStr),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => FullScreenViewer(
                              files: _mediaFiles,
                              initialIndex: index,
                            ),
                          ),
                        ).then((_) => _loadSavedMedia());
                      },
                    );
                  },
                ),
      floatingActionButton: _selectionMode
          ? null
          : FloatingActionButton(
              onPressed: _pickAndCopyMedia,
              child: const Icon(Icons.add),
            ),
    );
  }
}
