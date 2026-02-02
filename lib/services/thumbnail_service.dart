
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

class ThumbnailService {
  Future<Directory> get _thumbnailDir async {
    final Directory appDir = await getApplicationDocumentsDirectory();
    final Directory thumbDir = Directory(path.join(appDir.path, '.thumbnails'));
    if (!await thumbDir.exists()) {
      await thumbDir.create();
    }
    return thumbDir;
  }

  Future<File> getThumbnailFile(File videoFile) async {
    final Directory thumbDir = await _thumbnailDir;
    final String videoFileName = path.basenameWithoutExtension(videoFile.path);
    return File(path.join(thumbDir.path, '$videoFileName.jpg'));
  }

  Future<Uint8List?> getThumbnail(File videoFile) async {
    final File thumbFile = await getThumbnailFile(videoFile);
    if (await thumbFile.exists()) {
      return await thumbFile.readAsBytes();
    }
    return null;
  }

  Future<File?> generateAndSaveThumbnail(File videoFile) async {
    final Uint8List? bytes = await VideoThumbnail.thumbnailData(
      video: videoFile.path,
      imageFormat: ImageFormat.JPEG,
      maxWidth: 300,
      quality: 75,
    );

    if (bytes != null) {
      final File thumbFile = await getThumbnailFile(videoFile);
      await thumbFile.writeAsBytes(bytes);
      return thumbFile;
    }
    return null;
  }
}
