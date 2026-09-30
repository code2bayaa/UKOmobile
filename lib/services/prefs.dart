import 'package:shared_preferences/shared_preferences.dart';

/// AsyncStorage replacement. Key names are identical to the RN app.
class PrefKeys {
  PrefKeys._();
  static const user = 'user'; // signed-in user's email (a.k.a. userId)
  static const remote = 'remote'; // "on" | "off" — phone-as-TV-remote mode
  static const location = 'location'; // JSON reverse-geocode result (report.js)
  static const device = 'device'; // JSON device info (report.js)
  static const type = 'type'; // last stream type (collection.jsx)
  static const token = 'token'; // app token from sign-in, sent as Bearer on every /android call
}

class Prefs {
  Prefs._();
  static SharedPreferences? _p;

  static Future<SharedPreferences> get instance async => _p ??= await SharedPreferences.getInstance();

  static Future<String?> getItem(String key) async => (await instance).getString(key);

  static Future<void> setItem(String key, String value) async => (await instance).setString(key, value);

  static Future<void> removeItem(String key) async => (await instance).remove(key);

  static Future<String?> get user => getItem(PrefKeys.user);

  static Future<String?> get token => getItem(PrefKeys.token);
}
