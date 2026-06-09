import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../models/call_queue.dart';

class CallQueueApi {
  static bool _validateQueueItem(Map<String, dynamic> item) {
    final docname = item['name']?.toString() ?? item['docname']?.toString() ?? '';
    final mobileNo = item['mobile_no']?.toString() ?? '';
    final customerName = item['customer_name']?.toString() ?? item['name']?.toString() ?? '';

    if (docname.isEmpty || mobileNo.isEmpty) {
      debugPrint('[QUEUE_API] ❌ Invalid queue item - missing required fields');
      return false;
    }

    return true;
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
          "items": []
        };
      }

      debugPrint('[QUEUE_API] 📡 Fetching call queue from API...');

      final response = await http.get(
        Uri.parse(AppConfig.callQueueApi),
        headers: {
          'Content-Type': 'application/json',
          'Cookie': cookie,
        },
      ).timeout(const Duration(seconds: 10));

      debugPrint('[QUEUE_API] Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        debugPrint('[QUEUE_API] Response body: $jsonData');

        // Handle different response formats
        List<dynamic> queueList = [];
        
        if (jsonData is Map<String, dynamic>) {
          // Check various possible response structures
          if (jsonData['data'] is List) {
            queueList = jsonData['data'] as List<dynamic>;
          } else if (jsonData['message'] is List) {
            queueList = jsonData['message'] as List<dynamic>;
          } else if (jsonData['queue'] is List) {
            queueList = jsonData['queue'] as List<dynamic>;
          }
        } else if (jsonData is List) {
          queueList = jsonData;
        }

        // Filter and validate queue items
        final validQueue = <CallQueueItem>[];
        for (final item in queueList) {
          if (item is Map<String, dynamic>) {
            if (_validateQueueItem(item)) {
              try {
                final queueItem = CallQueueItem.fromMap(item);
                validQueue.add(queueItem);
              } catch (e) {
                debugPrint('[QUEUE_API] ⚠️ Failed to parse queue item: $e');
              }
            }
          }
        }

        debugPrint('[QUEUE_API] ✅ Queue fetched successfully - ${validQueue.length} items');
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
          "items": []
        };
      } else {
        debugPrint('[QUEUE_API] ❌ API error - ${response.statusCode}');
        return {
          "success": false,
          "message": "Failed to fetch queue. Status: ${response.statusCode}",
          "queue": [],
          "items": []
        };
      }
    } on http.ClientException catch (e) {
      debugPrint('[QUEUE_API] ❌ Network error: $e');
      return {
        "success": false,
        "message": "Network error. Please check your connection.",
        "queue": [],
        "items": []
      };
    } catch (e) {
      debugPrint('[QUEUE_API] ❌ Unexpected error: $e');
      return {
        "success": false,
        "message": "Error: $e",
        "queue": [],
        "items": []
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
