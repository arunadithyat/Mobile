import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

class LeadApi {
  /// Fetches current field values for a Lead from the backend.
  static Future<Map<String, dynamic>> getLeadValues(String leadName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cookie = prefs.getString('cookie') ?? '';
      if (cookie.isEmpty) return {};

      debugPrint('[LEAD_API] Fetching values for: $leadName');

      final response = await http.post(
        Uri.parse(AppConfig.leadValuesApi),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Cookie': cookie,
        },
        body: {'lead_name': leadName},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final message = data['message'];
        if (message is Map<String, dynamic>) {
          debugPrint('[LEAD_API] ✅ Got values for $leadName');
          return message;
        }
      }
      debugPrint('[LEAD_API] ❌ HTTP ${response.statusCode}');
      return {};
    } catch (e) {
      debugPrint('[LEAD_API] ❌ Error: $e');
      return {};
    }
  }

  /// Updates Lead fields after an answered call.
  static Future<Map<String, dynamic>> updateLead({
    required String leadName,
    required Map<String, dynamic> fields,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cookie = prefs.getString('cookie') ?? '';
      if (cookie.isEmpty) {
        return {'success': false, 'message': 'No session'};
      }

      debugPrint('[LEAD_API] Updating $leadName: $fields');

      final body = <String, String>{'lead_name': leadName};
      fields.forEach((key, value) {
        if (value != null) body[key] = value.toString();
      });

      final response = await http.post(
        Uri.parse(AppConfig.updateLeadApi),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Cookie': cookie,
        },
        body: body,
      ).timeout(const Duration(seconds: 10));

      debugPrint('[LEAD_API] Response: ${response.statusCode}');

      if (response.statusCode == 200) {
        return {'success': true};
      }

      debugPrint('[LEAD_API] ❌ ${response.body}');
      return {'success': false, 'message': 'Failed (${response.statusCode})'};
    } catch (e) {
      debugPrint('[LEAD_API] ❌ $e');
      return {'success': false, 'message': e.toString()};
    }
  }
}
