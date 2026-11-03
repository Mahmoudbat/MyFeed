import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../util/format.dart';

typedef VideoControllerFactory = Future<VideoPlayerController> Function();

/// The single video player used everywhere (gallery viewer, reels, locked
/// gallery).
///
/// * Plays only while [active] is true and the app is in the foreground, so
///   swiping away or switching tabs/apps always pauses playback.
/// * [compact] gives the reels layout (tap = play/pause, thin progress bar);
///   otherwise full controls with ±10 s, scrubbing and a fullscreen toggle.
/// * Leaving fullscreen restores the system's orientation preferences
///   instead of forcing portrait.
class VideoView extends StatefulWidget {
  const VideoView({
    super.key,
    required this.createController,
    this.active = true,
    this.compact = false,
    this.looping = true,
  });

  final VideoControllerFactory createController;
  final bool active;
  final bool compact;
  final bool looping;

  @override
  State<VideoView> createState() => _VideoViewState();
}

class _VideoViewState extends State<VideoView> with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  Object? _error;
  bool _showControls = true;
  bool _fullscreen = false;
  bool _appVisible = true;
  bool _userPaused = false;
  Timer? _hideTimer;
  Offset? _doubleTapPosition;

  bool get _shouldPlay => widget.active && _appVisible && !_userPaused;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    try {
      final controller = await widget.createController();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      await controller.setLooping(widget.looping);
      setState(() => _controller = controller);
      _syncPlayback();
      _scheduleHide();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void didUpdateWidget(covariant VideoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      if (widget.active) _userPaused = false;
      _syncPlayback();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appVisible = state == AppLifecycleState.resumed;
    _syncPlayback();
  }

  void _syncPlayback() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (_shouldPlay && !controller.value.isPlaying) {
      controller.play();
    } else if (!_shouldPlay && controller.value.isPlaying) {
      controller.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    if (_fullscreen) _restoreSystemUi();
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final controller = _controller;
    if (controller == null) return;
    _userPaused = controller.value.isPlaying;
    _syncPlayback();
    _showControlsNow();
  }

  void _seekBy(Duration delta) {
    final controller = _controller;
    if (controller == null) return;
    final duration = controller.value.duration;
    var target = controller.value.position + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (target > duration) target = duration;
    controller.seekTo(target);
    _showControlsNow();
  }

  void _onDoubleTap() {
    final width = context.size?.width ?? 0;
    final x = _doubleTapPosition?.dx ?? width;
    _seekBy(Duration(seconds: x < width / 2 ? -10 : 10));
  }

  void _showControlsNow() {
    if (!mounted) return;
    setState(() => _showControls = true);
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (widget.compact) return;
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && (_controller?.value.isPlaying ?? false)) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleFullscreen() {
    setState(() => _fullscreen = !_fullscreen);
    if (_fullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      final aspect = _controller?.value.aspectRatio ?? 1;
      SystemChrome.setPreferredOrientations(aspect >= 1
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : [DeviceOrientation.portraitUp]);
    } else {
      _restoreSystemUi();
    }
    _showControlsNow();
  }

  static void _restoreSystemUi() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(const []); // back to system default
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: Colors.white54, size: 48),
            SizedBox(height: 8),
            Text("This video can't be played", style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }
    final controller = _controller;
    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final video = Center(
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: VideoPlayer(controller),
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.compact
          ? _togglePlay
          : () {
              setState(() => _showControls = !_showControls);
              if (_showControls) _scheduleHide();
            },
      onDoubleTapDown: (d) => _doubleTapPosition = d.localPosition,
      onDoubleTap: _onDoubleTap,
      child: ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          return Stack(
            fit: StackFit.expand,
            children: [
              video,
              if (widget.compact) ...[
                if (!value.isPlaying)
                  const IgnorePointer(
                    child: Center(child: Icon(Icons.play_arrow, color: Colors.white70, size: 72)),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: VideoProgressIndicator(
                    controller,
                    allowScrubbing: true,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                  ),
                ),
              ] else
                AnimatedOpacity(
                  opacity: _showControls ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: IgnorePointer(
                    ignoring: !_showControls,
                    child: _FullControls(
                      controller: controller,
                      value: value,
                      fullscreen: _fullscreen,
                      onTogglePlay: _togglePlay,
                      onSeek: _seekBy,
                      onToggleFullscreen: _toggleFullscreen,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _FullControls extends StatelessWidget {
  const _FullControls({
    required this.controller,
    required this.value,
    required this.fullscreen,
    required this.onTogglePlay,
    required this.onSeek,
    required this.onToggleFullscreen,
  });

  final VideoPlayerController controller;
  final VideoPlayerValue value;
  final bool fullscreen;
  final VoidCallback onTogglePlay;
  final void Function(Duration) onSeek;
  final VoidCallback onToggleFullscreen;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black26,
      child: Stack(
        children: [
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Back 10 seconds',
                  icon: const Icon(Icons.replay_10, color: Colors.white, size: 40),
                  onPressed: () => onSeek(const Duration(seconds: -10)),
                ),
                const SizedBox(width: 24),
                IconButton(
                  tooltip: value.isPlaying ? 'Pause' : 'Play',
                  icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 56),
                  onPressed: onTogglePlay,
                ),
                const SizedBox(width: 24),
                IconButton(
                  tooltip: 'Forward 10 seconds',
                  icon: const Icon(Icons.forward_10, color: Colors.white, size: 40),
                  onPressed: () => onSeek(const Duration(seconds: 10)),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  VideoProgressIndicator(
                    controller,
                    allowScrubbing: true,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    colors: const VideoProgressColors(
                      playedColor: Colors.white,
                      bufferedColor: Colors.white24,
                      backgroundColor: Colors.white10,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Text(
                          '${formatDuration(value.position)} / ${formatDuration(value.duration)}',
                          style: const TextStyle(color: Colors.white),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: fullscreen ? 'Exit fullscreen' : 'Fullscreen',
                          icon: Icon(fullscreen ? Icons.fullscreen_exit : Icons.fullscreen, color: Colors.white),
                          onPressed: onToggleFullscreen,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
