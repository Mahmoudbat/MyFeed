
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VideoPlayerWidget extends StatefulWidget {
  final File file;
  /// When false (e.g. not on Reels tab or not the current reel), video is paused.
  final bool isVisible;
  /// Whether to show the progress bar and allow scrubbing.
  final bool showProgressBar;

  const VideoPlayerWidget({
    super.key,
    required this.file,
    this.isVisible = true,
    this.showProgressBar = true,
  });

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  late VideoPlayerController _controller;
  Offset? _lastDoubleTapPosition;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.file)
      ..initialize().then((_) {
        if (mounted) {
          setState(() {});
          if (widget.isVisible) {
            _controller.play();
          }
          _controller.setLooping(true);
        }
      });
  }

  @override
  void didUpdateWidget(covariant VideoPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_controller.value.isInitialized) return;
    if (widget.isVisible && !oldWidget.isVisible) {
      _controller.play();
    } else if (!widget.isVisible && oldWidget.isVisible) {
      _controller.pause();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    if (_controller.value.isPlaying) {
      _controller.pause();
    } else {
      _controller.play();
    }
    setState(() {});
  }

  void _seek(Duration delta) {
    final pos = _controller.value.position + delta;
    final dur = _controller.value.duration;
    if (dur.inMilliseconds > 0) {
      final clamped = Duration(
        milliseconds: pos.inMilliseconds.clamp(0, dur.inMilliseconds),
      );
      _controller.seekTo(clamped);
    }
  }

  void _onDoubleTap(TapDownDetails details) {
    _lastDoubleTapPosition = details.localPosition;
  }

  void _handleDoubleTap(double width) {
    if (_lastDoubleTapPosition == null) return;
    if (_lastDoubleTapPosition!.dx < width / 2) {
      _seek(const Duration(seconds: -5));
    } else {
      _seek(const Duration(seconds: 5));
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    final aspectRatio = _controller.value.aspectRatio;
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        return Stack(
          alignment: Alignment.center,
          children: [
            // Centered video that fits inside the available space (portrait/landscape)
            Center(
              child: AspectRatio(
                aspectRatio: aspectRatio,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _togglePlayPause,
                  onDoubleTapDown: _onDoubleTap,
                  onDoubleTap: () => _handleDoubleTap(w),
                  child: VideoPlayer(_controller),
                ),
              ),
            ),
            if (widget.showProgressBar)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: VideoProgressIndicator(
                  _controller,
                  allowScrubbing: true,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
          ],
        );
      },
    );
  }
}
