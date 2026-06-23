import 'dart:async';
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
      ).timeout(const Duration(seconds: 10));

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
    String fromNumber = '',
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

      final endTime = initiatedTime.add(Duration(seconds: callDuration));

      // Format call update as error log entry
      final callDetails = {
        "type": "CALL_COMPLETED",
        "timestamp": DateTime.now().toIso8601String(),
        "initiated_time": initiatedTime.toIso8601String(),
        "end_time": endTime.toIso8601String(),
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
      if (fromNumber.isNotEmpty) {
        callDetails["from"] = fromNumber;
      }

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
      ).timeout(const Duration(seconds: 10));

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
      ).timeout(const Duration(seconds: 10));

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

  /// Updates Lead status after unanswered call (RNR/Busy/etc.)
  static Future<Map<String, dynamic>> updateLeadRnr({
    required String leadName,
    required String status,
    required String followUpDate,
    String comments = '',
    String junkReason = '',
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cookie = prefs.getString('cookie') ?? '';
      if (cookie.isEmpty) {
        return {'success': false, 'message': 'No session'};
      }

      debugPrint('[RNR] Updating Lead: $leadName → $status, followup: $followUpDate');

      final response = await http.post(
        Uri.parse(AppConfig.updateLeadRnrApi),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Cookie': cookie,
          'X-Frappe-CSRF-Token': await _getCsrfToken(cookie),
        },
        body: {
          'lead_name': leadName,
          'status': status,
          'custom_next_followup_date1': followUpDate,
          'comments': comments,
          'custom_reason_for_junk': junkReason,
        },
      ).timeout(const Duration(seconds: 10));

      debugPrint('[RNR] Response: ${response.statusCode}');

      if (response.statusCode == 200) {
        debugPrint('[RNR] ✅ Lead updated');
        return {'success': true};
      }

      debugPrint('[RNR] ❌ HTTP ${response.statusCode}: ${response.body}');
      return {'success': false, 'message': 'Failed (${response.statusCode})'};
    } catch (e) {
      debugPrint('[RNR] ❌ Error: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Updates Opportunity status after unanswered call (RNR/Junk)
  static Future<Map<String, dynamic>> updateOpportunityRnr({
    required String opportunityName,
    required String status,
    required String followUpDate,
    String comments = '',
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cookie = prefs.getString('cookie') ?? '';
      if (cookie.isEmpty) return {'success': false, 'message': 'No session'};

      debugPrint('[OPP_RNR] Updating Opportunity: $opportunityName → $status');

      final response = await http.post(
        Uri.parse(AppConfig.updateOpportunityRnrApi),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Cookie': cookie,
          'X-Frappe-CSRF-Token': await _getCsrfToken(cookie),
        },
        body: {
          'opportunity_name': opportunityName,
          'status': status,
          'custom_next_followup_date1': followUpDate,
          'comments': comments,
        },
      ).timeout(const Duration(seconds: 10));

      debugPrint('[OPP_RNR] Response: ${response.statusCode}');

      if (response.statusCode == 200) {
        debugPrint('[OPP_RNR] ✅ Opportunity updated');
        return {'success': true};
      }

      debugPrint('[OPP_RNR] ❌ HTTP ${response.statusCode}: ${response.body}');
      return {'success': false, 'message': 'Failed (${response.statusCode})'};
    } catch (e) {
      debugPrint('[OPP_RNR] ❌ Error: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Get CSRF token
  /// Fetches previous notes/comments for a call log
  static Future<List<Map<String, dynamic>>> getComments(String callLogName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cookie = prefs.getString('cookie') ?? '';
      if (cookie.isEmpty || callLogName.isEmpty) return [];

      final response = await http.post(
        Uri.parse(AppConfig.getCommentsApi),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Cookie': cookie,
          'X-Frappe-CSRF-Token': await _getCsrfToken(cookie),
        },
        body: {'call_log': callLogName},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final msg = json['message'];
        if (msg is Map<String, dynamic> && msg['notes'] is List) {
          return (msg['notes'] as List)
              .whereType<Map<String, dynamic>>()
              .toList();
        }
      }
      debugPrint('[COMMENTS] Response: ${response.statusCode}');
      return [];
    } catch (e) {
      debugPrint('[COMMENTS] Error: $e');
      return [];
    }
  }

  static Future<String> _getCsrfToken(String cookie) async {
    try {
      final response = await http.get(
        Uri.parse("${AppConfig.baseUrl}/api/method/frappe.auth.get_csrf_token"),
        headers: {
          'Cookie': cookie,
        },
      ).timeout(const Duration(seconds: 10));

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


/// Syncs device incoming calls to the backend. The backend decides
/// relevance (matches mobile numbers against Lead/Opportunity) and
/// creates Call Log entries for matched numbers.
class IncomingCallSyncApi {
  static Future<bool> syncIncomingCalls(
    List<Map<String, dynamic>> calls,
  ) async {
    if (calls.isEmpty) return true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final cookie = prefs.getString('cookie') ?? '';
      if (cookie.isEmpty) {
        debugPrint('[INCOMING_SYNC] No session — skipping sync');
        return false;
      }

      debugPrint('[INCOMING_SYNC] Syncing ${calls.length} incoming call(s)...');
      final response = await http.post(
        Uri.parse(AppConfig.syncIncomingCallsApi),
        headers: {
          'Content-Type': 'application/json',
          'Cookie': cookie,
        },
        body: jsonEncode({'calls': calls}),
      ).timeout(const Duration(seconds: 15));

      debugPrint('[INCOMING_SYNC] Response: ${response.statusCode}');
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[INCOMING_SYNC] Error: $e');
      return false;
    }
  }
}

/// Posts call data to the actual Call Log doctype in ERPNext.
/// This is separate from the Error Log posting (which stays as-is).
class CallLogDoctypeApi {
  /// Creates a Call Log record for an incoming call from a queued customer.
  /// Uses custom server script endpoint with ignore flags.
  static Future<Map<String, dynamic>> createIncomingCallLog({
    required String fromNumber,
    required String toNumber,
    required DateTime startTime,
    required int durationSeconds,
    required bool attended,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cookie = prefs.getString('cookie') ?? '';
      if (cookie.isEmpty) {
        return {'success': false, 'message': 'No session'};
      }

      final erpStatus = attended ? 'Completed' : 'No Answer';
      final endTime = startTime.add(Duration(seconds: durationSeconds));

      // Field names match the server script's frappe.form_dict keys
      final data = {
        'from_number': fromNumber,
        'to_number': toNumber,
        'start_time': startTime.toIso8601String(),
        'end_time': endTime.toIso8601String(),
        'duration': durationSeconds,
        'status': erpStatus,
      };

      debugPrint('[INCOMING_CALLLOG] POST ${AppConfig.createIncomingCallLogApi}');
      debugPrint('[INCOMING_CALLLOG] from=$fromNumber | to=$toNumber | status=$erpStatus | duration=$durationSeconds');

      final response = await http.post(
        Uri.parse(AppConfig.createIncomingCallLogApi),
        headers: {
          'Content-Type': 'application/json',
          'Cookie': cookie,
        },
        body: jsonEncode(data),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('[INCOMING_CALLLOG] ✅ Incoming Call Log created');
        return {'success': true};
      }

      debugPrint('[INCOMING_CALLLOG] ❌ HTTP ${response.statusCode}');
      return {'success': false, 'message': 'Failed (${response.statusCode})'};
    } catch (e) {
      debugPrint('[INCOMING_CALLLOG] ❌ Error: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Updates the Call Log record in ERPNext.
  /// Uses callLogName to find the exact record (from get_pending_calls API).
  /// attended: true → Completed, false → No Answer
  /// Updates only the summary field on a Call Log
  static Future<void> updateCallLogSummary({
    required String callLogName,
    required String summary,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cookie = prefs.getString('cookie') ?? '';
      if (cookie.isEmpty || callLogName.isEmpty) return;

      final csrfResponse = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/method/frappe.auth.get_csrf_token'),
        headers: {'Cookie': cookie},
      ).timeout(const Duration(seconds: 5));
      String csrfToken = '';
      if (csrfResponse.statusCode == 200) {
        final csrfJson = jsonDecode(csrfResponse.body);
        csrfToken = (csrfJson['message'] ?? '').toString();
      }

      final url = '${AppConfig.updateCallLogApi}/$callLogName';
      final response = await http.put(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Cookie': cookie,
          'X-Frappe-CSRF-Token': csrfToken,
        },
        body: jsonEncode({'summary': summary}),
      ).timeout(const Duration(seconds: 10));

      debugPrint('[CALL_LOG] Summary update $callLogName → $summary: ${response.statusCode}');
    } catch (e) {
      debugPrint('[CALL_LOG] Summary update error: $e');
    }
  }

  static Future<Map<String, dynamic>> updateCallLog({
    required String callLogName,
    required String mobileNo,
    required String fromNumber,
    required DateTime startTime,
    required int durationSeconds,
    required bool attended,
    String summary = '',
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cookie = prefs.getString('cookie') ?? '';
      if (cookie.isEmpty) {
        return {'success': false, 'message': 'No session'};
      }

      if (callLogName.isEmpty) {
        debugPrint('[CALL_LOG_DOCTYPE] ⚠️ No callLogName — skipping update');
        return {'success': false, 'message': 'No Call Log name'};
      }

      final erpStatus = attended ? 'Completed' : 'No Answer';

      // Calculate end_time = start_time + duration
      final endTime = startTime.add(Duration(seconds: durationSeconds));

      final data = <String, dynamic>{
        'to': mobileNo,
        if (summary.isNotEmpty) 'summary': summary,
        'type': 'Outgoing',
        'start_time': startTime.toIso8601String(),
        'end_time': endTime.toIso8601String(),
        'duration': durationSeconds,
        'status': erpStatus,
      };
      // Only send 'from' if device number is available
      if (fromNumber.isNotEmpty) {
        data['from'] = fromNumber;
      }

      final url = '${AppConfig.updateCallLogApi}/$callLogName';
      debugPrint('[CALL_LOG_DOCTYPE] PUT $url');
      debugPrint('[CALL_LOG_DOCTYPE] to: $mobileNo | duration: $durationSeconds | status: $erpStatus');

      // Get CSRF token
      final csrfResponse = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/method/frappe.auth.get_csrf_token'),
        headers: {'Cookie': cookie},
      ).timeout(const Duration(seconds: 5));
      String csrfToken = '';
      if (csrfResponse.statusCode == 200) {
        final csrfJson = jsonDecode(csrfResponse.body);
        csrfToken = (csrfJson['message'] ?? '').toString();
      }

      final response = await http.put(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Cookie': cookie,
          'X-Frappe-CSRF-Token': csrfToken,
        },
        body: jsonEncode(data),
      ).timeout(const Duration(seconds: 10));

      debugPrint('[CALL_LOG_DOCTYPE] Response: ${response.statusCode}');

      if (response.statusCode == 200) {
        debugPrint('[CALL_LOG_DOCTYPE] ✅ Call Log $callLogName updated');
        return {'success': true, 'message': 'Call Log updated'};
      }

      debugPrint('[CALL_LOG_DOCTYPE] ❌ HTTP ${response.statusCode}: ${response.body}');
      return {
        'success': false,
        'message': 'Failed (${response.statusCode})',
      };
    } catch (e) {
      debugPrint('[CALL_LOG_DOCTYPE] ❌ Error: $e');
      return {'success': false, 'message': e.toString()};
    }
  }
}
