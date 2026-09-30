// Port of mobile/middleware/fileSystem.js (expo-file-system/legacy).
//
// Layout (identical to RN, rooted at the app documents directory):
//   <documents>/video-store/videos/<id>.<format>
//   <documents>/video-store/subtitles/<id>.vtt
//   <documents>/video-store/images/<id>.jpg
//   <documents>/video-store/index.json   { "<id>": {id, name, video, subtitle, image, data, downloadedAt} }
//
// Differences from RN: paths stored in index.json are absolute file-system
// paths (RN stored `file://...` URIs from FileSystem.documentDirectory).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class OfflineStore {
  OfflineStore._();

  static Future<String> _root() async {
    final docs = await getApplicationDocumentsDirectory();
    return '${docs.path}${Platform.pathSeparator}video-store${Platform.pathSeparator}';
  }

  static Future<String> get videoDir async => '${await _root()}videos${Platform.pathSeparator}';
  static Future<String> get subDir async => '${await _root()}subtitles${Platform.pathSeparator}';
  static Future<String> get imgDir async => '${await _root()}images${Platform.pathSeparator}';
  static Future<File> get _indexFile async => File('${await _root()}index.json');

  static Future<void> _ensureDir(String path) async {
    final d = Directory(path);
    if (!await d.exists()) await d.create(recursive: true);
  }

  /// `downloadFile(type, url, path, onProgress, format)`. [type] is
  /// "video" | "subtitle" | anything else (image). Returns the saved file path,
  /// or null when the server did not answer 200 (RN returned `false`).
  static Future<String?> downloadFile(
    String type,
    String url,
    String path, {
    void Function(int percent)? onProgress,
    String? format,
  }) async {
    final dir = type == 'video'
        ? await videoDir
        : type == 'subtitle'
            ? await subDir
            : await imgDir;
    final destPath = type == 'video'
        ? '$dir$path.$format'
        : type == 'subtitle'
            ? '$dir$path.vtt'
            : '$dir$path.jpg';
    await _ensureDir(dir);

    // written to <dest>.part and moved into place only when complete, so a cut-off download never
    // replaces a good file or lands in Downloads as a broken video (movies PRD #9)
    final client = http.Client();
    final file = File('$destPath.part');
    try {
      final res = await client.send(http.Request('GET', Uri.parse(url)));
      if (res.statusCode != 200) {
        await res.stream.drain<void>();
        return null;
      }
      // a video URL that answers with a JSON / HTML / text error page is not a video (any video/* or binary type is)
      final contentType = (res.headers['content-type'] ?? '').toLowerCase();
      if (type == 'video' && RegExp(r'^(application/json|text/)').hasMatch(contentType)) {
        await res.stream.drain<void>();
        debugPrint('downloadFile: $url answered $contentType, not a video');
        return null;
      }
      final total = res.contentLength ?? 0;
      var written = 0;
      var lastPercent = -1;
      final sink = file.openWrite();
      try {
        await for (final chunk in res.stream) {
          sink.add(chunk);
          written += chunk.length;
          if (total > 0 && onProgress != null) {
            final percent = ((written / total) * 100).round();
            if (percent != lastPercent) {
              lastPercent = percent;
              onProgress(percent);
            }
          }
        }
      } finally {
        await sink.flush();
        await sink.close();
      }
      // the connection ended early without an error: shorter than the server said, or nothing at all
      if ((total > 0 && written < total) || written == 0) {
        debugPrint('downloadFile: $url stopped at $written of $total bytes');
        if (await file.exists()) await file.delete();
        return null;
      }
      final dest = File(destPath);
      if (await dest.exists()) await dest.delete();
      await file.rename(destPath);
      debugPrint('downloadFile result $destPath ($written bytes)');
      return destPath;
    } catch (e) {
      debugPrint('downloadFile error $url: $e');
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
      rethrow;
    } finally {
      client.close();
    }
  }

  /// `getDB()`: creates the folders and an empty index.json.
  static Future<bool> getDB() async {
    await _ensureDir(await _root());
    await _ensureDir(await videoDir);
    await _ensureDir(await subDir);
    await _ensureDir(await imgDir);
    final index = await _indexFile;
    if (!await index.exists()) await index.writeAsString(jsonEncode({}));
    return true;
  }

  static Future<Map<String, dynamic>> _readIndex() async {
    await getDB();
    final raw = await (await _indexFile).readAsString();
    final decoded = jsonDecode(raw);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
  }

  static Future<void> _writeIndex(Map<String, dynamic> index) async {
    await (await _indexFile).writeAsString(const JsonEncoder.withIndent('  ').convert(index));
  }

  /// `saveVideo(videoUri, subtitleUri, imageUri, data, name, format)` ->
  /// `{status: true}` or `{status: false, error}`.
  static Future<({bool status, String? error})> saveVideo(
    String? videoUri,
    String? subtitleUri,
    String? imageUri,
    dynamic data,
    String name,
    String format,
  ) async {
    try {
      await getDB();
      final videoPath = '${await videoDir}$name.$format';
      final subtitlePath = subtitleUri != null ? '${await subDir}$name.vtt' : null;
      final imagePath = imageUri != null ? '${await imgDir}$name.jpg' : null;

      final index = await _readIndex();
      index[name] = {
        'id': name,
        'name': name,
        'video': videoPath,
        'subtitle': subtitlePath,
        'image': imagePath,
        'data': data,
        'downloadedAt': DateTime.now().millisecondsSinceEpoch,
      };
      await _writeIndex(index);
      return (status: true, error: null);
    } catch (e) {
      debugPrint('saveVideo error $e');
      return (status: false, error: '$e');
    }
  }

  static Future<Map<String, dynamic>?> getVideoRecord(String key) async {
    final index = await _readIndex();
    final r = index[key];
    return r is Map ? Map<String, dynamic>.from(r) : null;
  }

  static Future<void> deleteVideo(String key) async {
    final index = await _readIndex();
    final record = index[key];
    if (record is! Map) return;
    for (final k in const ['video', 'subtitle', 'image']) {
      final p = record[k];
      if (p is String && p.isNotEmpty) {
        final f = File(p);
        if (await f.exists()) await f.delete();
      }
    }
    index.remove(key);
    await _writeIndex(index);
  }

  static Future<List<String>> listVideoKeys() async => (await _readIndex()).keys.toList();

  /// bytes in the file at [path], or null when it is missing (a sale states the size it offers)
  static Future<int?> fileSize(String path) async {
    final f = File(path);
    return await f.exists() ? f.length() : null;
  }

  static Future<List<Map<String, dynamic>>> listVideos() async {
    final index = await _readIndex();
    return index.values.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }
}
