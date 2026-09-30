import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/env.dart';
import '../core/http.dart';
import '../services/prefs.dart';

/// Port of middleware/report.js `COLLECT()`.
///
/// 1. "location" pref: if missing, asks for foreground location permission,
///    reads the current position and reverse-geocodes it (expo-location
///    `reverseGeocodeAsync` -> geocoding `placemarkFromCoordinates`, mapped to
///    the same field names expo returned), then stores the JSON array.
///    Permission denied -> returns null without reporting (same as RN).
/// 2. "device" pref: if missing, builds the react-native-device-info blob and
///    stores it as a JSON string. NOTE: like RN, `device` is sent to the
///    report endpoint as that *string*, not as an object.
/// 3. POSTs `{wireframe:{}, time, user, date, locations, device}` to Api.report.
///
/// Never throws.
class Report {
  Report._();

  static bool _running = false;

  static Future<void> collect() async {
    if (_running) return; // avoid overlapping permission prompts
    _running = true;
    try {
      await _collect();
    } catch (e) {
      debugPrint('COLLECT failed: $e');
    } finally {
      _running = false;
    }
  }

  static Future<void> _collect() async {
    final apiUrl = Api.report;

    final storedLocation = await Prefs.getItem(PrefKeys.location);
    String? device = await Prefs.getItem(PrefKeys.device);

    // `new Date().toISOString().slice(11, 19)` -> UTC HH:MM:SS
    final time = DateTime.now().toUtc().toIso8601String().substring(11, 19);
    // local yy-MM-dd
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final date = '${now.year.toString().substring(now.year.toString().length - 2)}-${two(now.month)}-${two(now.day)}';

    dynamic userLocation;
    if (storedLocation == null || storedLocation.isEmpty) {
      final granted = await _requestPermission();
      if (!granted) return; // RN: `if (status !== "granted") return null;`

      final pos = await Geolocator.getCurrentPosition();
      final placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      final locations = placemarks.map(_placemarkToExpo).toList();
      await Prefs.setItem(PrefKeys.location, jsonEncode(locations));
      userLocation = locations;
    } else {
      try {
        userLocation = jsonDecode(storedLocation);
      } catch (e) {
        // leave as-is if parsing fails (RN kept the raw string)
        debugPrint('parsing error $e');
        userLocation = storedLocation;
      }
    }

    if (device == null || device.isEmpty) {
      device = jsonEncode(await _deviceInfo());
      await Prefs.setItem(PrefKeys.device, device);
    }

    final res = await Http.postJson(
      apiUrl,
      {
        'wireframe': <String, dynamic>{},
        'time': time,
        'user': await Prefs.user,
        'date': date,
        'locations': userLocation,
        'device': device,
      },
      headers: const {'Content-type': 'application/json; charset=UTF-8'},
    );
    debugPrint('${res is Map ? res['status'] : null} status report');
  }

  /// expo-location `requestForegroundPermissionsAsync()` -> "granted"?
  static Future<bool> _requestPermission() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        // expo would still return "granted" but getCurrentPositionAsync then
        // throws; either way no report is sent.
        return false;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      return perm == LocationPermission.always || perm == LocationPermission.whileInUse;
    } catch (e) {
      debugPrint('location permission error: $e');
      return false;
    }
  }

  /// Same keys as expo-location's LocationGeocodedAddress.
  static Map<String, dynamic> _placemarkToExpo(Placemark p) {
    String? n(String? v) => (v == null || v.isEmpty) ? null : v;
    final parts = [p.name, p.thoroughfare, p.locality, p.administrativeArea, p.country]
        .where((e) => e != null && e.isNotEmpty)
        .toList();
    return {
      'city': n(p.locality),
      'district': n(p.subLocality),
      'streetNumber': n(p.subThoroughfare),
      'street': n(p.thoroughfare),
      'region': n(p.administrativeArea),
      'subregion': n(p.subAdministrativeArea),
      'country': n(p.country),
      'postalCode': n(p.postalCode),
      'name': n(p.name),
      'isoCountryCode': n(p.isoCountryCode),
      'timezone': null,
      'formattedAddress': parts.isEmpty ? null : parts.join(', '),
    };
  }

  /// react-native-device-info fields used by report.js.
  static Future<Map<String, dynamic>> _deviceInfo() async {
    final plugin = DeviceInfoPlugin();
    String brand = '', model = '', systemName = '', systemVersion = '', deviceId = '', uniqueId = '';
    bool isEmulator = false;
    try {
      if (Platform.isAndroid) {
        final a = await plugin.androidInfo;
        brand = a.brand;
        model = a.model;
        systemName = 'Android';
        systemVersion = a.version.release;
        deviceId = a.board; // DeviceInfo.getDeviceId() == Build.BOARD on Android
        isEmulator = !a.isPhysicalDevice;
        // ANDROID_ID (RN getUniqueId) is not exposed by device_info_plus; a
        // random per-install id is used instead (persisted via the "device" pref).
        uniqueId = _randomId();
      } else if (Platform.isIOS) {
        final i = await plugin.iosInfo;
        brand = 'Apple';
        model = i.model;
        systemName = i.systemName;
        systemVersion = i.systemVersion;
        deviceId = i.utsname.machine;
        uniqueId = i.identifierForVendor ?? _randomId();
        isEmulator = !i.isPhysicalDevice;
      } else {
        systemName = Platform.operatingSystem;
        systemVersion = Platform.operatingSystemVersion;
        uniqueId = _randomId();
      }
    } catch (e) {
      debugPrint('device info error: $e');
    }
    String appVersion = '', buildNumber = '';
    try {
      final info = await PackageInfo.fromPlatform();
      appVersion = info.version;
      buildNumber = info.buildNumber;
    } catch (_) {}
    return {
      'brand': brand,
      'model': model,
      'systemName': systemName,
      'systemVersion': systemVersion,
      'deviceId': deviceId,
      'uniqueId': uniqueId,
      'appVersion': appVersion,
      'buildNumber': buildNumber,
      'isEmulator': isEmulator,
    };
  }

  static String _randomId() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }
}
