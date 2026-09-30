import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../services/prefs.dart';

/// Thin `fetch` replacement. The RN code never checks `response.ok`, it just
/// calls `.json()`; these helpers do the same but return `null` instead of
/// throwing on network / JSON errors so ports stay simple.
class Http {
  Http._();
  static final http.Client _client = http.Client();

  static const jsonHeaders = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  static Future<dynamic> getJson(String url, {Map<String, String>? headers}) async {
    if (url.isEmpty) return null;
    try {
      final res = await _client.get(Uri.parse(url), headers: await _headersFor(url, headers));
      return await _keep(url, _decode(res, url));
    } catch (e) {
      debugPrint('GET $url failed: $e');
      return null;
    }
  }

  static Future<dynamic> postJson(String url, Object? body, {Map<String, String>? headers}) async {
    if (url.isEmpty) {
      debugPrint('POST skipped: empty url (missing --dart-define?)');
      return null;
    }
    try {
      final res = await _client.post(
        Uri.parse(url),
        headers: await _headersFor(url, headers ?? jsonHeaders),
        body: body is String ? body : jsonEncode(body),
      );
      return await _keep(url, _decode(res, url));
    } catch (e) {
      debugPrint('POST $url failed: $e');
      return null;
    }
  }

  /// Raw response when the caller needs status codes / headers.
  static Future<http.Response?> post(String url, Object? body, {Map<String, String>? headers}) async {
    if (url.isEmpty) return null;
    try {
      return await _client.post(Uri.parse(url),
          headers: await _headersFor(url, headers ?? jsonHeaders), body: body is String ? body : jsonEncode(body));
    } catch (e) {
      debugPrint('POST $url failed: $e');
      return null;
    }
  }

  /// Raw GET response when the caller needs status codes / headers.
  static Future<http.Response?> getRaw(String url, {Map<String, String>? headers}) async {
    if (url.isEmpty) return null;
    try {
      return await _client.get(Uri.parse(url), headers: await _headersFor(url, headers));
    } catch (e) {
      debugPrint('GET $url failed: $e');
      return null;
    }
  }

  /// The account routes (…/android and the TV link) run on the app token from sign-in, sent as
  /// Bearer - the server ignores any email in the body for them.
  static bool _needsToken(String url) => url.contains('/android') || url.contains('/user/tv/');

  /// Which app signed in / out (users.verification.apps); the body's "mobile" does not say.
  static Map<String, String> get _platform => kIsWeb
      ? const {}
      : {'X-Platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android'};

  static Future<Map<String, String>?> _headersFor(String url, Map<String, String>? headers) async {
    if (!_needsToken(url)) return headers;
    final token = await Prefs.token;
    if (token == null || token.isEmpty) return {...?headers, ..._platform};
    return {...?headers, ..._platform, 'Authorization': 'Bearer $token'};
  }

  /// sign-in and /authentication/android hand back a token - keep the newest so an app in use
  /// never reaches the 90-day expiry
  static Future<dynamic> _keep(String url, dynamic data) async {
    if (_needsToken(url) && data is Map) {
      final token = data['token'];
      if (token is String && token.isNotEmpty) await Prefs.setItem(PrefKeys.token, token);
    }
    return data;
  }

  static dynamic _decode(http.Response res, String url) {
    try {
      return jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      final body = res.body;
      debugPrint('Invalid JSON (status=${res.statusCode}) from $url: '
          '${body.length > 200 ? body.substring(0, 200) : body}');
      return null;
    }
  }
}
