
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:local_social_media/widgets/video_player_widget.dart';

class ReelsScreen extends StatefulWidget {
  final int selectedTabIndex;

  const ReelsScreen({super.key, required this.selectedTabIndex});

  @override
  State<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends State<ReelsScreen> {
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
    final Directory appDir = await getApplicationDocumentsDirectory();
    final List<FileSystemEntity> entities = appDir.listSync();
    final List<File> allFiles = entities.whereType<File>().toList();

    final List<File> videoFiles = allFiles.where((file) {
      final String extension = path.extension(file.path).toLowerCase();
      return extension == '.mp4' || extension == '.mov' || extension == '.avi';
    }).toList();
    videoFiles.shuffle();

    setState(() {
      _videoFiles = videoFiles;
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
          : _videoFiles.isEmpty
              ? const Center(
                  child: Text(
                    'No videos found in your vault.',
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
                    final fileName = path.basename(file.path);
                    final isReelsTab = widget.selectedTabIndex == _reelsTabIndex;
                    final isCurrentReel = _currentPageIndex == index;
                    final isVisible = isReelsTab && isCurrentReel;

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
                ),
    );
  }
}
