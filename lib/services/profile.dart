import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../core/env.dart';
import '../core/http.dart';
import 'prefs.dart';

// Phone number + country / county / ward on the account (movies PRD #6, #21) and the play gate
// built on them (#7). Server side: movies/back-end/user profile/index.js + profile/locations.js.

/// One row of GET /profile/locations `countries`.
class UkoCountry {
  const UkoCountry({required this.name, required this.iso, required this.dial, required this.region, required this.plays});
  final String name;
  final String iso;
  final String dial; // without "+"
  final String region;
  final bool plays; // a phone number from here may play (Africa, Australia, Brazil)

  static UkoCountry? fromJson(dynamic j) {
    if (j is! Map) return null;
    final name = '${j['name'] ?? ''}';
    if (name.isEmpty) return null;
    return UkoCountry(
      name: name,
      iso: '${j['iso'] ?? ''}'.toUpperCase(),
      dial: '${j['dial'] ?? ''}',
      region: '${j['region'] ?? ''}',
      plays: j['plays'] == true,
    );
  }
}

/// GET /profile/locations: Kenya's counties are a closed list, every other country types its
/// county; wards are suggestions only.
class UkoLocations {
  UkoLocations({required this.defaultCountry, required this.countries, required this.counties, required this.wards});
  final String defaultCountry;
  final List<UkoCountry> countries;
  final Map<String, List<String>> counties;
  final Map<String, List<String>> wards;

  UkoCountry? byName(String? name) {
    final n = (name ?? '').trim().toLowerCase();
    for (final c in countries) {
      if (c.name.toLowerCase() == n) return c;
    }
    return null;
  }

  /// The closed county list for [country], or null when the county is typed.
  List<String>? countiesFor(String? country) => counties[country];

  List<String> wardsFor(String? county) {
    final n = (county ?? '').trim().toLowerCase();
    for (final e in wards.entries) {
      if (e.key.toLowerCase() == n) return e.value;
    }
    return const [];
  }

  /// The country a typed phone number belongs to: "+254…" / "00254…" by dialling code (longest
  /// first, like the server), otherwise the country picked in the form. "+1" reads as the US.
  UkoCountry? phoneCountry(String phone, String? pickedCountry) {
    var digits = phone.replaceAll(RegExp(r'[\s\-().]'), '');
    if (digits.startsWith('00')) digits = '+${digits.substring(2)}';
    if (!digits.startsWith('+')) return byName(pickedCountry);
    final body = digits.substring(1);
    if (body.isEmpty) return null;
    UkoCountry? best;
    for (final c in countries) {
      if (c.dial.isEmpty || !body.startsWith(c.dial)) continue;
      if (best == null || c.dial.length > best.dial.length) best = c;
    }
    return best;
  }

  static UkoLocations? fromJson(dynamic j) {
    if (j is! Map || j['status'] != true) return null;
    final countries = (j['countries'] is List ? j['countries'] as List : const [])
        .map(UkoCountry.fromJson)
        .whereType<UkoCountry>()
        .toList();
    if (countries.isEmpty) return null;
    Map<String, List<String>> lists(dynamic m) => {
          if (m is Map)
            for (final e in m.entries)
              if (e.value is List) '${e.key}': [for (final v in e.value as List) '$v'],
        };
    return UkoLocations(
      defaultCountry: '${j['default_country'] ?? 'Kenya'}',
      countries: countries,
      counties: lists(j['counties']),
      wards: lists(j['wards']),
    );
  }
}

/// GET/POST /profile/android `profile`.
class UkoProfile {
  const UkoProfile({
    this.email,
    this.username,
    this.telephone,
    this.country,
    this.county,
    this.ward,
    this.phoneCountry,
    this.phoneAllowsPlay = false,
    this.complete = false,
  });
  /// Where the account number was emailed; the number itself is only stored hashed.
  final String? email;
  /// Unique; comments are posted under it. Null until the viewer picks one.
  final String? username;
  final String? telephone;
  final String? country;
  final String? county;
  final String? ward;
  final String? phoneCountry;
  final bool phoneAllowsPlay;
  final bool complete;

  static String? _s(dynamic v) => v == null || '$v'.isEmpty ? null : '$v';

  static UkoProfile? fromJson(dynamic j) {
    if (j is! Map) return null;
    return UkoProfile(
      email: _s(j['email']),
      username: _s(j['username']),
      telephone: _s(j['telephone']),
      country: _s(j['country']),
      county: _s(j['county']),
      ward: _s(j['ward']),
      phoneCountry: _s(j['phone_country']),
      phoneAllowsPlay: j['phone_allows_play'] == true,
      complete: j['complete'] == true,
    );
  }
}

/// A save's outcome: the updated profile, or the server's message (400 bad phone / location,
/// 409 phone on another account).
class ProfileSaveResult {
  const ProfileSaveResult({this.profile, this.message});
  final UkoProfile? profile;
  final String? message;
  bool get ok => profile != null;
}

class ProfileService {
  ProfileService._();

  /// Profile answers are kept this long, so moving between detail screens doesn't refetch.
  static const cacheFor = Duration(minutes: 2);

  static UkoLocations? _locations;
  static UkoProfile? _profile;
  static String? _profileUser;
  static DateTime? _profileAt;
  static Future<UkoProfile?>? _inFlight;

  static Future<bool> get signedIn async {
    final user = await Prefs.user;
    return user != null && user.isNotEmpty;
  }

  /// Reference data for the forms; kept for the life of the app once it loads.
  static Future<UkoLocations?> locations() async {
    final cached = _locations;
    if (cached != null) return cached;
    final res = await Http.getJson(Api.profileLocations);
    return _locations = UkoLocations.fromJson(res);
  }

  /// The signed-in account's profile (null when signed out or on a failed request). Cached for
  /// [cacheFor] per account; [force] skips the cache.
  static Future<UkoProfile?> fetch({bool force = false}) async {
    final user = await Prefs.user;
    if (user == null || user.isEmpty) return null;
    final at = _profileAt;
    if (!force && _profile != null && _profileUser == user && at != null && DateTime.now().difference(at) < cacheFor) {
      return _profile;
    }
    return _inFlight ??= _load(user).whenComplete(() => _inFlight = null);
  }

  static Future<UkoProfile?> _load(String user) async {
    final res = await Http.getJson(Api.profile);
    final profile = res is Map && res['status'] == true ? UkoProfile.fromJson(res['profile']) : null;
    if (profile != null) _remember(user, profile);
    return profile;
  }

  static void _remember(String user, UkoProfile profile) {
    _profile = profile;
    _profileUser = user;
    _profileAt = DateTime.now();
  }

  /// POST /profile/android with any of username / telephone / country+county+ward.
  static Future<ProfileSaveResult> save(Map<String, String> body) async {
    final user = await Prefs.user;
    final res = await Http.postJson(Api.profile, body);
    if (res is Map && res['status'] == true) {
      final profile = UkoProfile.fromJson(res['profile']);
      if (profile != null) {
        if (user != null) _remember(user, profile);
        return ProfileSaveResult(profile: profile);
      }
    }
    final m = res is Map ? res['message'] : null;
    return ProfileSaveResult(message: m is String && m.isNotEmpty ? m : 'Could not save your profile. Try again.');
  }

  static void clearCache() {
    _profile = null;
    _profileUser = null;
    _profileAt = null;
  }
}

/// Same rule as the user service (profile/index.js readUsername): 3-20 letters, digits, "_" or ".",
/// starting with a letter or digit, at least one letter, no "..", not ending in ".". Returns the
/// problem, or null when [raw] is fine.
String? usernameProblem(String raw) {
  final name = cleanUsername(raw);
  if (name.isEmpty) return 'Choose a username';
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.]{2,19}$').hasMatch(name) || name.contains('..') || name.endsWith('.')) {
    return '3 to 20 letters, numbers, _ or . - starting with a letter or number';
  }
  if (RegExp(r'^\d+$').hasMatch(name)) return 'A username needs at least one letter';
  return null;
}

/// A typed username as it is sent: trimmed, a leading "@" dropped.
String cleanUsername(String raw) => raw.trim().replaceFirst(RegExp(r'^@'), '');

// ------------------------------------------------------------------ play gate (PRD #7)

/// Africa (all 54, the server's PLAY_COUNTRIES), Australia and Brazil, as ISO 3166 alpha-2.
const kPlayCountryCodes = <String>{
  'DZ', 'AO', 'BJ', 'BW', 'BF', 'BI', 'CV', 'CM', 'CF', 'TD', 'KM', 'CG', 'CD', 'CI', 'DJ', 'EG', 'GQ', 'ER',
  'SZ', 'ET', 'GA', 'GM', 'GH', 'GN', 'GW', 'KE', 'LS', 'LR', 'LY', 'MG', 'MW', 'ML', 'MR', 'MU', 'MA', 'MZ',
  'NA', 'NE', 'NG', 'RW', 'ST', 'SN', 'SC', 'SL', 'SO', 'ZA', 'SS', 'SD', 'TZ', 'TG', 'TN', 'UG', 'ZM', 'ZW',
  'AU', 'BR',
};

/// Fallback for a cached geocode without an ISO code (older caches): English country names.
const _playCountryNames = <String>{
  'Algeria', 'Angola', 'Benin', 'Botswana', 'Burkina Faso', 'Burundi', 'Cabo Verde', 'Cameroon',
  'Central African Republic', 'Chad', 'Comoros', 'Congo', 'Democratic Republic of the Congo',
  "Côte d'Ivoire", 'Djibouti', 'Egypt', 'Equatorial Guinea', 'Eritrea', 'Eswatini', 'Ethiopia', 'Gabon',
  'Gambia', 'Ghana', 'Guinea', 'Guinea-Bissau', 'Kenya', 'Lesotho', 'Liberia', 'Libya', 'Madagascar',
  'Malawi', 'Mali', 'Mauritania', 'Mauritius', 'Morocco', 'Mozambique', 'Namibia', 'Niger', 'Nigeria',
  'Rwanda', 'São Tomé and Príncipe', 'Senegal', 'Seychelles', 'Sierra Leone', 'Somalia', 'South Africa',
  'South Sudan', 'Sudan', 'Tanzania', 'Togo', 'Tunisia', 'Uganda', 'Zambia', 'Zimbabwe', 'Australia', 'Brazil',
};

/// runLocale(): the device half of the play gate. Reads the reverse-geocode cached in "location"
/// (services_ext/report.dart writes it); when there is none, asks for GPS once and caches it.
/// True in Africa, Australia or Brazil.
Future<bool> deviceInPlayRegion() async {
  try {
    dynamic userLocation;
    final stored = await Prefs.getItem(PrefKeys.location);
    if (stored == null || stored.isEmpty) {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm != LocationPermission.always && perm != LocationPermission.whileInUse) return false;
      final pos = await Geolocator.getCurrentPosition();
      final marks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      // Same keys as expo-location's reverseGeocodeAsync result.
      userLocation = marks
          .map((p) => {
                'city': p.locality,
                'country': p.country,
                'district': p.subLocality,
                'isoCountryCode': p.isoCountryCode,
                'name': p.name,
                'postalCode': p.postalCode,
                'region': p.administrativeArea,
                'street': p.thoroughfare,
                'streetNumber': p.subThoroughfare,
                'subregion': p.subAdministrativeArea,
                'timezone': null,
                'formattedAddress': null,
              })
          .toList();
      try {
        await Prefs.setItem(PrefKeys.location, jsonEncode(userLocation));
      } catch (e) {
        debugPrint('Failed to persist location $e');
      }
    } else {
      userLocation = jsonDecode(stored);
    }
    final first = userLocation is List && userLocation.isNotEmpty && userLocation[0] is Map ? userLocation[0] as Map : null;
    if (first == null) return false;
    final code = '${first['isoCountryCode'] ?? ''}'.toUpperCase();
    if (code.isNotEmpty) return kPlayCountryCodes.contains(code);
    return _playCountryNames.contains(first['country']);
  } catch (e) {
    debugPrint('$e location error');
    return false;
  }
}

enum PlayGate {
  /// Device is outside Africa / Australia / Brazil: no play button at all.
  hidden,

  /// Device location is fine but the signed-in account has no phone number from a play
  /// country: show "Add a phone number…" instead of play.
  needsPhone,

  /// Show play.
  allowed,
}

/// PRD #7: play shows only when the device is in Africa, Australia or Brazil AND, when signed
/// in, the account's phone number is from one of them. Guests (Eden content only) are checked on
/// location alone. A failed profile request counts as "no phone" (it is not cached, so the next
/// screen asks again).
Future<PlayGate> playGate() async {
  if (!await deviceInPlayRegion()) return PlayGate.hidden;
  if (!await ProfileService.signedIn) return PlayGate.allowed;
  final profile = await ProfileService.fetch();
  return profile != null && profile.phoneAllowsPlay ? PlayGate.allowed : PlayGate.needsPhone;
}
