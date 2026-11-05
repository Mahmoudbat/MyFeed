import 'package:flutter/material.dart';

import 'albums_screen.dart';
import 'asset_grid_screen.dart';
import 'reels_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  /// Tabs are built the first time they are opened, not all at launch.
  final Set<int> _visited = {0};

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const AssetGridScreen(title: 'Gallery'),
      ReelsScreen(active: _tab == 1),
      const AlbumsScreen(),
      const SettingsScreen(),
    ];
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [for (var i = 0; i < pages.length; i++) _visited.contains(i) ? pages[i] : const SizedBox()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() {
          _tab = i;
          _visited.add(i);
        }),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.video_library_outlined), selectedIcon: Icon(Icons.video_library), label: 'Reels'),
          NavigationDestination(icon: Icon(Icons.photo_album_outlined), selectedIcon: Icon(Icons.photo_album), label: 'Albums'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
