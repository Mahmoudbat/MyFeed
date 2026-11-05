import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../services/gallery_service.dart';
import 'asset_grid_screen.dart';

/// Vertical, shuffled feed of every video on the device.
///
/// Only a shuffled list of indices is kept in memory; each page fetches its
/// own asset, so there is no cap on library size.
class ReelsScreen extends StatefulWidget {
  const ReelsScreen({super.key, required this.active});

  /// Whether the Reels tab is visible (videos pause otherwise).
  final bool active;

  @override
  State<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends State<ReelsScreen> {
  final _gallery = GalleryService.instance;
  final PageController _controller = PageController();
  AssetPathEntity? _path;
  List<int> _order = [];
  int _current = 0;
  bool _loading = true;
  bool _permission = true;

  @override
  void initState() {
    super.initState();
    _gallery.changes.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    _gallery.changes.removeListener(_load);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load({bool reshuffle = false}) async {
    if (!await _gallery.ensurePermission()) {
      if (mounted) {
        setState(() {
          _permission = false;
          _loading = false;
        });
      }
      return;
    }
    final path = await _gallery.allMedia(type: RequestType.video);
    final count = path == null ? 0 : await path.assetCountAsync;
    if (!mounted) return;
    setState(() {
      _permission = true;
      _path = path;
      // Keep the current order when the library changes, unless asked to reshuffle.
      if (reshuffle || _order.length != count) {
        _order = List<int>.generate(count, (i) => i)..shuffle();
        _current = 0;
        if (_controller.hasClients) _controller.jumpToPage(0);
      }
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: landscape
          ? null
          : AppBar(
              title: const Text('Reels'),
              backgroundColor: Colors.transparent,
              actions: [
                IconButton(tooltip: 'Shuffle', icon: const Icon(Icons.shuffle), onPressed: () => _load(reshuffle: true)),
              ],
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !_permission
              ? PermissionPrompt(onRetry: () async {
                  await _gallery.ensurePermission(force: true);
                  _load();
                })
              : _order.isEmpty
                  ? const Center(child: Text('No videos found in your gallery.', style: TextStyle(color: Colors.white70)))
                  : PageView.builder(
                      controller: _controller,
                      scrollDirection: Axis.vertical,
                      itemCount: _order.length,
                      onPageChanged: (i) => setState(() => _current = i),
                      itemBuilder: (context, i) => _ReelPage(
                        key: ValueKey('${_path?.id}-${_order[i]}'),
                        path: _path!,
                        index: _order[i],
                        active: widget.active && i == _current,
                        showCaption: !landscape,
                      ),
                    ),
    );
  }
}

class _ReelPage extends StatefulWidget {
  const _ReelPage({super.key, required this.path, required this.index, required this.active, required this.showCaption});

  final AssetPathEntity path;
  final int index;
  final bool active;
  final bool showCaption;

  @override
  State<_ReelPage> createState() => _ReelPageState();
}

class _ReelPageState extends State<_ReelPage> {
  late final Future<AssetEntity?> _asset = widget.path
      .getAssetListRange(start: widget.index, end: widget.index + 1)
      .then((list) => list.isEmpty ? null : list.first);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AssetEntity?>(
      future: _asset,
      builder: (context, snapshot) {
        final asset = snapshot.data;
        if (asset == null) {
          return snapshot.connectionState == ConnectionState.done
              ? const Center(child: Icon(Icons.error_outline, color: Colors.white54))
              : const Center(child: CircularProgressIndicator());
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            AssetPage(asset: asset, active: widget.active, compact: true),
            if (widget.showCaption)
              Positioned(
                left: 16,
                right: 16,
                bottom: 24,
                child: IgnorePointer(
                  child: Text(
                    asset.title ?? 'Video',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, shadows: [
                      Shadow(blurRadius: 6, color: Colors.black),
                    ]),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
