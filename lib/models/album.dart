
import 'dart:io';

class Album {
  final String name;
  final List<File> files;
  final bool isDeletable;

  Album({required this.name, this.files = const [], this.isDeletable = false});

  // From JSON for loading custom albums
  factory Album.fromJson(Map<String, dynamic> json, List<File> allFiles) {
    final filePaths = List<String>.from(json['files'] ?? []);
    final files = filePaths.map((path) => allFiles.firstWhere((f) => f.path == path, orElse: () => File(path))) // Graceful handling of missing files
        .where((f) => f.existsSync()).toList();
    return Album(name: json['name'], files: files, isDeletable: true);
  }

  // To JSON for saving custom albums
  Map<String, dynamic> toJson() => {
        'name': name,
        'files': files.map((f) => f.path).toList(),
      };
}
