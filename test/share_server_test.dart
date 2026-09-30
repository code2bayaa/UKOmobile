// The seller's local server for phone-to-phone sales (movies PRD #10): it describes the offer and the poster to
// anyone on the network, but never sends the video or subtitles without a ticket UKO confirms is paid.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:uko_mobile/services/share_server.dart';

void main() {
  late Directory dir;
  late ShareServer server;
  late HttpClient client;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('uko-sale-test');
    final video = File('${dir.path}/550.mp4')..writeAsBytesSync(List<int>.filled(4096, 7));
    final image = File('${dir.path}/550.jpg')..writeAsBytesSync([1, 2, 3]);
    server = ShareServer(
      code: 'ABCD1234',
      record: {'name': '550', 'video': video.path, 'image': image.path, 'subtitle': null, 'data': {'id': 550, 'title': 'Fight Club'}},
      onChange: () {},
    );
    await server.start();
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await server.stop();
    await dir.delete(recursive: true);
  });

  Future<(int, String)> get(String path) async {
    final req = await client.getUrl(Uri.parse('http://127.0.0.1:${server.port}$path'));
    final res = await req.close();
    return (res.statusCode, await res.transform(utf8.decoder).join());
  }

  test('describes the offer without the file', () async {
    final (status, body) = await get('/uko-sale/offer?code=ABCD1234');
    expect(status, 200);
    final j = jsonDecode(body) as Map;
    expect(j['size'], 4096);
    expect(j['format'], 'mp4');
    expect(j['has_image'], true);
    expect(j['has_subtitle'], false);
    expect((j['data'] as Map)['title'], 'Fight Club');
  });

  test('serves the poster', () async {
    final (status, _) = await get('/uko-sale/image?code=ABCD1234');
    expect(status, 200);
  });

  test('refuses the video without a paid ticket', () async {
    expect((await get('/uko-sale/video?code=ABCD1234')).$1, 403);
    expect((await get('/uko-sale/video?code=ABCD1234&ticket=made-up')).$1, 403);
    expect(server.transfers, isEmpty);
  });

  test('ignores another offer code', () async {
    expect((await get('/uko-sale/offer?code=OTHER999')).$1, 404);
    expect((await get('/uko-sale/video?code=OTHER999&ticket=x')).$1, 404);
  });

  test('lists this phone\'s local addresses without loopback', () async {
    final hosts = await ShareServer.localAddresses();
    expect(hosts.contains('127.0.0.1'), false);
  });
}
