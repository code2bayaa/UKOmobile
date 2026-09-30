// The user service's /sales routes (movies PRD #10 - selling downloaded videos phone to phone).
// Every call runs on the app token (core/http.dart adds it to …/android URLs).
import 'dart:convert';
import 'dart:math';

import '../core/env.dart';
import '../core/http.dart';

class SalesApi {
  SalesApi._();

  static Map<String, dynamic> _fail(String message) => {'status': false, 'message': message};

  static Future<Map<String, dynamic>> _send(String path, {Map<String, dynamic>? body}) async {
    final url = Api.sales(path);
    if (url.isEmpty) return _fail('Selling is not set up in this build');
    final res = body == null ? await Http.getRaw(url) : await Http.post(url, body);
    if (res == null) return _fail('No connection - check your internet');
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return _fail('Unexpected answer from UKO (${res.statusCode})');
  }

  /// seller: put a downloaded video on offer -> {status, offer:{code, price, name, ...}, seller_share}
  static Future<Map<String, dynamic>> offer({
    required String titleId,
    required String titleType,
    required bool eden,
    required String name,
    required int price,
    int? fileSize,
  }) =>
      _send('offer', body: {
        'title_id': titleId,
        'title_type': titleType,
        'eden': eden,
        'name': name,
        'price': price,
        'file_size': fileSize,
      });

  static Future<Map<String, dynamic>> close(String code) => _send('offer/close', body: {'code': code});

  /// seller: may the phone that presented [ticket] have this offer's file?
  static Future<Map<String, dynamic>> verify(String code, String ticket) =>
      _send('verify', body: {'code': code, 'ticket': ticket});

  /// buyer: what is on offer (price and seller come from UKO, not from the seller's phone)
  static Future<Map<String, dynamic>> view(String code) => _send('offer/view', body: {'code': code});

  /// buyer: M-PESA prompt on [phone] -> {status, state, sale_id, ticket?, message}
  static Future<Map<String, dynamic>> pay(String code, String phone) =>
      _send('pay', body: {'code': code, 'phone': phone, 'socket_key': socketKey()});

  /// buyer: {state: pending|paid|failed, ticket?}
  static Future<Map<String, dynamic>> confirm(int saleId) => _send('confirm', body: {'sale_id': saleId});

  static Future<Map<String, dynamic>> delivered(int saleId) => _send('delivered', body: {'sale_id': saleId});

  /// seller: balance, sales and withdrawals
  static Future<Map<String, dynamic>> wallet() => _send('wallet');

  static Future<Map<String, dynamic>> withdraw(int amount) =>
      _send('withdraw', body: {'amount': amount, 'socket_key': socketKey()});

  static Future<Map<String, dynamic>> withdrawal(int id) => _send('withdraw/$id');

  /// a random room key for the M-PESA result relay
  static String socketKey() {
    final r = Random.secure();
    return List.generate(32, (_) => r.nextInt(16).toRadixString(16)).join();
  }
}
