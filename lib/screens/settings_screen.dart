
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsService _settingsService = SettingsService();
  bool _deleteAfterImport = false;
  bool _deleteAfterExport = false;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _deleteAfterImport = await _settingsService.getDeleteAfterImport();
    _deleteAfterExport = await _settingsService.getDeleteAfterExport();
    setState(() {});
  }

  Future<void> _exportAllMedia() async {
    // 1. Ask the user to pick a directory
    final String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

    if (selectedDirectory == null) {
      // User canceled the picker
      return;
    }

    setState(() => _isExporting = true);

    final Directory appDir = await getApplicationDocumentsDirectory();
    final List<File> files = appDir.listSync().whereType<File>().toList();

    // 2. Copy each file to the selected directory
    for (final file in files) {
      final String fileName = path.basename(file.path);
      final String newPath = path.join(selectedDirectory, fileName);
      await file.copy(newPath);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export complete to $selectedDirectory'),
          backgroundColor: Colors.green,
        ),
      );
    }

    if (_deleteAfterExport) {
      _clearVault();
    }

    setState(() => _isExporting = false);
  }

  Future<void> _clearVault() async {
    final Directory appDir = await getApplicationDocumentsDirectory();
    final List<FileSystemEntity> entities = appDir.listSync().whereType<File>().toList();
    for (final FileSystemEntity entity in entities) {
      if (entity is File) {
        await entity.delete();
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vault has been cleared!'), backgroundColor: Colors.green),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        centerTitle: true,
        backgroundColor: Colors.black,
      ),
      body: _isExporting
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Exporting media...'),
                ],
              ),
            )
          : ListView(
              children: [
                SwitchListTile(
                  title: const Text('Delete after importing'),
                  subtitle: const Text('Automatically delete from public gallery after import'),
                  value: _deleteAfterImport,
                  onChanged: (value) {
                    setState(() => _deleteAfterImport = value);
                    _settingsService.setDeleteAfterImport(value);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.folder_open),
                  title: const Text('Export all media'),
                  subtitle: const Text('Copy all media to a selected folder'),
                  onTap: _exportAllMedia,
                ),
                SwitchListTile(
                  title: const Text('Delete after exporting'),
                  subtitle: const Text('Automatically clear vault after exporting'),
                  value: _deleteAfterExport,
                  onChanged: (value) {
                    setState(() => _deleteAfterExport = value);
                    _settingsService.setDeleteAfterExport(value);
                  },
                ),
                 ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.red),
                  title: const Text('Clear Vault'),
                  subtitle: const Text('Delete all media from the app', style: TextStyle(color: Colors.redAccent)),
                  onTap: _showClearVaultConfirmation,
                ),
              ],
            ),
    );
  }

  void _showClearVaultConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Vault?'),
        content: const Text(
            'This will permanently delete all photos and videos from your private vault. This action cannot be undone.'),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          TextButton(
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
            onPressed: () {
              Navigator.of(context).pop();
              _clearVault();
            },
          ),
        ],
      ),
    );
  }
}
