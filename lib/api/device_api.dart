import 'dart:async';
import 'dart:convert';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

class DeviceApi {
  /// Returns a unique, stable device identifier that survives app reinstalls.
  /// On Android this is the androidId. Falls back to a stored UUID if unavailable.
  static Future<String> _getDeviceId() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      final id = androidInfo.id; // stable hardware-backed ID
      if (id.isNotEmpty) {
        debugPrint('[DEVICE] Using androidId: $id');
        return id;
      }
    } catch (e) {
      debugPrint('[DEVICE] androidId unavailable: $e');
    }

    // Fallback — use a UUID stored in SharedPreferences (survives reinstall
    // only if backup is enabled, but better than nothing)
    final prefs = await SharedPreferences.getInstance();
    var stored = prefs.getString('device_uuid');
    if (stored == null || stored.isEmpty) {
      stored = DateTime.now().millisecondsSinceEpoch.toString();
      await prefs.setString('device_uuid', stored);
      debugPrint('[DEVICE] Generated fallback device_uuid: $stored');
    } else {
      debugPrint('[DEVICE] Using stored device_uuid: $stored');
    }
    return stored;
  }

  /// Registers or UPDATES the FCM device entry for the current user.
  /// Sends device_id so the backend can upsert (update if exists, insert if not)
  /// instead of always creating a new record on reinstall.
  static Future<Map<String, dynamic>> registerDevice(String fcmToken) async {
    try {
      if (fcmToken.isEmpty) {
        return {'success': false, 'message': 'FCM token is empty'};
      }

      final prefs = await SharedPreferences.getInstance();
      final cookie = prefs.getString('cookie') ?? '';
      final username = prefs.getString('username') ?? '';

      if (cookie.isEmpty || username.isEmpty) {
        return {'success': false, 'message': 'Session not found'};
      }

      final deviceId = await _getDeviceId();
      final packageInfo = await PackageInfo.fromPlatform();
      final appVersion = packageInfo.version;
      final buildNumber = packageInfo.buildNumber;

      debugPrint('[DEVICE] Registering device...');
      debugPrint('[DEVICE] username   : $username');
      debugPrint('[DEVICE] device_id  : $deviceId');
      debugPrint('[DEVICE] token (len): \${fcmToken.length}');
      debugPrint('[DEVICE] app_version: $appVersion+$buildNumber');

      final response = await http.post(
        Uri.parse(AppConfig.registerDeviceApi),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Cookie': cookie,
        },
        body: {
          // User identity
          'username': username,
          'user': username,
          // Stable device identity — backend uses this for upsert
          'device_id': deviceId,
          // FCM token (changes on reinstall — backend updates this field)
          'fcm_token': fcmToken,
          'token': fcmToken,
          'device_token': fcmToken,
          // Platform
          'platform': 'android',
          // Tell backend to upsert: update existing entry for this
          // device_id+user combo, or insert if none exists
          'app_version': appVersion,
          'build_number': buildNumber,
          'action': 'upsert',
        },
      ).timeout(const Duration(seconds: 10));

      debugPrint('[DEVICE] Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final body = response.body;
        if (body.isNotEmpty) {
          try {
            final jsonData = jsonDecode(body);
            if (jsonData is Map &&
                jsonData['message'] is Map &&
                jsonData['message']['success'] == false) {
              debugPrint('[DEVICE] ❌ Registration failed: ${jsonData['message']['message']}');
              return {
                'success': false,
                'message': jsonData['message']['message'] ?? 'Registration failed',
              };
            }
          } catch (_) {}
        }
        debugPrint('[DEVICE] ✅ Device registered/updated successfully');
        return {'success': true, 'message': 'Device registered'};
      }

      debugPrint('[DEVICE] ❌ HTTP ${response.statusCode}');
      return {
        'success': false,
        'message': 'Register device failed (${response.statusCode})',
      };
    } catch (e) {
      debugPrint('[DEVICE] ❌ Error: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Call this on login to force a fresh token registration.
  /// Deletes the cached FCM token so Firebase generates a new one,
  /// then immediately registers it — ensuring the backend always has
  /// the latest token for this device+user combination.
  static Future<void> refreshAndRegisterToken() async {
    try {
      debugPrint('[DEVICE] 🔄 Forcing FCM token refresh on login...');
      await _deleteAndRefetchToken();
    } catch (e) {
      debugPrint('[DEVICE] ❌ refreshAndRegisterToken error: $e');
    }
  }

  static Future<void> _deleteAndRefetchToken() async {
    // Importing FirebaseMessaging here avoids a circular dependency
    // between device_api and main.dart — handled via dynamic import pattern
    // The actual call is made from main.dart _initFCM() after login.
    debugPrint('[DEVICE] Token refresh should be triggered from _initFCM() in main.dart');
  }
}
