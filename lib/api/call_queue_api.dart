import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../models/call_queue.dart';

class CallQueueApi {
  static bool _validateQueueItem(Map<String, dynamic> item) {
    final docname =
        item['name']?.toString() ?? item['docname']?.toString() ?? '';
    final mobileNo = item['mobile_no']?.toString() ?? '';

    if (docname.isEmpty || mobileNo.isEmpty) {
      debugPrint('[QUEUE_API] ❌ Invalid queue item - missing required fields');
      return false;
    }

    return true;
  }

  static List<dynamic> _extractQueueList(dynamic jsonData) {
    if (jsonData is List) return jsonData;
    if (jsonData is! Map) return const [];

    for (final key in const ['data', 'message', 'queue', 'items', 'results']) {
      final value = jsonData[key];
      if (value is List && value.isNotEmpty) return value;
      if (value is Map) {
        final nested = _extractQueueList(value);
        if (nested.isNotEmpty) return nested;
      }
    }

    return const [];
  }

  static Future<Map<String, dynamic>> getCallQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final cookie = prefs.getString("cookie") ?? "";
      final username = prefs.getString("username") ?? "";

      if (cookie.isEmpty || username.isEmpty) {
        return {
          "success": false,
          "message": "Session not found. Please login again.",
          "queue": [],
          "items": [],
        };
      }

      debugPrint('[QUEUE_API] 📡 Fetching call queue from API...');

      final response = await http
          .get(
            Uri.parse(AppConfig.callQueueApi),
            headers: {'Content-Type': 'application/json', 'Cookie': cookie},
          )
          .timeout(const Duration(seconds: 10));

      debugPrint('[QUEUE_API] Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        debugPrint('[QUEUE_API] Response body: $jsonData');

        final queueList = _extractQueueList(jsonData);

        // Filter and validate queue items
        final validQueue = <CallQueueItem>[];
        for (final item in queueList) {
          if (item is Map) {
            final queueMap = item.map(
              (key, value) => MapEntry(key.toString(), value),
            );
            if (_validateQueueItem(queueMap)) {
              try {
                final queueItem = CallQueueItem.fromMap(queueMap);
                validQueue.add(queueItem);
              } catch (e) {
                debugPrint('[QUEUE_API] ⚠️ Failed to parse queue item: $e');
              }
            }
          }
        }

        debugPrint(
          '[QUEUE_API] ✅ Queue fetched successfully - ${validQueue.length} items',
        );
        return {
          "success": true,
          "message": "Queue fetched successfully",
          "queue": validQueue,
          "items": validQueue,
          "total": validQueue.length,
        };
      } else if (response.statusCode == 401) {
        debugPrint('[QUEUE_API] ❌ Session expired - 401');
        return {
          "success": false,
          "message": "Session expired. Please login again.",
          "queue": [],
          "items": [],
        };
      } else {
        debugPrint('[QUEUE_API] ❌ API error - ${response.statusCode}');
        return {
          "success": false,
          "message": "Failed to fetch queue. Status: ${response.statusCode}",
          "queue": [],
          "items": [],
        };
      }
    } on http.ClientException catch (e) {
      debugPrint('[QUEUE_API] ❌ Network error: $e');
      return {
        "success": false,
        "message": "Network error. Please check your connection.",
        "queue": [],
        "items": [],
      };
    } catch (e) {
      debugPrint('[QUEUE_API] ❌ Unexpected error: $e');
      return {
        "success": false,
        "message": "Error: $e",
        "queue": [],
        "items": [],
      };
    }
  }

  /// Fetch call queue and return as list of CallQueueItem
  static Future<List<CallQueueItem>> fetchCallQueue() async {
    final result = await getCallQueue();
    if (result['success'] == true) {
      final queue = result['queue'] as List?;
      if (queue != null && queue.isNotEmpty) {
        return List<CallQueueItem>.from(queue);
      }
    }
    return [];
  }
}
