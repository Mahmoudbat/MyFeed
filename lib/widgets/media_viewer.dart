import 'package:flutter/material.dart';

import '../services/app_settings.dart';

/// Full-screen pager shared by the gallery, album and locked-gallery viewers.
///
/// Pages are not kept alive, so only the visible page holds a decoded image
/// or video controller; [pageBuilder] receives `active` so that only the
/// current page plays video.
class MediaViewer<T> extends StatefulWidget {
  const MediaViewer({
    super.key,
    required this.items,
    required this.initialIndex,
    required this.pageBuilder,
    this.actionsBuilder,
  });

  final List<T> items;
  final int initialIndex;
  final Widget Function(BuildContext context, T item, bool active) pageBuilder;

  /// App-bar actions for the current item. Return value of an action may call
  /// [MediaViewerState.removeCurrent] after deleting/exporting the item.
  final List<Widget> Function(BuildContext context, T item, MediaViewerState<T> viewer)? actionsBuilder;

  @override
  State<MediaViewer<T>> createState() => MediaViewerState<T>();
}

class MediaViewerState<T> extends State<MediaViewer<T>> {
  late final List<T> _items = List.of(widget.items);
  late int _index = _items.isEmpty ? 0 : widget.initialIndex.clamp(0, _items.length - 1);
  late final PageController _controller = PageController(initialPage: _index);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Removes the current item (after it was deleted); closes when empty.
  void removeCurrent() {
    setState(() {
      _items.removeAt(_index);
      if (_index >= _items.length) _index = _items.length - 1;
    });
    if (_items.isEmpty) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const Scaffold(backgroundColor: Colors.black);
    final current = _items[_index];
    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) {
        final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
        return Scaffold(
          backgroundColor: Colors.black,
          extendBodyBehindAppBar: true,
          appBar: landscape
              ? null
              : AppBar(
                  backgroundColor: Colors.black38,
                  foregroundColor: Colors.white,
                  title: Text('${_index + 1} / ${_items.length}'),
                  actions: widget.actionsBuilder?.call(context, current, this),
                ),
          body: PageView.builder(
            controller: _controller,
            scrollDirection: AppSettings.instance.verticalScrolling ? Axis.vertical : Axis.horizontal,
            itemCount: _items.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) => KeyedSubtree(
              key: ValueKey(_items[i]),
              child: widget.pageBuilder(context, _items[i], i == _index),
            ),
          ),
        );
      },
    );
  }
}

/// Zoomable image page used by the viewers.
class ZoomableImage extends StatelessWidget {
  const ZoomableImage({super.key, required this.image});

  final ImageProvider image;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    // Decode at ~2x screen size: sharp when zoomed, without decoding 50 MP
    // originals at full resolution.
    final target = (size.longestSide * dpr * 2).round();
    return InteractiveViewer(
      maxScale: 5,
      child: Center(
        child: Image(
          image: ResizeImage(image, width: target, height: target, policy: ResizeImagePolicy.fit, allowUpscaling: false),
          fit: BoxFit.contain,
          gaplessPlayback: true,
          loadingBuilder: (context, child, progress) =>
              progress == null ? child : const Center(child: CircularProgressIndicator()),
          frameBuilder: (context, child, frame, sync) =>
              frame == null && !sync ? const Center(child: CircularProgressIndicator()) : child,
          errorBuilder: (context, error, stack) =>
              const Center(child: Icon(Icons.broken_image, color: Colors.white54, size: 72)),
        ),
      ),
    );
  }
}
