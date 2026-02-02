import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:local_social_media/widgets/video_player_widget.dart';
import '../services/gallery_service.dart';

class ReelsScreen extends StatefulWidget {
  final int selectedTabIndex;

  const ReelsScreen({super.key, required this.selectedTabIndex});

  @override
  State<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends State<ReelsScreen> {
  final GalleryService _galleryService = GalleryService();
  List<AssetEntity> _videoAssets = [];
  bool _isLoading = true;
  bool _permissionGranted = false;
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
    
    final hasPermission = await _galleryService.requestPermissions();
    if (!hasPermission) {
      setState(() {
        _isLoading = false;
        _permissionGranted = false;
      });
      return;
    }
    
    setState(() => _permissionGranted = true);
    
    final videos = await _galleryService.getVideos(page: 0, size: 1000);
    videos.shuffle();

    setState(() {
      _videoAssets = videos;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: isLandscape,
      appBar: isLandscape
          ? null
          : AppBar(
              title: const Text('Reels'),
              centerTitle: true,
              backgroundColor: Colors.black,
              actions: [
                IconButton(
                  icon: const Icon(Icons.shuffle),
                  onPressed: _loadVideos,
                ),
              ],
            ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : !_permissionGranted
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.video_library, size: 64, color: Colors.white54),
                      const SizedBox(height: 16),
                      Text(
                        'Gallery access required',
                        style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 18),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: _loadVideos,
                        child: const Text('Grant Permission'),
                      ),
                    ],
                  ),
                )
              : _videoAssets.isEmpty
                  ? const Center(
                      child: Text(
                        'No videos found in your gallery.',
                        style: TextStyle(color: Colors.white70),
                      ),
                    )
                  : PageView.builder(
                      controller: _pageController,
                      scrollDirection: Axis.vertical,
                      itemCount: _videoAssets.length,
                      onPageChanged: (index) => setState(() => _currentPageIndex = index),
                      itemBuilder: (context, index) {
                        final asset = _videoAssets[index];
                        final isReelsTab = widget.selectedTabIndex == _reelsTabIndex;
                        final isCurrentReel = _currentPageIndex == index;
                        final isVisible = isReelsTab && isCurrentReel;

                        return FutureBuilder<File?>(
                          future: asset.file,
                          builder: (context, snapshot) {
                            if (!snapshot.hasData || snapshot.data == null) {
                              return const Center(child: CircularProgressIndicator());
                            }

                            final file = snapshot.data!;
                            final fileName = asset.title ?? 'Video';

                            return Stack(
                              fit: StackFit.expand,
                              children: [
                                Center(
                                  child: VideoPlayerWidget(
                                    file: file,
                                    isVisible: isVisible,
                                    showProgressBar: true,
                                  ),
                                ),
                                if (!isLandscape) ...[
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
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Text(
                                            "@Me",
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            fileName,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(color: Colors.white70, fontSize: 14),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            );
                          },
                        );
                      },
                    ),
    );
  }
}
