import 'package:flutter/material.dart';
import 'locked_home_screen.dart';
import 'locked_reels_screen.dart';
import 'locked_albums_screen.dart';

class LockedGalleryScreen extends StatefulWidget {
  const LockedGalleryScreen({super.key});

  @override
  State<LockedGalleryScreen> createState() => _LockedGalleryScreenState();
}

class _LockedGalleryScreenState extends State<LockedGalleryScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      LockedHomeScreen(selectedTabIndex: _currentIndex),
      LockedReelsScreen(selectedTabIndex: _currentIndex),
      const LockedAlbumsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        backgroundColor: Colors.black,
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.grey[600],
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.video_library),
            label: 'Reels',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.photo_album),
            label: 'Albums',
          ),
        ],
      ),
    );
  }
}
