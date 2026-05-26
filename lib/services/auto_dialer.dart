import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AutoDialer {
  static const MethodChannel _channel = MethodChannel('lead_calling/dialer');

  static String _cleanNumber(String phoneNumber) {
    return phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
  }

  static Future<bool> autoCall(String phoneNumber) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      debugPrint('[DIALER] Unsupported platform: ${Platform.operatingSystem}');
      return false;
    }

    final cleanedNumber = _cleanNumber(phoneNumber);
    debugPrint('[DIALER] 📞 Auto-dialing: $cleanedNumber');

    try {
      final result = await _channel.invokeMethod<bool>(
        'autoCall',
        {'phoneNumber': cleanedNumber},
      );

      if (result == true) {
        debugPrint('[DIALER] ✅ Auto-dial initiated successfully');
        return true;
      }

      debugPrint('[DIALER] ❌ Auto-dial platform call returned false');
      return await openDialer(cleanedNumber);
    } catch (e) {
      debugPrint('[DIALER] ❌ Auto-dial error: $e');
      return await openDialer(cleanedNumber);
    }
  }

  static Future<bool> openDialer(String phoneNumber) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      debugPrint('[DIALER] Unsupported platform: ${Platform.operatingSystem}');
      return false;
    }

    final cleanedNumber = _cleanNumber(phoneNumber);
    debugPrint('[DIALER] 📞 Opening dialer for: $cleanedNumber');

    try {
      final result = await _channel.invokeMethod<bool>(
        'openDialer',
        {'phoneNumber': cleanedNumber},
      );

      if (result == true) {
        debugPrint('[DIALER] ✅ Dialer opened');
        return true;
      }

      debugPrint('[DIALER] ❌ openDialer platform call returned false');
      return false;
    } catch (e) {
      debugPrint('[DIALER] ❌ Dialer error: $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>> getLastCallInfo(String phoneNumber) async {
    if (!Platform.isAndroid) {
      debugPrint('[DIALER] Call log fetch is only supported on Android');
      return {
        'found': false,
        'durationSeconds': 0,
        'callStatus': 'Unsupported',
        'disconnectedStatus': 'Unsupported',
        'attended': false,
      };
    }

    final cleanedNumber = _cleanNumber(phoneNumber);
    debugPrint('[DIALER] 📞 Fetching last call info for: $cleanedNumber');

    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'getLastCallInfo',
        {'phoneNumber': cleanedNumber},
      );

      if (result != null) {
        return result;
      }
    } catch (e) {
      debugPrint('[DIALER] ❌ getLastCallInfo error: $e');
    }

    return {
      'found': false,
      'durationSeconds': 0,
      'callStatus': 'Unknown',
      'disconnectedStatus': 'Unknown',
      'attended': false,
    };
  }

  static Future<Map<String, dynamic>> getLastCallInfoForSession(
    String phoneNumber, {
    required DateTime initiatedAt,
  }) async {
    if (!Platform.isAndroid) {
      return {
        'found': false,
        'durationSeconds': 0,
        'callStatus': 'Unknown',
        'disconnectedStatus': 'Unsupported',
        'attended': false,
        'timestamp': 0,
      };
    }

    final cleanedNumber = _cleanNumber(phoneNumber);
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'getLastCallInfo',
        {
          'phoneNumber': cleanedNumber,
          'initiatedAtMs': initiatedAt.millisecondsSinceEpoch,
        },
      );
      if (result != null) return result;
    } catch (e) {
      debugPrint('[DIALER] ❌ getLastCallInfoForSession error: $e');
    }

    return {
      'found': false,
      'durationSeconds': 0,
      'callStatus': 'Unknown',
      'disconnectedStatus': 'Unknown',
      'attended': false,
      'timestamp': 0,
    };
  }

  static Future<bool> ensureCallLogPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final granted = await _channel.invokeMethod<bool>('ensureCallLogPermission');
      return granted == true;
    } catch (e) {
      debugPrint('[DIALER] ❌ ensureCallLogPermission error: $e');
      return false;
    }
  }
}
