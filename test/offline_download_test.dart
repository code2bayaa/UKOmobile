// ignore_for_file: depend_on_referenced_packages - path_provider / plugin platform interfaces come with path_provider
// OfflineStore.downloadFile against a local HTTP server (movies PRD #9): complete files land, error pages,
// refused and cut-off downloads return null and leave nothing behind.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:uko_mobile/screens/offline/file_system.dart';

class _FakePaths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePaths(this.dir);
  final String dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

void main() {
  late Directory tmp;
  late HttpServer server;
  late String base;
  final video = List<int>.generate(50000, (i) => i % 251);

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('uko_offline_test');
    PathProviderPlatform.instance = _FakePaths(tmp.path);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((req) async {
      final r = req.response;
      switch (req.uri.path) {
        case '/video':
          r.headers.contentType = ContentType('video', 'mp4');
          r.contentLength = video.length;
          r.add(video);
        case '/octet':
          r.headers.contentType = ContentType('application', 'octet-stream');
          r.add(video);
        case '/error-page':
          r.headers.contentType = ContentType.json;
          r.write('{"error":"not found"}');
        case '/forbidden':
          r.statusCode = 403;
          r.write('ticket not paid');
        case '/empty':
          r.headers.contentType = ContentType('video', 'mp4');
        case '/subtitle':
          r.headers.contentType = ContentType('text', 'vtt');
          r.write('WEBVTT\n\n00:00.000 --> 00:01.000\nhi\n');
      }
      await r.close();
    });
  });

  tearDownAll(() async {
    await server.close(force: true);
    await tmp.delete(recursive: true);
  });

  Future<List<String>> leftovers() async => (await Directory(await OfflineStore.videoDir).list().toList())
      .map((e) => e.path.split(Platform.pathSeparator).last)
      .toList();

  test('a complete video lands at its path, with progress', () async {
    final seen = <int>[];
    final path = await OfflineStore.downloadFile('video', '$base/video', 'm1', format: 'mp4', onProgress: seen.add);
    expect(path, isNotNull);
    expect(await File(path!).length(), video.length);
    expect(seen.last, 100);
    expect(await leftovers(), isNot(contains('m1.mp4.part')));
  });

  test('octet-stream with no extension is still a video', () async {
    final path = await OfflineStore.downloadFile('video', '$base/octet', 'm2', format: 'mp4');
    expect(path, isNotNull);
  });

  test('an error page, a refusal and an empty body return null and leave no file', () async {
    expect(await OfflineStore.downloadFile('video', '$base/error-page', 'm3', format: 'mp4'), isNull);
    expect(await OfflineStore.downloadFile('video', '$base/forbidden', 'm4', format: 'mp4'), isNull);
    expect(await OfflineStore.downloadFile('video', '$base/empty', 'm5', format: 'mp4'), isNull);
    final files = await leftovers();
    for (final name in ['m3', 'm4', 'm5']) {
      expect(files.where((f) => f.startsWith(name)), isEmpty, reason: name);
    }
  });

  test('subtitles are not held to the video content-type check', () async {
    final path = await OfflineStore.downloadFile('subtitle', '$base/subtitle', 'm1');
    expect(path, isNotNull);
    expect(await File(path!).readAsString(), startsWith('WEBVTT'));
  });
}
