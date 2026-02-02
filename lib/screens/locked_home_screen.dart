import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../services/encryption_service.dart';
import '../services/settings_service.dart';

class LockedHomeScreen extends StatefulWidget {
  final int selectedTabIndex;

  const LockedHomeScreen({super.key, required this.selectedTabIndex});

  @override
  State<LockedHomeScreen> createState() => _LockedHomeScreenState();
}

class _LockedHomeScreenState extends State<LockedHomeScreen> {
  final EncryptionService _encryptionService = EncryptionService();
  final SettingsService _settingsService = SettingsService();
  List<File> _encryptedFiles = [];
  bool _isLoading = true;
  bool _selectionMode = false;
  final Set<String> _selectedPaths = {};
  final Map<String, Uint8List> _thumbnailCache = {};

  @override
  void initState() {
    super.initState();
    _loadEncryptedMedia();
  }

  Future<void> _loadEncryptedMedia() async {
    setState(() => _isLoading = true);
    await _encryptionService.initialize();
    final files = await _encryptionService.listEncryptedFiles();
    
    // Sort by newest first
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    
    setState(() {
      _encryptedFiles = files;
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

  void _toggleSelect(String path) {
    setState(() {
      if (_selectedPaths.contains(path)) {
        _selectedPaths.remove(path);
        if (_selectedPaths.isEmpty) {
          _selectionMode = false;
        }
      } else {
        _selectedPaths.add(path);
      }
    });
  }

  void _selectAll() {
    setState(() {
      for (final file in _encryptedFiles) {
        _selectedPaths.add(file.path);
      }
    });
  }

  Future<void> _deleteSelected() async {
    final selectedFiles = _encryptedFiles.where((f) => _selectedPaths.contains(f.path)).toList();
    if (selectedFiles.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete selected?'),
        content: Text(
          'Permanently delete ${selectedFiles.length} item${selectedFiles.length == 1 ? '' : 's'}? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    for (final file in selectedFiles) {
      await _encryptionService.deleteEncryptedFile(file);
      _thumbnailCache.remove(file.path);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted ${selectedFiles.length} item(s).')),
      );
      _exitSelectionMode();
      await _loadEncryptedMedia();
    }
  }

  Future<Uint8List?> _getThumbnail(File file) async {
    // Return cached thumbnail if available
    if (_thumbnailCache.containsKey(file.path)) {
      return _thumbnailCache[file.path];
    }

    // Don't decrypt videos for thumbnails - too slow
    final isVideo = await _encryptionService.isVideo(file);
    if (isVideo) {
      return null;
    }

    try {
      // Decrypt and cache thumbnail for images only
      final decrypted = await _encryptionService.decryptFile(file);
      _thumbnailCache[file.path] = decrypted;
      return decrypted;
    } catch (e) {
      return null;
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
              title: Text('${_selectedPaths.length} selected'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.select_all),
                  onPressed: _selectAll,
                  tooltip: 'Select all',
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: _deleteSelected,
                  tooltip: 'Delete',
                ),
              ],
            )
          : AppBar(
              title: const Text('Locked Gallery'),
              centerTitle: true,
              backgroundColor: Colors.black,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
      backgroundColor: Colors.black,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _encryptedFiles.isEmpty
              ? Center(
                  child: Text(
                    'No locked media.\nSelect photos/videos from the main gallery to add them here.',
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
                  itemCount: _encryptedFiles.length,
                  itemBuilder: (context, index) {
                    final file = _encryptedFiles[index];
                    final isSelected = _selectedPaths.contains(file.path);

                    return GestureDetector(
                      onTap: () {
                        if (_selectionMode) {
                          _toggleSelect(file.path);
                        } else {
                          _openFullScreen(index);
                        }
                      },
                      onLongPress: () => _enterSelectionMode(file.path),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          FutureBuilder<Uint8List?>(
                            future: _getThumbnail(file),
                            builder: (context, snapshot) {
                              if (snapshot.hasData && snapshot.data != null) {
                                return Image.memory(
                                  snapshot.data!,
                                  fit: BoxFit.cover,
                                  gaplessPlayback: true,
                                );
                              }
                              return Container(
                                color: Colors.grey[900],
                                child: FutureBuilder<bool>(
                                  future: _encryptionService.isVideo(file),
                                  builder: (context, isVideoSnapshot) {
                                    if (isVideoSnapshot.data == true) {
                                      return const Center(
                                        child: Icon(
                                          Icons.play_circle_outline,
                                          size: 48,
                                          color: Colors.white54,
                                        ),
                                      );
                                    }
                                    return const Center(
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    );
                                  },
                                ),
                              );
                            },
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
        builder: (_) => _FullScreenLockedViewer(
          files: _encryptedFiles,
          initialIndex: index,
          encryptionService: _encryptionService,
          settingsService: _settingsService,
        ),
      ),
    );
  }
}

// Fullscreen viewer with vertical/horizontal scrolling
class _FullScreenLockedViewer extends StatefulWidget {
  final List<File> files;
  final int initialIndex;
  final EncryptionService encryptionService;
  final SettingsService settingsService;

  const _FullScreenLockedViewer({
    required this.files,
    required this.initialIndex,
    required this.encryptionService,
    required this.settingsService,
  });

  @override
  State<_FullScreenLockedViewer> createState() => _FullScreenLockedViewerState();
}

class _FullScreenLockedViewerState extends State<_FullScreenLockedViewer> {
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
        title: Text('${_currentIndex + 1} / ${widget.files.length}'),
      ),
      body: PageView.builder(
        controller: _pageController,
        scrollDirection: _verticalScrolling ? Axis.vertical : Axis.horizontal,
        itemCount: widget.files.length,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        itemBuilder: (context, index) {
          final file = widget.files[index];
          return _LockedMediaItem(
            file: file,
            encryptionService: widget.encryptionService,
          );
        },
      ),
    );
  }
}

// Cached media item to prevent repeated decryption
class _LockedMediaItem extends StatefulWidget {
  final File file;
  final EncryptionService encryptionService;

  const _LockedMediaItem({
    required this.file,
    required this.encryptionService,
  });

  @override
  State<_LockedMediaItem> createState() => _LockedMediaItemState();
}

class _LockedMediaItemState extends State<_LockedMediaItem> with AutomaticKeepAliveClientMixin {
  Uint8List? _decryptedData;
  bool _isLoading = true;
  bool _isVideo = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadMedia();
  }

  Future<void> _loadMedia() async {
    _isVideo = await widget.encryptionService.isVideo(widget.file);
    final decrypted = await widget.encryptionService.decryptFile(widget.file);
    
    if (mounted) {
      setState(() {
        _decryptedData = decrypted;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    if (_isLoading || _decryptedData == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_isVideo) {
      return _LockedVideoPlayer(videoData: _decryptedData!);
    } else {
      return InteractiveViewer(
        child: Image.memory(
          _decryptedData!,
          fit: BoxFit.contain,
        ),
      );
    }
  }
}

// Video player for locked videos with full controls
class _LockedVideoPlayer extends StatefulWidget {
  final Uint8List videoData;

  const _LockedVideoPlayer({required this.videoData});

  @override
  State<_LockedVideoPlayer> createState() => _LockedVideoPlayerState();
}

class _LockedVideoPlayerState extends State<_LockedVideoPlayer> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _showControls = true;
  bool _isFullscreen = false;
  File? _tempFile;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      // Create temp file for video playback
      final tempDir = await Directory.systemTemp.createTemp('locked_video_');
      _tempFile = File('${tempDir.path}/video.mp4');
      await _tempFile!.writeAsBytes(widget.videoData);

      _controller = VideoPlayerController.file(_tempFile!)
        ..initialize().then((_) {
          if (mounted) {
            setState(() => _initialized = true);
            _controller!.play();
            _controller!.setLooping(true);
          }
        });
    } catch (e) {
      print('Error initializing video: $e');
    }
  }

  @override
  void dispose() {
    if (_isFullscreen) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    _controller?.dispose();
    _tempFile?.parent.deleteSync(recursive: true);
    super.dispose();
  }

  void _togglePlayPause() {
    if (_controller == null) return;
    setState(() {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
      } else {
        _controller!.play();
      }
      _showControls = true;
    });
  }

  void _skipForward() {
    if (_controller == null) return;
    final newPosition = _controller!.value.position + const Duration(seconds: 10);
    if (newPosition < _controller!.value.duration) {
      _controller!.seekTo(newPosition);
    }
  }

  void _skipBackward() {
    if (_controller == null) return;
    final newPosition = _controller!.value.position - const Duration(seconds: 10);
    _controller!.seekTo(newPosition > Duration.zero ? newPosition : Duration.zero);
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
    if (!_initialized || _controller == null) {
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
              aspectRatio: _controller!.value.aspectRatio,
              child: VideoPlayer(_controller!),
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
                          _controller!.value.isPlaying ? Icons.pause : Icons.play_arrow,
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
                    _controller!,
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
                          valueListenable: _controller!,
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
