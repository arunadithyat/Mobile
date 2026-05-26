import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:lead_calling/services/call_queue_storage_service.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  static final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // StreamController for handling navigation
  static final StreamController<Map<String, dynamic>> notificationStream =
      StreamController<Map<String, dynamic>>.broadcast();

  NotificationService._internal();

  factory NotificationService() {
    return _instance;
  }

  static int _buildNotificationId(Map<String, dynamic> data) {
    final seed =
        '${data['docname']}_${data['mobile_no']}_${data['queued_at'] ?? DateTime.now().toIso8601String()}';
    return seed.hashCode.abs() & 0x7fffffff;
  }

  static Map<String, dynamic>? normalizeLeadCallPayload(
    Map<String, dynamic> rawData,
  ) {
    debugPrint("[NOTIFY] normalizeLeadCallPayload input => $rawData");
    
    final merged = <String, dynamic>{};

    void merge(dynamic source) {
      if (source is Map) {
        source.forEach((key, value) {
          merged[key.toString()] = value;
        });
        return;
      }
      if (source is String) {
        try {
          final decoded = jsonDecode(source);
          if (decoded is Map) {
            decoded.forEach((key, value) {
              merged[key.toString()] = value;
            });
          }
        } catch (_) {
          // Ignore non-JSON strings
        }
      }
    }

    merge(rawData);
    merge(rawData['data']);
    merge(rawData['payload']);
    merge(rawData['message']);

    debugPrint("[NOTIFY] merged data => $merged");

    dynamic pick(List<String> keys) {
      for (final key in keys) {
        if (merged.containsKey(key) && merged[key] != null) {
          return merged[key];
        }
      }
      return null;
    }

    final type =
        (pick(['type', 'event', 'event_type']) ?? '').toString().trim();
    debugPrint("[NOTIFY] extracted type => '$type'");
    debugPrint("[NOTIFY] type.toUpperCase() => '${type.toUpperCase()}'");
    debugPrint("[NOTIFY] checking if in: ['NEW_LEAD_CALL', 'LEAD_CALL']");
    
    // Accept known types, and also allow payloads that clearly look like lead-call data.
    final hasLeadIdentity =
        (pick(['mobile_no', 'mobileNo', 'mobile', 'phone', 'phone_number']) ??
                '')
            .toString()
            .trim()
            .isNotEmpty &&
        (pick(['docname', 'doc_name', 'docName']) ?? '')
            .toString()
            .trim()
            .isNotEmpty;
    final isValidType = ['NEW_LEAD_CALL', 'LEAD_CALL'].contains(type.toUpperCase());
    debugPrint("[NOTIFY] isValidType: $isValidType");
    
    if (!isValidType && !hasLeadIdentity) {
      debugPrint("[NOTIFY] ❌ type mismatch: '$type' not in acceptable types");
      debugPrint("[NOTIFY] Raw data was: $rawData");
      return null;
    }

    final normalized = {
      'type': 'NEW_LEAD_CALL',
      'doctype': (pick(['doctype', 'doc_type', 'docType']) ?? '').toString(),
      'docname': (pick(['docname', 'doc_name', 'docName']) ?? '').toString(),
      'customer_name':
          (pick(['customer_name', 'customerName', 'customer', 'lead_name']) ??
                  'Customer')
              .toString(),
      'mobile_no':
          (pick(['mobile_no', 'mobileNo', 'mobile', 'phone', 'phone_number']) ??
                  '')
              .toString(),
      'auto_call': (pick(['auto_call', 'autoCall']) ?? '1').toString(),
      'queued_at': DateTime.now().toIso8601String(),
    };
    
    debugPrint("[NOTIFY] ✅ normalized => $normalized");
    return normalized;
  }

  Future<void> initialize() async {
    try {
      debugPrint("[INIT] initialize() method STARTED");
      
      // Initialize local notifications
      debugPrint("[INIT] Initializing local notifications...");
      const AndroidInitializationSettings androidInitializationSettings =
          AndroidInitializationSettings('ic_launcher');  // ← Changed from 'app_icon' to 'ic_launcher'

      const DarwinInitializationSettings iOSInitializationSettings =
          DarwinInitializationSettings(
        requestSoundPermission: true,
        requestBadgePermission: true,
        requestAlertPermission: true,
      );

      const InitializationSettings initializationSettings = InitializationSettings(
        android: androidInitializationSettings,
        iOS: iOSInitializationSettings,
      );

      debugPrint("[INIT] Awaiting _flutterLocalNotificationsPlugin.initialize()...");
      await _flutterLocalNotificationsPlugin.initialize(
        settings: initializationSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );
      debugPrint("[INIT] ✅ Local notifications initialized");

      // Create Android notification channel
      debugPrint("[INIT] Creating Android notification channel...");
      await _createAndroidNotificationChannel();
      debugPrint("[INIT] ✅ Android notification channel created");

      // Request iOS permissions
      debugPrint("[INIT] Requesting iOS permissions...");
      await _flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
      debugPrint("[INIT] ✅ iOS permissions requested");

      // Request notification permission on Android 13+
      // This happens silently without showing a dialog if the app isn't already running
      debugPrint("[INIT] Requesting Android notification permission...");
      try {
        final status = await Permission.notification.request();
        debugPrint("[INIT] Notification permission status: $status");
        
        if (status.isGranted) {
          debugPrint("[INIT] ✅ Notification permission granted");
        } else if (status.isDenied) {
          debugPrint("[INIT] ⚠️ Notification permission denied");
          // App will still receive notifications via FCM, just won't show in notification bar
          // User can manually enable in Settings
        } else if (status.isPermanentlyDenied) {
          debugPrint("[INIT] ⚠️ Notification permission permanently denied - open app settings to enable");
        }
      } catch (e) {
        debugPrint("[INIT] ❌ Error requesting notification permission: $e");
      }

      // Handle foreground messages
      debugPrint("[INIT] Setting up Firebase message listeners...");
      debugPrint("[LISTENER] Setting up onMessage listener...");
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint("[LISTENER] onMessage triggered!");
        debugPrint("[LISTENER] 🎉 FOREGROUND MESSAGE RECEIVED IN LISTENER!");
        _handleForegroundMessage(message);
      });
      debugPrint("[LISTENER] ✅ onMessage listener SET UP and ACTIVE");

      // Handle notification tap when app is terminated/closed
      debugPrint("[LISTENER] Setting up getInitialMessage...");
      FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
        if (message != null) {
          debugPrint("[LISTENER] getInitialMessage found message!");
          final leadData = normalizeLeadCallPayload(message.data);
          if (leadData != null) {
            notificationStream.add(leadData);
          }
        } else {
          debugPrint("[LISTENER] getInitialMessage - no message");
        }
      });
      debugPrint("[LISTENER] ✅ getInitialMessage listener SET UP");

      // Handle notification tap when app is in background
      debugPrint("[LISTENER] Setting up onMessageOpenedApp listener...");
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint("[LISTENER] onMessageOpenedApp triggered!");
        final leadData = normalizeLeadCallPayload(message.data);
        if (leadData != null) {
          notificationStream.add(leadData);
        }
      });
      debugPrint("[LISTENER] ✅ onMessageOpenedApp listener SET UP and ACTIVE");
      
      debugPrint("[LISTENER] ═══════════════════════════════════════");
      debugPrint("[LISTENER] 🎉 ALL LISTENERS SET UP AND ACTIVE");
      debugPrint("[LISTENER] ═══════════════════════════════════════");
      
      debugPrint("[INIT] initialize() method COMPLETED SUCCESSFULLY");
    } catch (e, stacktrace) {
      debugPrint("[INIT] ❌ ERROR in initialize(): $e");
      debugPrint("[INIT] Stack trace: $stacktrace");
      rethrow;
    }
  }

  Future<void> _createAndroidNotificationChannel() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'high_importance_channel',
      'High Importance Notifications',
      description: 'This channel is used for important notifications like incoming calls.',
      importance: Importance.max,
      enableVibration: true,
      enableLights: true,
      playSound: true,
    );

    await _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    debugPrint("═════════════════════════════════════════");
    debugPrint("[FOREGROUND MESSAGE] Received!");
    debugPrint("Message ID: ${message.messageId}");
    debugPrint("Sent time: ${message.sentTime}");
    debugPrint("Data field: ${message.data}");
    debugPrint("Notification field: ${message.notification}");
    debugPrint("─────────────────────────────────────────");

    // Extract data from multiple possible sources
    Map<String, dynamic> extractedData = {};
    
    // Try message.data first
    if (message.data.isNotEmpty) {
      debugPrint("[DATA SOURCE] Using message.data");
      extractedData.addAll(message.data);
    }
    
    // Also try notification fields if present
    if (message.notification != null) {
      debugPrint("[DATA SOURCE] Also found message.notification");
      extractedData['notification_title'] = message.notification!.title;
      extractedData['notification_body'] = message.notification!.body;
    }

    debugPrint("[EXTRACTED DATA] $extractedData");

    final leadData = normalizeLeadCallPayload(extractedData);
    
    debugPrint("[PAYLOAD CHECK]");
    debugPrint("Normalized data: $leadData");
    
    if (leadData != null) {
      debugPrint("[SUCCESS] ✅ Lead call payload recognized!");
      await _showCallNotification(leadData);
      notificationStream.add(leadData);
      debugPrint("[NOTIFICATION] Shown and added to stream");
    } else {
      debugPrint("[ERROR] ❌ Failed to normalize payload!");
      debugPrint("Payload structure: $extractedData");
    }
    debugPrint("═════════════════════════════════════════");
  }

  Future<void> _showCallNotification(Map<String, dynamic> data) async {
    final customerName = data['customer_name'] ?? 'Incoming Call';
    final mobileNo = data['mobile_no'] ?? 'Unknown';
    final notificationId = _buildNotificationId(data);

    final AndroidNotificationDetails androidNotificationDetails =
        AndroidNotificationDetails(
      'high_importance_channel',
      'High Importance Notifications',
      channelDescription: 'This channel is used for important notifications.',
      importance: Importance.max,
      priority: Priority.high,
      enableVibration: true,
      enableLights: true,
      playSound: true,
      fullScreenIntent: true,
      styleInformation: BigTextStyleInformation(
        'Incoming call from $customerName\n$mobileNo',
        htmlFormatBigText: true,
        contentTitle: 'Incoming Call',
        summaryText: 'Lead Call Alert',
      ),
    );

    const DarwinNotificationDetails iOSNotificationDetails =
        DarwinNotificationDetails(
      presentSound: true,
      presentBadge: true,
      presentAlert: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    final NotificationDetails notificationDetails = NotificationDetails(
      android: androidNotificationDetails,
      iOS: iOSNotificationDetails,
    );

    await _flutterLocalNotificationsPlugin.show(
      id: notificationId,
      title: 'Incoming Call',
      body: '$customerName - $mobileNo',
      notificationDetails: notificationDetails,
      payload: jsonEncode(data),
    );
  }

  Future<void> _onNotificationTapped(
    NotificationResponse notificationResponse,
  ) async {
    debugPrint('Notification tapped: ${notificationResponse.payload}');

    if (notificationResponse.payload != null && notificationResponse.payload!.isNotEmpty) {
      try {
        final Map<String, dynamic> data =
            jsonDecode(notificationResponse.payload!) as Map<String, dynamic>;
        final leadData = normalizeLeadCallPayload(data);
        if (leadData != null) {
          notificationStream.add(leadData);
        }
      } catch (e) {
        debugPrint('Error parsing notification payload: $e');
      }
    }
  }

  void dispose() {
    notificationStream.close();
  }
}

// Top-level function to handle background messages
// BUG FIX #2 & #3: Moved from NotificationService.initialize() to main.dart
// This function will be registered before runApp() in main()
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  
  // BUG FIX #3: Initialize FlutterLocalNotificationsPlugin in background isolate
  final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  
  const AndroidInitializationSettings androidInitializationSettings =
      AndroidInitializationSettings('ic_launcher');
  const DarwinInitializationSettings iOSInitializationSettings =
      DarwinInitializationSettings(
    requestSoundPermission: true,
    requestBadgePermission: true,
    requestAlertPermission: true,
  );
  const InitializationSettings initializationSettings = InitializationSettings(
    android: androidInitializationSettings,
    iOS: iOSInitializationSettings,
  );
  
  await flutterLocalNotificationsPlugin.initialize(
    settings: initializationSettings,
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      debugPrint('Background notification tapped: ${response.payload}');
    },
  );
  
  // Create notification channel in background
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'high_importance_channel',
    'High Importance Notifications',
    description: 'This channel is used for important notifications like incoming calls.',
    importance: Importance.max,
    enableVibration: true,
    enableLights: true,
    playSound: true,
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);
  
  debugPrint('========== BACKGROUND MESSAGE HANDLER ==========');
  debugPrint('[BG][PUSH] push received');
  debugPrint('Message ID: ${message.messageId}');
  debugPrint('Message data: ${message.data}');
  debugPrint('Message notification: ${message.notification}');

  // Extract data from multiple possible sources
  Map<String, dynamic> extractedData = {};
  
  // Try message.data first
  if (message.data.isNotEmpty) {
    debugPrint("[BG] Using message.data");
    extractedData.addAll(message.data);
  }
  
  // Also try notification fields if present
  if (message.notification != null) {
    debugPrint("[BG] Also found message.notification");
    extractedData['notification_title'] = message.notification!.title;
    extractedData['notification_body'] = message.notification!.body;
  }

  debugPrint("[BG] Extracted data: $extractedData");
  debugPrint("[BG][PUSH] payload parsed");

  final leadData = NotificationService.normalizeLeadCallPayload(extractedData);
  if (leadData != null) {
    debugPrint("[BG][QUEUE] queue add started");
    final queueResult = await CallQueueStorageService.addIfNotPending(leadData);
    if (!queueResult.success) {
      debugPrint("[BG][QUEUE] queue add failure: ${queueResult.message}");
    } else if (queueResult.duplicate) {
      debugPrint("[BG][QUEUE] duplicate skipped");
    } else {
      debugPrint("[BG][QUEUE] queue add success");
    }
    debugPrint("[BG] ✅ Showing notification for: ${leadData['customer_name']}");
    await _showCallNotificationInBackground(flutterLocalNotificationsPlugin, leadData);
  } else {
    debugPrint("[BG] ❌ Failed to normalize payload");
    debugPrint("[BG] Raw data was: $extractedData");
  }
  debugPrint('========== END BACKGROUND MESSAGE ==========');
}

// Helper function for background notifications
Future<void> _showCallNotificationInBackground(
  FlutterLocalNotificationsPlugin plugin,
  Map<String, dynamic> data,
) async {
  final customerName = data['customer_name'] ?? 'Incoming Call';
  final mobileNo = data['mobile_no'] ?? 'Unknown';
  
  // Use the same ID generation logic
  final seed =
      '${data['docname']}_${data['mobile_no']}_${data['queued_at'] ?? DateTime.now().toIso8601String()}';
  final notificationId = seed.hashCode.abs() & 0x7fffffff;

  final AndroidNotificationDetails androidNotificationDetails =
      AndroidNotificationDetails(
    'high_importance_channel',
    'High Importance Notifications',
    channelDescription: 'This channel is used for important notifications.',
    importance: Importance.max,
    priority: Priority.high,
    enableVibration: true,
    enableLights: true,
    playSound: true,
    fullScreenIntent: true,
    styleInformation: BigTextStyleInformation(
      'Incoming call from $customerName\n$mobileNo',
      htmlFormatBigText: true,
      contentTitle: 'Incoming Call',
      summaryText: 'Lead Call Alert',
    ),
  );

  const DarwinNotificationDetails iOSNotificationDetails =
      DarwinNotificationDetails(
    presentSound: true,
    presentBadge: true,
    presentAlert: true,
    interruptionLevel: InterruptionLevel.timeSensitive,
  );

  final NotificationDetails notificationDetails = NotificationDetails(
    android: androidNotificationDetails,
    iOS: iOSNotificationDetails,
  );

  await plugin.show(
    id: notificationId,
    title: 'Incoming Call',
    body: '$customerName - $mobileNo',
    notificationDetails: notificationDetails,
    payload: jsonEncode(data),
  );
}
