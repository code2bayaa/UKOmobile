import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'prefs.dart';

/// Earn / buy credits are only offered in Kenya, Brazil and Oceania, matching useCreditRegion()
/// in the web-app. Matched on ISO codes, since place names are localised.
const kCreditCountryCodes = <String>{
  'KE', 'BR',
  // Oceania
  'AU', 'NZ', 'FJ', 'PG', 'SB', 'VU', 'NC', 'PF', 'WS', 'TO', 'KI', 'TV', 'NR', 'PW', 'FM', 'MH', 'CK', 'NU',
};

/// True when the reverse-geocode runLocale() already cached in "location" is in a
/// [kCreditCountryCodes] country. Never prompts for GPS.
Future<bool> creditsAllowedHere() async {
  try {
    final stored = await Prefs.getItem(PrefKeys.location);
    if (stored == null || stored.isEmpty) return false;
    final location = jsonDecode(stored);
    final first = location is List && location.isNotEmpty && location[0] is Map ? location[0] as Map : null;
    final code = '${first?['isoCountryCode'] ?? ''}'.toUpperCase();
    return kCreditCountryCodes.contains(code);
  } catch (e) {
    debugPrint('$e credit region error');
    return false;
  }
}
