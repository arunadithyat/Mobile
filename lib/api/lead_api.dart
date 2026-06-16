import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

class LeadApi {
  static Future<String> _getCsrfToken(String cookie) async {
    try {
      final response = await http.get(
        Uri.parse("${AppConfig.baseUrl}/api/method/frappe.auth.get_csrf_token"),
        headers: {'Cookie': cookie},
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return jsonDecode(response.body)['message'] ?? '';
      }
      return '';
    } catch (e) {
      debugPrint("[CSRF] Error: $e");
      return '';
    }
  }
  /// Fetches dropdown OPTIONS for Lead fields from /api/method/leadvalues
  static Future<Map<String, List<String>>> getFieldOptions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cookie = prefs.getString('cookie') ?? '';
      if (cookie.isEmpty) return {};

      debugPrint('[LEAD_API] Fetching field options...');

      final response = await http.get(
        Uri.parse(AppConfig.leadValuesApi),
        headers: {'Cookie': cookie},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final message = data['message'];
        if (message is Map<String, dynamic>) {
          final options = <String, List<String>>{};
          message.forEach((key, value) {
            if (value is List) {
              options[key] = value.map((e) => e.toString()).toList();
            }
          });
          debugPrint('[LEAD_API] ✅ Got options for ${options.length} fields');
          return options;
        }
      }
      debugPrint('[LEAD_API] ❌ HTTP ${response.statusCode}');
      return {};
    } catch (e) {
      debugPrint('[LEAD_API] ❌ Options error: $e');
      return {};
    }
  }

  /// Fetches CURRENT VALUES of a specific Lead from Frappe resource API
  static Future<Map<String, dynamic>> getLeadCurrentValues(String leadName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cookie = prefs.getString('cookie') ?? '';
      if (cookie.isEmpty || leadName.isEmpty) return {};

      debugPrint('[LEAD_API] Fetching current values for: $leadName');

      final fields = Uri.encodeComponent(jsonEncode([
        "status", "custom_customer_category", "custom_customer_type",
        "custom_district", "custom_citytown", "custom_next_followup_date1"
      ]));
      final url = '${AppConfig.baseUrl}/api/resource/Lead/$leadName?fields=$fields';

      final response = await http.get(
        Uri.parse(url),
        headers: {'Cookie': cookie},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final values = data['data'] ?? {};
        if (values is Map<String, dynamic>) {
          debugPrint('[LEAD_API] ✅ Got values for $leadName');
          return values;
        }
      }
      debugPrint('[LEAD_API] ❌ HTTP ${response.statusCode}');
      return {};
    } catch (e) {
      debugPrint('[LEAD_API] ❌ Values error: $e');
      return {};
    }
  }

  /// Updates Lead fields via /api/method/update_lead
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
          'X-Frappe-CSRF-Token': await _getCsrfToken(cookie),
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

class OpportunityApi {
  static Future<String> _getCsrfToken(String cookie) async {
    try {
      final response = await http.get(
        Uri.parse("${AppConfig.baseUrl}/api/method/frappe.auth.get_csrf_token"),
        headers: {'Cookie': cookie},
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return jsonDecode(response.body)['message'] ?? '';
      }
      return '';
    } catch (e) {
      debugPrint("[CSRF] Error: $e");
      return '';
    }
  }
  /// Fetches dropdown OPTIONS for Opportunity fields
  static Future<Map<String, List<String>>> getFieldOptions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cookie = prefs.getString('cookie') ?? '';
      if (cookie.isEmpty) return {};

      debugPrint('[OPP_API] Fetching field options...');

      final response = await http.get(
        Uri.parse(AppConfig.opportunityValuesApi),
        headers: {'Cookie': cookie},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final message = data['message'];
        if (message is Map<String, dynamic>) {
          final options = <String, List<String>>{};
          message.forEach((key, value) {
            if (value is List) {
              options[key] = value.map((e) => e.toString()).toList();
            }
          });
          debugPrint('[OPP_API] ✅ Got options for ${options.length} fields');
          return options;
        }
      }
      return {};
    } catch (e) {
      debugPrint('[OPP_API] ❌ Options error: $e');
      return {};
    }
  }

  /// Fetches CURRENT VALUES of a specific Opportunity
  static Future<Map<String, dynamic>> getCurrentValues(String oppName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cookie = prefs.getString('cookie') ?? '';
      if (cookie.isEmpty || oppName.isEmpty) return {};

      debugPrint('[OPP_API] Fetching current values for: $oppName');

      final fields = Uri.encodeComponent(jsonEncode([
        "status", "opportunity_amount", "custom_next_followup_date1"
      ]));
      final url = '${AppConfig.baseUrl}/api/resource/Opportunity/$oppName?fields=$fields';

      final response = await http.get(
        Uri.parse(url),
        headers: {'Cookie': cookie},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final values = data['data'] ?? {};
        if (values is Map<String, dynamic>) {
          debugPrint('[OPP_API] ✅ Got values for $oppName');
          return values;
        }
      }
      return {};
    } catch (e) {
      debugPrint('[OPP_API] ❌ Values error: $e');
      return {};
    }
  }

  /// Updates Opportunity fields
  static Future<Map<String, dynamic>> updateOpportunity({
    required String oppName,
    required Map<String, dynamic> fields,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cookie = prefs.getString('cookie') ?? '';
      if (cookie.isEmpty) return {'success': false, 'message': 'No session'};

      debugPrint('[OPP_API] Updating $oppName: $fields');

      final body = <String, String>{'opportunity_name': oppName};
      fields.forEach((key, value) {
        if (value != null) body[key] = value.toString();
      });

      final response = await http.post(
        Uri.parse(AppConfig.updateOpportunityApi),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Cookie': cookie,
          'X-Frappe-CSRF-Token': await _getCsrfToken(cookie),
        },
        body: body,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) return {'success': true};
      debugPrint('[OPP_API] ❌ ${response.body}');
      return {'success': false, 'message': 'Failed (${response.statusCode})'};
    } catch (e) {
      debugPrint('[OPP_API] ❌ $e');
      return {'success': false, 'message': e.toString()};
    }
  }
}
