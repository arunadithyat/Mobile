import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../models/call_queue.dart';

class CallQueueApi {
  /// Fetches pending calls from the API endpoint.
  /// Supports both old format (calls/sent_payloads) and new categorized format.
  static Future<List<CallQueueItem>> fetchCallQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cookie = prefs.getString("cookie") ?? "";

      if (cookie.isEmpty) {
        debugPrint('[QUEUE_API] No session — skipping fetch');
        return [];
      }

      final response = await http.get(
        Uri.parse(AppConfig.callQueueApi),
        headers: {
          'Content-Type': 'application/json',
          'Cookie': cookie,
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        debugPrint('[QUEUE_API] HTTP ${response.statusCode}');
        return [];
      }

      final jsonData = jsonDecode(response.body);
      if (jsonData is! Map<String, dynamic>) return [];

      final message = jsonData['message'];
      if (message == null) return [];

      final items = <CallQueueItem>[];
      final seen = <String>{};

      // New categorized format
      if (message is Map<String, dynamic>) {
        const categoryMap = {
          'pending_calls': 'Hot Leads',
          'lead_followup_calls': 'Followup Leads',
          'opportunity_followup_calls': 'Order Followups',
          'b2b_calls': 'B2B Followups',
        };

        bool foundCategorized = false;
        for (final entry in categoryMap.entries) {
          final list = message[entry.key];
          if (list is List && list.isNotEmpty) {
            foundCategorized = true;
            for (final item in list) {
              if (item is! Map<String, dynamic>) continue;
              final parsed = _parseItem(item, seen, overrideCategory: entry.value);
              if (parsed != null) items.add(parsed);
            }
          }
        }

        // Fallback: old format (calls / sent_payloads)
        if (!foundCategorized) {
          List<dynamic> callList = [];
          if (message['calls'] is List) {
            callList = message['calls'] as List;
          } else if (message['sent_payloads'] is List) {
            callList = message['sent_payloads'] as List;
          }
          for (final item in callList) {
            if (item is! Map<String, dynamic>) continue;
            final parsed = _parseItem(item, seen);
            if (parsed != null) items.add(parsed);
          }
        }
      }
      // Fallback: message is a List directly
      else if (message is List) {
        for (final item in message) {
          if (item is! Map<String, dynamic>) continue;
          final parsed = _parseItem(item, seen);
          if (parsed != null) items.add(parsed);
        }
      }

      debugPrint('[QUEUE_API] ✅ ${items.length} call(s) loaded');
      return items;
    } catch (e) {
      debugPrint('[QUEUE_API] Error: $e');
      return [];
    }
  }

  static CallQueueItem? _parseItem(
    Map<String, dynamic> entry,
    Set<String> seen, {
    String? overrideCategory,
  }) {
    final docname = (entry['docname'] ?? entry['reference_docname'] ?? '').toString();
    final mobileNo = (entry['mobile_no'] ?? '').toString();
    if (docname.isEmpty || mobileNo.isEmpty) return null;

    final key = '$docname|$mobileNo';
    if (seen.contains(key)) return null;
    seen.add(key);

    if (overrideCategory != null) {
      entry['category'] = overrideCategory;
    }

    return CallQueueItem.fromMap(entry);
  }
}
