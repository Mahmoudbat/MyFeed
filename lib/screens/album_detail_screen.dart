import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';
import '../services/encryption_service.dart';
import '../services/settings_service.dart';

class AlbumDetailScreen extends StatefulWidget {
  final AssetPathEntity album;

  const AlbumDetailScreen({super.key, required this.album});

  @override
  State<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends State<AlbumDetailScreen> {
  final EncryptionService _encryptionService = EncryptionService();
  final SettingsService _settingsService = SettingsService();
  List<AssetEntity> _assets = [];
  bool _isLoading = true;
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _loadAlbumAssets();
  }

  Future<void> _loadAlbumAssets() async {
    setState(() => _isLoading = true);
    
    final count = await widget.album.assetCountAsync;
    final assets = await widget.album.getAssetListPaged(page: 0, size: count);
    
    // Sort by date (newest first)
    assets.sort((a, b) => b.createDateTime.compareTo(a.createDateTime));
    
    setState(() {
      _assets = assets;
      _isLoading = false;
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
              title: Text(widget.album.name),
              centerTitle: true,
              backgroundColor: Colors.black,
            ),
      backgroundColor: Colors.black,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _assets.isEmpty
              ? Center(
                  child: Text(
                    'This album is empty',
                    style: TextStyle(color: Colors.white.withOpacity(0.7)),
                  ),
                )
              : GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 2,
                    mainAxisSpacing: 2,
                  ),
                  itemCount: _assets.length,
                  itemBuilder: (context, index) {
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

  void _openFullScreen(int index) async {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _AlbumAssetViewer(
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

class _AlbumAssetViewer extends StatefulWidget {
  final List<AssetEntity> assets;
  final int initialIndex;
  final SettingsService settingsService;

  const _AlbumAssetViewer({
    required this.assets,
    required this.initialIndex,
    required this.settingsService,
  });

  @override
  State<_AlbumAssetViewer> createState() => _AlbumAssetViewerState();
}

class _AlbumAssetViewerState extends State<_AlbumAssetViewer> {
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

  Future<void> _loadScrollPreference() async {
    final vertical = await widget.settingsService.getScrollDirectionVertical();
    if (mounted) {
      setState(() => _verticalScrolling = vertical);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
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
          return _AlbumAssetViewItem(asset: asset);
        },
      ),
    );
  }
}

// Cached asset view item to reduce glitches
class _AlbumAssetViewItem extends StatefulWidget {
  final AssetEntity asset;

  const _AlbumAssetViewItem({required this.asset});

  @override
  State<_AlbumAssetViewItem> createState() => _AlbumAssetViewItemState();
}

class _AlbumAssetViewItemState extends State<_AlbumAssetViewItem> with AutomaticKeepAliveClientMixin {
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
      return _VideoPlayerWidget(file: _file!);
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

// Video player with full controls (pause/play, timeline, skip)
class _VideoPlayerWidget extends StatefulWidget {
  final File file;

  const _VideoPlayerWidget({required this.file});

  @override
  State<_VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<_VideoPlayerWidget> {
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
