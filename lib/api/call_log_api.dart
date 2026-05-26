import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';

class CallLogApi {
  /// Log a call initiation to Error Log
  static Future<Map<String, dynamic>> logCallInitiation({
    required String doctype,
    required String docname,
    required String customerName,
    required String mobileNo,
    required DateTime initiatedAt,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cookie = prefs.getString("cookie") ?? "";
      final username = prefs.getString("username") ?? "";

      if (cookie.isEmpty || username.isEmpty) {
        return {
          "success": false,
          "message": "Session not found",
        };
      }

      // Format call details as error log entry
      final callDetails = {
        "type": "CALL_INITIATED",
        "timestamp": initiatedAt.toIso8601String(),
        "initiated_by": username,
        "doctype_reference": doctype,
        "docname_reference": docname,
        "customer_name": customerName,
        "mobile_number": mobileNo,
        "status": "Success",
        "call_status": "Initiated"
      };

      final response = await http.post(
        Uri.parse("${AppConfig.baseUrl}/api/resource/Error%20Log"),
        headers: {
          'Content-Type': 'application/json',
          'Cookie': cookie,
          'X-Frappe-CSRF-Token': await _getCsrfToken(cookie),
        },
        body: jsonEncode({
          "data": {
            "doctype": "Error Log",
            "title": "Call Initiated - $customerName",
            "error": jsonEncode(callDetails),
            "reference_doctype": doctype,
            "reference_name": docname,
          }
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint("[CALLLOG] ✅ Call initiated logged to Error Log");
        return {
          "success": true,
          "message": "Call logged successfully",
        };
      }

      debugPrint("[CALLLOG] ❌ Failed to log call: ${response.statusCode}");
      return {
        "success": false,
        "message": "Failed to log call (${response.statusCode})",
      };
    } catch (e) {
      debugPrint("[CALLLOG] ❌ ERROR logging call: $e");
      return {
        "success": false,
        "message": e.toString(),
      };
    }
  }

  /// Update call with duration and final status
  static Future<Map<String, dynamic>> updateCallLog({
    required String doctype,
    required String docname,
    required String customerName,
    required String mobileNo,
    required DateTime initiatedTime,
    required int callDuration,
    required String callStatus,
    required String disconnectedStatus,
    required String notes,
    required bool attended,
    String dataSource = 'unknown',
    bool permissionGranted = false,
    int retrievedAttempt = -1,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cookie = prefs.getString("cookie") ?? "";
      final username = prefs.getString("username") ?? "";

      if (cookie.isEmpty || username.isEmpty) {
        return {
          "success": false,
          "message": "Session not found",
        };
      }

      // Format call update as error log entry
      final callDetails = {
        "type": "CALL_COMPLETED",
        "timestamp": DateTime.now().toIso8601String(),
        "initiated_time": initiatedTime.toIso8601String(),
        "initiated_by": username,
        "doctype_reference": doctype,
        "docname_reference": docname,
        "customer_name": customerName,
        "mobile_number": mobileNo,
        "call_duration_seconds": callDuration,
        "call_status": callStatus,
        "disconnected_status": disconnectedStatus,
        "notes": notes,
        "attended": attended,
        "data_source": dataSource,
        "read_call_log_permission": permissionGranted ? 'GRANTED' : 'DENIED',
        "device_log_retrieval_attempt": retrievedAttempt,
      };

      final response = await http.post(
        Uri.parse("${AppConfig.baseUrl}/api/resource/Error%20Log"),
        headers: {
          'Content-Type': 'application/json',
          'Cookie': cookie,
          'X-Frappe-CSRF-Token': await _getCsrfToken(cookie),
        },
        body: jsonEncode({
          "data": {
            "doctype": "Error Log",
            "title": "Call Completed - $customerName ($callDuration seconds)",
            "error": jsonEncode(callDetails),
            "reference_doctype": doctype,
            "reference_name": docname,
          }
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint("[CALLLOG] ✅ Call completed logged to Error Log");
        return {
          "success": true,
          "message": "Call updated successfully",
        };
      }

      return {
        "success": false,
        "message": "Failed to update call (${response.statusCode})",
      };
    } catch (e) {
      debugPrint("[CALLLOG] ❌ ERROR updating call: $e");
      return {
        "success": false,
        "message": e.toString(),
      };
    }
  }

  /// Log error/failure
  static Future<Map<String, dynamic>> logCallError({
    required String doctype,
    required String docname,
    required String customerName,
    required String mobileNo,
    required String errorMessage,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cookie = prefs.getString("cookie") ?? "";
      final username = prefs.getString("username") ?? "";

      if (cookie.isEmpty || username.isEmpty) {
        return {
          "success": false,
          "message": "Session not found",
        };
      }

      // Format error details
      final errorDetails = {
        "type": "CALL_ERROR",
        "timestamp": DateTime.now().toIso8601String(),
        "initiated_by": username,
        "doctype_reference": doctype,
        "docname_reference": docname,
        "customer_name": customerName,
        "mobile_number": mobileNo,
        "error_message": errorMessage,
      };

      final response = await http.post(
        Uri.parse("${AppConfig.baseUrl}/api/resource/Error%20Log"),
        headers: {
          'Content-Type': 'application/json',
          'Cookie': cookie,
          'X-Frappe-CSRF-Token': await _getCsrfToken(cookie),
        },
        body: jsonEncode({
          "data": {
            "doctype": "Error Log",
            "title": "Call Error - $customerName",
            "error": jsonEncode(errorDetails),
            "reference_doctype": doctype,
            "reference_name": docname,
          }
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint("[ERRORLOG] ✅ Error logged");
        return {
          "success": true,
          "message": "Error logged successfully",
        };
      }

      return {
        "success": false,
        "message": "Failed to log error",
      };
    } catch (e) {
      debugPrint("[ERRORLOG] ❌ ERROR logging error: $e");
      return {
        "success": false,
        "message": e.toString(),
      };
    }
  }

  /// Get CSRF token
  static Future<String> _getCsrfToken(String cookie) async {
    try {
      final response = await http.get(
        Uri.parse("${AppConfig.baseUrl}/api/method/frappe.auth.get_csrf_token"),
        headers: {
          'Cookie': cookie,
        },
      );

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        return jsonData['message'] ?? '';
      }
      return '';
    } catch (e) {
      debugPrint("[CSRF] ERROR: $e");
      return '';
    }
  }
}

