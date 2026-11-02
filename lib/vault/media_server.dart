import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'chunked_cipher.dart';
import 'vault_store.dart';

/// Serves decrypted vault media to the video player over a loopback-only
/// HTTP socket, with HTTP Range support so playback and seeking decrypt only
/// the chunks that are actually needed. Plaintext never touches the disk.
///
/// The server listens on 127.0.0.1 only and every URL carries a random
/// 256-bit token, so other apps on the device cannot fetch content.
class VaultMediaServer {
  VaultMediaServer(this._store);

  final VaultStore _store;
  HttpServer? _server;
  String _token = '';
  Future<void>? _starting;

  bool get isRunning => _server != null;

  Future<void> start() {
    if (_server != null) return Future.value();
    return _starting ??= _start().whenComplete(() => _starting = null);
  }

  Future<void> _start() async {
    final random = Random.secure();
    _token = List.generate(32, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0, shared: false);
    server.autoCompress = false;
    _server = server;
    server.listen(_handle, onError: (Object e) => debugPrint('media server: $e'));
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _token = '';
    await server?.close(force: true);
  }

  /// URL for playing [itemId]. Call [start] first.
  Uri urlFor(String itemId) {
    final server = _server;
    if (server == null) throw StateError('media server not running');
    final ext = _store.itemById(itemId)?.extension ?? '';
    return Uri.parse('http://127.0.0.1:${server.port}/$_token/$itemId$ext');
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    EncryptedFileReader? reader;
    try {
      final segments = request.uri.pathSegments;
      if (_token.isEmpty || segments.length != 2 || segments[0] != _token) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
        return;
      }
      final id = segments[1].split('.').first;
      final item = _store.isUnlocked ? _store.itemById(id) : null;
      if (item == null) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      reader = await _store.openReader(id);
      final length = reader.length;
      final range = parseRange(request.headers.value(HttpHeaders.rangeHeader), length);

      response.headers
        ..contentType = ContentType.parse(item.mimeType)
        ..set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..set(HttpHeaders.cacheControlHeader, 'no-store');

      int start = 0, end = length; // [start, end)
      if (range == RangeResult.unsatisfiable) {
        response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$length');
        return;
      } else if (range != null) {
        start = range.start;
        end = range.end;
        response.statusCode = HttpStatus.partialContent;
        response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-${end - 1}/$length');
      } else {
        response.statusCode = HttpStatus.ok;
      }
      response.contentLength = end - start;
      if (request.method == 'GET' && end > start) {
        await response.addStream(reader.read(start, end));
      }
    } catch (e) {
      // Usually the player closing a connection mid-stream while seeking.
      debugPrint('media server request failed: $e');
      try {
        response.statusCode = HttpStatus.internalServerError;
      } catch (_) {}
    } finally {
      try {
        await reader?.close();
      } catch (e) {
        debugPrint('media server: closing reader failed: $e');
      }
      try {
        await response.close();
      } catch (_) {}
    }
  }

  /// Parses a single `bytes=` range. Returns null for "no/ignored range",
  /// [RangeResult.unsatisfiable] when it cannot be served.
  @visibleForTesting
  static RangeResult? parseRange(String? header, int length) {
    if (header == null) return null;
    final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header.trim());
    if (match == null) return null; // multi-range or malformed: serve everything
    final first = match.group(1)!;
    final last = match.group(2)!;
    if (first.isEmpty && last.isEmpty) return null;
    if (first.isEmpty) {
      final suffix = int.parse(last);
      if (suffix == 0) return RangeResult.unsatisfiable;
      return RangeResult(max(0, length - suffix), length);
    }
    final start = int.parse(first);
    if (start >= length) return RangeResult.unsatisfiable;
    final end = last.isEmpty ? length : min(int.parse(last) + 1, length);
    if (end <= start) return RangeResult.unsatisfiable;
    return RangeResult(start, end);
  }
}

class RangeResult {
  const RangeResult(this.start, this.end);
  final int start;
  final int end;

  static const unsatisfiable = RangeResult(-1, -1);

  @override
  bool operator ==(Object other) => other is RangeResult && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'RangeResult($start, $end)';
}
