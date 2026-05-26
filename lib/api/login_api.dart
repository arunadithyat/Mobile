import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

class LoginApi {

  static Future<Map<String, dynamic>> login(
    String usr,
    String pwd,
  ) async {

    try {

      final response = await http.post(
        Uri.parse(AppConfig.loginApi),

        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },

        body: {
          "usr": usr,
          "pwd": pwd,
        },
      );

      if (response.statusCode != 200) {
        return {
          "success": false,
          "message": "Invalid Credentials"
        };
      }

      final prefs = await SharedPreferences.getInstance();

      final cookie =
          response.headers["set-cookie"] ?? "";

      await prefs.setString(
        "cookie",
        cookie,
      );

      await prefs.setString(
        "base_url",
        AppConfig.baseUrl,
      );

      await prefs.setString(
        "username",
        usr,
      );

      await prefs.setBool(
        "is_logged_in",
        true,
      );

      return {
        "success": true
      };

    } catch (e) {

      return {
        "success": false,
        "message": e.toString()
      };
    }
  }

  static Future<bool> checkSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isLoggedIn = prefs.getBool("is_logged_in") ?? false;
      final cookie = prefs.getString("cookie") ?? "";
      final username = prefs.getString("username") ?? "";

      if (!isLoggedIn || cookie.isEmpty || username.isEmpty) {
        return false;
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<void> logout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool("is_logged_in", false);
      await prefs.remove("cookie");
      await prefs.remove("username");
      await prefs.remove("base_url");
    } catch (e) {
      // Handle error silently
    }
  }
}