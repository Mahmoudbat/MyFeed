enum MediaKind { image, video }

/// A media file stored (encrypted) in the vault. All of this metadata lives
/// only inside the encrypted index; on disk the file is just `<random id>.mfv`.
class LockedItem {
  LockedItem({
    required this.id,
    required this.kind,
    required this.extension,
    required this.name,
    required this.size,
    required this.addedAt,
    this.createdAt,
    this.sourceId,
    this.durationSeconds = 0,
    this.width = 0,
    this.height = 0,
    this.hasThumbnail = false,
  });

  final String id;
  final MediaKind kind;

  /// Lower-case original extension including the dot, e.g. `.jpg`.
  final String extension;
  final String name;
  final int size;
  final DateTime addedAt;
  final DateTime? createdAt;

  /// Gallery asset id the item was imported from (used to skip duplicates).
  final String? sourceId;
  final int durationSeconds;
  final int width;
  final int height;
  final bool hasThumbnail;

  bool get isVideo => kind == MediaKind.video;

  String get mimeType => mimeTypeFor(extension, kind);

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind.name,
        'ext': extension,
        'name': name,
        'size': size,
        'added': addedAt.millisecondsSinceEpoch,
        'created': createdAt?.millisecondsSinceEpoch,
        'source': sourceId,
        'duration': durationSeconds,
        'w': width,
        'h': height,
        'thumb': hasThumbnail,
      };

  factory LockedItem.fromJson(Map<String, dynamic> json) => LockedItem(
        id: json['id'] as String,
        kind: MediaKind.values.byName(json['kind'] as String),
        extension: json['ext'] as String,
        name: json['name'] as String,
        size: json['size'] as int,
        addedAt: DateTime.fromMillisecondsSinceEpoch(json['added'] as int),
        createdAt: json['created'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(json['created'] as int),
        sourceId: json['source'] as String?,
        durationSeconds: json['duration'] as int? ?? 0,
        width: json['w'] as int? ?? 0,
        height: json['h'] as int? ?? 0,
        hasThumbnail: json['thumb'] as bool? ?? false,
      );
}

class LockedAlbum {
  LockedAlbum({
    required this.id,
    required this.name,
    required this.createdAt,
    List<String>? itemIds,
  }) : itemIds = itemIds ?? <String>[];

  final String id;
  String name;
  final DateTime createdAt;
  final List<String> itemIds;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'created': createdAt.millisecondsSinceEpoch,
        'items': itemIds,
      };

  factory LockedAlbum.fromJson(Map<String, dynamic> json) => LockedAlbum(
        id: json['id'] as String,
        name: json['name'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(json['created'] as int),
        itemIds: List<String>.from(json['items'] as List),
      );
}

const _videoExtensions = {
  '.mp4', '.m4v', '.mov', '.avi', '.mkv', '.webm', '.3gp', '.3g2', '.ts', '.mpg', '.mpeg', '.wmv', '.flv',
};

/// Best-effort media type detection from a file extension.
MediaKind kindForExtension(String extension) =>
    _videoExtensions.contains(extension.toLowerCase()) ? MediaKind.video : MediaKind.image;

String mimeTypeFor(String extension, MediaKind kind) {
  switch (extension.toLowerCase()) {
    case '.jpg':
    case '.jpeg':
      return 'image/jpeg';
    case '.png':
      return 'image/png';
    case '.gif':
      return 'image/gif';
    case '.webp':
      return 'image/webp';
    case '.heic':
      return 'image/heic';
    case '.heif':
      return 'image/heif';
    case '.bmp':
      return 'image/bmp';
    case '.mp4':
    case '.m4v':
      return 'video/mp4';
    case '.mov':
      return 'video/quicktime';
    case '.mkv':
      return 'video/x-matroska';
    case '.webm':
      return 'video/webm';
    case '.3gp':
      return 'video/3gpp';
    case '.3g2':
      return 'video/3gpp2';
    case '.avi':
      return 'video/x-msvideo';
    case '.ts':
      return 'video/mp2t';
    case '.mpg':
    case '.mpeg':
      return 'video/mpeg';
    default:
      return kind == MediaKind.video ? 'video/mp4' : 'image/jpeg';
  }
}
