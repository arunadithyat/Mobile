import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/call_queue.dart';

class QueueAddResult {
  final bool success;
  final bool duplicate;
  final String message;
  final CallQueueItem? item;

  const QueueAddResult({
    required this.success,
    this.duplicate = false,
    required this.message,
    this.item,
  });
}

class CallQueueStorageService {
  static const String _pendingQueueKey = 'pending_call_queue_v1';
  static Future<void> _op = Future.value();
  static SharedPreferences? _prefs;

  static String buildQueueKey({
    required String docname,
    required String mobileNo,
  }) {
    return '${docname.trim().toLowerCase()}::${mobileNo.trim()}';
  }

  static Future<T> _withLock<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _op = _op.then((_) async {
      try {
        completer.complete(await action());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  static Future<SharedPreferences> _getPrefs() async =>
      _prefs ??= await SharedPreferences.getInstance();

  static Future<List<Map<String, dynamic>>> _readRawQueue() async {
    final prefs = await _getPrefs();
    final raw = prefs.getString(_pendingQueueKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('[QUEUE][STORE] Failed to parse queue JSON: $e');
      return [];
    }
  }

  static Future<void> _writeRawQueue(List<Map<String, dynamic>> queue) async {
    final prefs = await _getPrefs();
    await prefs.setString(_pendingQueueKey, jsonEncode(queue));
  }

  static Future<QueueAddResult> addIfNotPending(Map<String, dynamic> payload) {
    return _withLock(() async {
      debugPrint('[QUEUE][ADD] queue add started');

      final type = (payload['type'] ?? '').toString().trim().toUpperCase();
      final docname = (payload['docname'] ?? '').toString().trim();
      final mobileNo = (payload['mobile_no'] ?? '').toString().trim();

      if (type.isNotEmpty && type != 'LEAD_CALL' && type != 'NEW_LEAD_CALL') {
        return const QueueAddResult(
          success: false,
          message: 'invalid_type',
        );
      }
      if (docname.isEmpty || mobileNo.isEmpty) {
        return const QueueAddResult(
          success: false,
          message: 'missing_docname_or_mobile',
        );
      }

      final key = buildQueueKey(docname: docname, mobileNo: mobileNo);
      final queue = await _readRawQueue();
      final alreadyPending = queue.any((entry) {
        final eDoc = (entry['docname'] ?? '').toString().trim();
        final eMob = (entry['mobile_no'] ?? '').toString().trim();
        return buildQueueKey(docname: eDoc, mobileNo: eMob) == key;
      });

      if (alreadyPending) {
        debugPrint('[QUEUE][ADD] duplicate skipped key=$key');
        return const QueueAddResult(
          success: true,
          duplicate: true,
          message: 'duplicate_skipped',
        );
      }

      final normalized = <String, dynamic>{
        'type': 'NEW_LEAD_CALL',
        'doctype': (payload['doctype'] ?? '').toString(),
        'docname': docname,
        'customer_name': (payload['customer_name'] ?? 'Customer').toString(),
        'mobile_no': mobileNo,
        'auto_call': (payload['auto_call'] ?? '1').toString(),
        'queued_at': (payload['queued_at'] ?? DateTime.now().toIso8601String())
            .toString(),
      };
      queue.add(normalized);
      await _writeRawQueue(queue);
      debugPrint('[QUEUE][ADD] queue add success key=$key len=${queue.length}');

      return QueueAddResult(
        success: true,
        message: 'added',
        item: CallQueueItem.fromMap(normalized),
      );
    }).catchError((e) {
      debugPrint('[QUEUE][ADD] queue add failure: $e');
      return QueueAddResult(success: false, message: 'add_failed: $e');
    });
  }

  static Future<List<CallQueueItem>> loadPendingQueue() async {
    return _withLock(() async {
      final raw = await _readRawQueue();
      return raw.map(CallQueueItem.fromMap).toList();
    });
  }

  static Future<void> removePendingByKey({
    required String docname,
    required String mobileNo,
  }) async {
    await _withLock(() async {
      final key = buildQueueKey(docname: docname, mobileNo: mobileNo);
      final queue = await _readRawQueue();
      queue.removeWhere((entry) {
        final eDoc = (entry['docname'] ?? '').toString().trim();
        final eMob = (entry['mobile_no'] ?? '').toString().trim();
        return buildQueueKey(docname: eDoc, mobileNo: eMob) == key;
      });
      await _writeRawQueue(queue);
      debugPrint('[QUEUE][REMOVE] removed key=$key len=${queue.length}');
    });
  }

  static Future<void> clearAll() async {
    await _withLock(() async {
      await _writeRawQueue([]);
      debugPrint('[QUEUE][CLEAR] all entries cleared');
    });
  }
}
