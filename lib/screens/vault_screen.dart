import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

import '../services/gallery_service.dart';
import '../services/encryption_service.dart';
import '../services/settings_service.dart';

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
  final GalleryService _galleryService = GalleryService();
  final EncryptionService _encryptionService = EncryptionService();
  final SettingsService _settingsService = SettingsService();
  List<AssetEntity> _assets = [];
  bool _isLoading = true;
  bool _permissionGranted = false;
  SortBy _sortBy = SortBy.newest;
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};
  int _currentPage = 0;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadGallery();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent * 0.8) {
      if (!_isLoadingMore && _hasMore) {
        _loadMoreAssets();
      }
    }
  }

  Future<void> _loadGallery() async {
    setState(() {
      _isLoading = true;
      _currentPage = 0;
      _hasMore = true;
      _assets.clear();
    });
    
    final hasPermission = await _galleryService.requestPermissions();
    if (!hasPermission) {
      setState(() {
        _isLoading = false;
        _permissionGranted = false;
      });
      return;
    }
    
    setState(() => _permissionGranted = true);
    
    final assets = await _galleryService.getAllMedia(page: 0, size: 100);
    
    if (assets.isEmpty || assets.length < 100) {
      setState(() => _hasMore = false);
    }
    
    // Sort assets by created date
    switch (_sortBy) {
      case SortBy.newest:
        assets.sort((a, b) => b.createDateTime.compareTo(a.createDateTime));
        break;
      case SortBy.oldest:
        assets.sort((a, b) => a.createDateTime.compareTo(b.createDateTime));
        break;
      case SortBy.nameAsc:
        assets.sort((a, b) => (a.title ?? '').compareTo(b.title ?? ''));
        break;
      case SortBy.nameDesc:
        assets.sort((a, b) => (b.title ?? '').compareTo(a.title ?? ''));
        break;
    }
    
    setState(() {
      _assets = assets;
      _isLoading = false;
      _currentPage = 0;
    });
  }

  Future<void> _loadMoreAssets() async {
    if (_isLoadingMore || !_hasMore) return;
    
    setState(() => _isLoadingMore = true);
    
    final newAssets = await _galleryService.getAllMedia(
      page: _currentPage + 1,
      size: 100,
    );
    
    if (newAssets.isEmpty || newAssets.length < 100) {
      setState(() => _hasMore = false);
    }
    
    // Sort new assets
    switch (_sortBy) {
      case SortBy.newest:
        newAssets.sort((a, b) => b.createDateTime.compareTo(a.createDateTime));
        break;
      case SortBy.oldest:
        newAssets.sort((a, b) => a.createDateTime.compareTo(b.createDateTime));
        break;
      case SortBy.nameAsc:
        newAssets.sort((a, b) => (a.title ?? '').compareTo(b.title ?? ''));
        break;
      case SortBy.nameDesc:
        newAssets.sort((a, b) => (b.title ?? '').compareTo(a.title ?? ''));
        break;
    }
    
    setState(() {
      _assets.addAll(newAssets);
      _currentPage++;
      _isLoadingMore = false;
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _enterSelectionMode(String id) {
    setState(() {
      _selectionMode = true;
      _selectedIds.add(id);
    });
  }

  void _toggleSelect(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) {
          _selectionMode = false;
        }
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _selectAll() {
    setState(() {
      for (final asset in _assets) {
        _selectedIds.add(asset.id);
      }
    });
  }

  Future<void> _addToLockedGallery() async {
    final selectedAssets = _assets.where((a) => _selectedIds.contains(a.id)).toList();
    if (selectedAssets.isEmpty) return;
    
    setState(() => _isLoading = true);
    
    int successCount = 0;
    for (final asset in selectedAssets) {
      try {
        final file = await asset.file;
        if (file != null) {
          await _encryptionService.encryptFile(file);
          successCount++;
        }
      } catch (e) {
        print('Error encrypting file: $e');
      }
    }
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added $successCount item(s) to locked gallery'),
          backgroundColor: Colors.green,
        ),
      );
      _exitSelectionMode();
      setState(() => _isLoading = false);
    }
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
              leading: _sortBy == SortBy.newest ? const Icon(Icons.check) : null,
              onTap: () {
                setState(() => _sortBy = SortBy.newest);
                _loadGallery();
                Navigator.of(context).pop();
              },
            ),
            ListTile(
              title: const Text('Date (Oldest First)'),
              leading: _sortBy == SortBy.oldest ? const Icon(Icons.check) : null,
              onTap: () {
                setState(() => _sortBy = SortBy.oldest);
                _loadGallery();
                Navigator.of(context).pop();
              },
            ),
            ListTile(
              title: const Text('Name (A-Z)'),
              leading: _sortBy == SortBy.nameAsc ? const Icon(Icons.check) : null,
              onTap: () {
                setState(() => _sortBy = SortBy.nameAsc);
                _loadGallery();
                Navigator.of(context).pop();
              },
            ),
            ListTile(
              title: const Text('Name (Z-A)'),
              leading: _sortBy == SortBy.nameDesc ? const Icon(Icons.check) : null,
              onTap: () {
                setState(() => _sortBy = SortBy.nameDesc);
                _loadGallery();
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
              title: Text('${_selectedIds.length} selected'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.select_all),
                  onPressed: _selectAll,
                  tooltip: 'Select all',
                ),
                IconButton(
                  icon: const Icon(Icons.lock),
                  onPressed: _addToLockedGallery,
                  tooltip: 'Add to locked gallery',
                ),
              ],
            )
          : AppBar(
              title: const Text('Gallery'),
              centerTitle: true,
              backgroundColor: Colors.black,
              actions: [
                IconButton(
                  icon: const Icon(Icons.sort),
                  onPressed: _showSortDialog,
                ),
              ],
            ),
      backgroundColor: Colors.black,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : !_permissionGranted
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.photo_library, size: 64, color: Colors.white54),
                      const SizedBox(height: 16),
                      Text(
                        'Gallery access required',
                        style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 18),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: _loadGallery,
                        child: const Text('Grant Permission'),
                      ),
                    ],
                  ),
                )
              : _assets.isEmpty
                  ? Center(
                      child: Text(
                        'No media found in your gallery.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white.withOpacity(0.7)),
                      ),
                    )
                  : GridView.builder(
                      controller: _scrollController,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 2,
                        mainAxisSpacing: 2,
                      ),
                      itemCount: _assets.length + (_hasMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index >= _assets.length) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        
                        final asset = _assets[index];
                        final isSelected = _selectedIds.contains(asset.id);
                        
                        return GestureDetector(
                          onTap: () {
                            if (_selectionMode) {
                              _toggleSelect(asset.id);
                            } else {
                              _openFullScreen(index);
                            }
                          },
                          onLongPress: () => _enterSelectionMode(asset.id),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              FutureBuilder<Uint8List?>(
                                future: asset.thumbnailDataWithSize(const ThumbnailSize(200, 200)),
                                builder: (context, snapshot) {
                                  if (snapshot.hasData && snapshot.data != null) {
                                    return Image.memory(
                                      snapshot.data!,
                                      fit: BoxFit.cover,
                                    );
                                  }
                                  return Container(
                                    color: Colors.grey[900],
                                    child: const Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  );
                                },
                              ),
                              if (asset.type == AssetType.video)
                                Positioned(
                                  bottom: 4,
                                  right: 4,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.7),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.play_arrow, size: 14, color: Colors.white),
                                        const SizedBox(width: 2),
                                        Text(
                                          _formatDuration(asset.duration),
                                          style: const TextStyle(color: Colors.white, fontSize: 10),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              if (_selectionMode)
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isSelected ? Colors.blue : Colors.white.withOpacity(0.3),
                                      border: Border.all(color: Colors.white, width: 2),
                                    ),
                                    child: isSelected
                                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                                        : null,
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
    );
  }

  void _openFullScreen(int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullScreenAssetViewer(
          assets: _assets,
          initialIndex: index,
          settingsService: _settingsService,
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final duration = Duration(seconds: seconds);
    final minutes = duration.inMinutes;
    final secs = duration.inSeconds % 60;
    return '${minutes}:${secs.toString().padLeft(2, '0')}';
  }
}

// Full screen viewer with vertical/horizontal scrolling
class _FullScreenAssetViewer extends StatefulWidget {
  final List<AssetEntity> assets;
  final int initialIndex;
  final SettingsService settingsService;

  const _FullScreenAssetViewer({
    required this.assets,
    required this.initialIndex,
    required this.settingsService,
  });

  @override
  State<_FullScreenAssetViewer> createState() => _FullScreenAssetViewerState();
}

class _FullScreenAssetViewerState extends State<_FullScreenAssetViewer> {
  late PageController _pageController;
  late int _currentIndex;
  bool _verticalScrolling = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _loadScrollPreference();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadScrollPreference() async {
    final vertical = await widget.settingsService.getScrollDirectionVertical();
    if (mounted) {
      setState(() => _verticalScrolling = vertical);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text('${_currentIndex + 1} / ${widget.assets.length}'),
      ),
      body: PageView.builder(
        controller: _pageController,
        scrollDirection: _verticalScrolling ? Axis.vertical : Axis.horizontal,
        itemCount: widget.assets.length,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        itemBuilder: (context, index) {
          final asset = widget.assets[index];
          return _AssetViewItem(asset: asset);
        },
      ),
    );
  }
}

// Cached asset view item to reduce glitches
class _AssetViewItem extends StatefulWidget {
  final AssetEntity asset;

  const _AssetViewItem({required this.asset});

  @override
  State<_AssetViewItem> createState() => _AssetViewItemState();
}

class _AssetViewItemState extends State<_AssetViewItem> with AutomaticKeepAliveClientMixin {
  File? _file;
  bool _isLoading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadFile();
  }

  Future<void> _loadFile() async {
    final file = await widget.asset.file;
    if (mounted) {
      setState(() {
        _file = file;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    if (_isLoading || _file == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (widget.asset.type == AssetType.video) {
      return _VideoPlayerWithControls(file: _file!);
    } else {
      return InteractiveViewer(
        child: Image.file(
          _file!,
          fit: BoxFit.contain,
        ),
      );
    }
  }
}

// Video player with full controls
class _VideoPlayerWithControls extends StatefulWidget {
  final File file;

  const _VideoPlayerWithControls({required this.file});

  @override
  State<_VideoPlayerWithControls> createState() => _VideoPlayerWithControlsState();
}

class _VideoPlayerWithControlsState extends State<_VideoPlayerWithControls> {
  late VideoPlayerController _controller;
  bool _initialized = false;
  bool _showControls = true;
  bool _isFullscreen = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.file)
      ..initialize().then((_) {
        if (mounted) {
          setState(() => _initialized = true);
          _controller.play();
          _controller.setLooping(true);
        }
      });
  }

  @override
  void dispose() {
    if (_isFullscreen) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    _controller.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    setState(() {
      if (_controller.value.isPlaying) {
        _controller.pause();
      } else {
        _controller.play();
      }
      _showControls = true;
    });
  }

  void _skipForward() {
    final newPosition = _controller.value.position + const Duration(seconds: 10);
    if (newPosition < _controller.value.duration) {
      _controller.seekTo(newPosition);
    }
  }

  void _skipBackward() {
    final newPosition = _controller.value.position - const Duration(seconds: 10);
    _controller.seekTo(newPosition > Duration.zero ? newPosition : Duration.zero);
  }

  void _toggleFullscreen() {
    setState(() {
      _isFullscreen = !_isFullscreen;
      if (_isFullscreen) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return GestureDetector(
      onTap: () => setState(() => _showControls = !_showControls),
      onDoubleTap: _skipForward,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: VideoPlayer(_controller),
            ),
          ),
          if (_showControls)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.replay_10, color: Colors.white, size: 48),
                        onPressed: _skipBackward,
                      ),
                      const SizedBox(width: 32),
                      IconButton(
                        icon: Icon(
                          _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
                          size: 64,
                        ),
                        onPressed: _togglePlayPause,
                      ),
                      const SizedBox(width: 32),
                      IconButton(
                        icon: const Icon(Icons.forward_10, color: Colors.white, size: 48),
                        onPressed: _skipForward,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          if (_showControls)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  VideoProgressIndicator(
                    _controller,
                    allowScrubbing: true,
                    colors: const VideoProgressColors(
                      playedColor: Colors.white,
                      bufferedColor: Colors.white24,
                      backgroundColor: Colors.white10,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        ValueListenableBuilder(
                          valueListenable: _controller,
                          builder: (context, VideoPlayerValue value, child) {
                            return Text(
                              '${_formatDuration(value.position)} / ${_formatDuration(value.duration)}',
                              style: const TextStyle(color: Colors.white),
                            );
                          },
                        ),
                        IconButton(
                          icon: Icon(
                            _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                            color: Colors.white,
                          ),
                          onPressed: _toggleFullscreen,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}
