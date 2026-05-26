import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

class DeviceApi {
  static Future<Map<String, dynamic>> registerDevice(String fcmToken) async {
    try {
      if (fcmToken.isEmpty) {
        return {
          "success": false,
          "message": "FCM token is empty",
        };
      }

      final prefs = await SharedPreferences.getInstance();
      final cookie = prefs.getString("cookie") ?? "";
      final username = prefs.getString("username") ?? "";

      if (cookie.isEmpty || username.isEmpty) {
        return {
          "success": false,
          "message": "Session not found",
        };
      }

      final response = await http.post(
        Uri.parse(AppConfig.registerDeviceApi),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Cookie': cookie,
        },
        body: {
          // Keep multiple key aliases so existing backend methods keep working.
          "username": username,
          "user": username,
          "fcm_token": fcmToken,
          "token": fcmToken,
          "device_token": fcmToken,
          "platform": "android",
        },
      );

      if (response.statusCode == 200) {
        final body = response.body;
        if (body.isNotEmpty) {
          final jsonData = jsonDecode(body);
          if (jsonData is Map &&
              jsonData["message"] is Map &&
              jsonData["message"]["success"] == false) {
            return {
              "success": false,
              "message": jsonData["message"]["message"] ?? "Registration failed",
            };
          }
        }

        return {
          "success": true,
          "message": "Device registered",
        };
      }

      return {
        "success": false,
        "message": "Register device failed (${response.statusCode})",
      };
    } catch (e) {
      return {
        "success": false,
        "message": e.toString(),
      };
    }
  }
}
