import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../services/encryption_service.dart';

class LockedReelsScreen extends StatefulWidget {
  final int selectedTabIndex;

  const LockedReelsScreen({super.key, required this.selectedTabIndex});

  @override
  State<LockedReelsScreen> createState() => _LockedReelsScreenState();
}

class _LockedReelsScreenState extends State<LockedReelsScreen> {
  final EncryptionService _encryptionService = EncryptionService();
  List<File> _videoFiles = [];
  bool _isLoading = true;
  final PageController _pageController = PageController();
  int _currentPageIndex = 0;

  static const int _reelsTabIndex = 1;

  @override
  void initState() {
    super.initState();
    _loadVideos();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadVideos() async {
    setState(() => _isLoading = true);
    await _encryptionService.initialize();
    
    final allFiles = await _encryptionService.listEncryptedFiles();
    final videoFiles = <File>[];
    
    for (final file in allFiles) {
      if (await _encryptionService.isVideo(file)) {
        videoFiles.add(file);
      }
    }
    
    videoFiles.shuffle();

    setState(() {
      _videoFiles = videoFiles;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Locked Reels'),
        centerTitle: true,
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.shuffle),
            onPressed: _loadVideos,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _videoFiles.isEmpty
              ? const Center(
                  child: Text(
                    'No locked videos found.',
                    style: TextStyle(color: Colors.white70),
                  ),
                )
              : PageView.builder(
                  controller: _pageController,
                  scrollDirection: Axis.vertical,
                  itemCount: _videoFiles.length,
                  onPageChanged: (index) => setState(() => _currentPageIndex = index),
                  itemBuilder: (context, index) {
                    final file = _videoFiles[index];
                    final isReelsTab = widget.selectedTabIndex == _reelsTabIndex;
                    final isCurrentReel = _currentPageIndex == index;
                    final isVisible = isReelsTab && isCurrentReel;

                    return FutureBuilder<Uint8List>(
                      future: _encryptionService.decryptFile(file),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        return _LockedVideoPlayer(
                          decryptedData: snapshot.data!,
                          isVisible: isVisible,
                        );
                      },
                    );
                  },
                ),
    );
  }
}

class _LockedVideoPlayer extends StatefulWidget {
  final Uint8List decryptedData;
  final bool isVisible;

  const _LockedVideoPlayer({
    required this.decryptedData,
    required this.isVisible,
  });

  @override
  State<_LockedVideoPlayer> createState() => _LockedVideoPlayerState();
}

class _LockedVideoPlayerState extends State<_LockedVideoPlayer> {
  VideoPlayerController? _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  @override
  void didUpdateWidget(_LockedVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible != oldWidget.isVisible) {
      if (widget.isVisible) {
        _controller?.play();
      } else {
        _controller?.pause();
      }
    }
  }

  Future<void> _initializeVideo() async {
    // Write decrypted data to a temporary file for playback
    final tempDir = Directory.systemTemp;
    final tempFile = File('${tempDir.path}/temp_reel_${DateTime.now().millisecondsSinceEpoch}.mp4');
    await tempFile.writeAsBytes(widget.decryptedData);

    _controller = VideoPlayerController.file(tempFile)
      ..initialize().then((_) {
        if (mounted) {
          setState(() => _initialized = true);
          if (widget.isVisible) {
            _controller!.play();
          }
          _controller!.setLooping(true);
        }
      });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized || _controller == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: _controller!.value.aspectRatio,
            child: VideoPlayer(_controller!),
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Container(
              height: 150,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 20,
          left: 16,
          right: 16,
          child: IgnorePointer(
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Locked Video",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
