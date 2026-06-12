import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One outgoing call attempt made through the app.
class CallHistoryEntry {
  final String customerName;
  final String mobileNo;
  final String doctype;
  final String docname;
  final String status; // Connected / Missed / Not Answered / Cancelled
  final int durationSeconds;
  final DateTime calledAt;

  CallHistoryEntry({
    required this.customerName,
    required this.mobileNo,
    required this.doctype,
    required this.docname,
    required this.status,
    required this.durationSeconds,
    required this.calledAt,
  });

  Map<String, dynamic> toMap() => {
        'customer_name': customerName,
        'mobile_no': mobileNo,
        'doctype': doctype,
        'docname': docname,
        'status': status,
        'duration_seconds': durationSeconds,
        'called_at': calledAt.toIso8601String(),
      };

  factory CallHistoryEntry.fromMap(Map<String, dynamic> m) => CallHistoryEntry(
        customerName: m['customer_name'] ?? '',
        mobileNo: m['mobile_no'] ?? '',
        doctype: m['doctype'] ?? '',
        docname: m['docname'] ?? '',
        status: m['status'] ?? 'Unknown',
        durationSeconds: m['duration_seconds'] is int
            ? m['duration_seconds'] as int
            : int.tryParse(m['duration_seconds']?.toString() ?? '0') ?? 0,
        calledAt: m['called_at'] != null
            ? DateTime.tryParse(m['called_at']) ?? DateTime.now()
            : DateTime.now(),
      );
}

/// Local store for outgoing call history. Backed by SharedPreferences for
/// now — will be replaced/augmented by the backend Call Log API later.
class CallHistoryStorage {
  static const _key = 'call_history';
  static const _maxEntries = 200;

  static Future<void> add(CallHistoryEntry entry) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_key) ?? [];
      list.insert(0, jsonEncode(entry.toMap())); // newest first
      if (list.length > _maxEntries) {
        list.removeRange(_maxEntries, list.length);
      }
      await prefs.setStringList(_key, list);
      debugPrint(
          '[HISTORY] Saved: ${entry.customerName} / ${entry.status} / ${entry.durationSeconds}s');
    } catch (e) {
      debugPrint('[HISTORY] Save failed: $e');
    }
  }

  static Future<List<CallHistoryEntry>> getAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final list = prefs.getStringList(_key) ?? [];
      return list
          .map((s) {
            try {
              return CallHistoryEntry.fromMap(
                  Map<String, dynamic>.from(jsonDecode(s) as Map));
            } catch (_) {
              return null;
            }
          })
          .whereType<CallHistoryEntry>()
          .toList();
    } catch (e) {
      debugPrint('[HISTORY] Load failed: $e');
      return [];
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
