import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../models/call_queue.dart';

class CallQueueApi {
  /// Fetches pending calls from the READ-only API endpoint.
  /// Response format: { message: { calls: [...] } }
  /// This endpoint does NOT send FCM — it only returns data.
  static Future<List<CallQueueItem>> fetchCallQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cookie = prefs.getString("cookie") ?? "";

      if (cookie.isEmpty) {
        debugPrint('[QUEUE_API] ❌ No session — skipping fetch');
        return [];
      }

      debugPrint('[QUEUE_API] Fetching from ${AppConfig.callQueueApi}...');

      final response = await http.get(
        Uri.parse(AppConfig.callQueueApi),
        headers: {
          'Content-Type': 'application/json',
          'Cookie': cookie,
        },
      ).timeout(const Duration(seconds: 10));

      debugPrint('[QUEUE_API] Status: ${response.statusCode}');

      if (response.statusCode != 200) {
        debugPrint('[QUEUE_API] ❌ HTTP ${response.statusCode}');
        return [];
      }

      final jsonData = jsonDecode(response.body);
      List<dynamic> callList = [];

      if (jsonData is Map<String, dynamic>) {
        final message = jsonData['message'];

        if (message is Map<String, dynamic>) {
          // Primary format: { message: { calls: [...] } }
          if (message['calls'] is List) {
            callList = message['calls'] as List;
          }
          // Fallback: { message: { sent_payloads: [...] } }
          else if (message['sent_payloads'] is List) {
            callList = message['sent_payloads'] as List;
          }
        }
        // Fallback: { message: [...] }
        else if (message is List) {
          callList = message;
        }
      }

      final items = <CallQueueItem>[];
      final seen = <String>{};

      for (final entry in callList) {
        if (entry is! Map<String, dynamic>) continue;

        // Support both field name formats
        final docname = (entry['docname'] ?? entry['reference_docname'] ?? '').toString();
        final mobileNo = (entry['mobile_no'] ?? '').toString();
        if (docname.isEmpty || mobileNo.isEmpty) continue;

        // Dedup by docname + mobile
        final key = '$docname|$mobileNo';
        if (seen.contains(key)) continue;
        seen.add(key);

        items.add(CallQueueItem.fromMap(entry));
      }

      debugPrint('[QUEUE_API] ✅ ${items.length} pending call(s) loaded');
      return items;
    } catch (e) {
      debugPrint('[QUEUE_API] ❌ Error: $e');
      return [];
    }
  }
}
