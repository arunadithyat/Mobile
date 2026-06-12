
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:lead_calling/services/auto_dialer.dart';
import 'package:lead_calling/api/call_log_api.dart';
import 'package:lead_calling/screens/call_completion_dialog.dart';
import 'package:lead_calling/screens/call_queue_screen.dart';
import 'package:lead_calling/screens/webview_screen.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api/device_api.dart';
import 'api/login_api.dart';
import 'api/call_queue_api.dart';
import 'config.dart';
import 'services/notification_service.dart';
import 'models/call_queue.dart';
import 'services/call_history_storage.dart';
import 'screens/call_history_tab.dart';
import 'services/message_service.dart';

/// Launches the phone dialer to call the given phone number
Future<bool> launchPhoneCall(String phoneNumber) async {
  return await AutoDialer.openDialer(phoneNumber);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  debugPrint("═════════════════════════════════════════");
  debugPrint("[FIREBASE] Initializing Firebase...");
  
  try {
    await Firebase.initializeApp();
    debugPrint("[FIREBASE] ✅ Firebase initialized successfully");
  } catch (e) {
    debugPrint("[FIREBASE] ❌ Firebase initialization failed: $e");
    rethrow;
  }
  
  debugPrint("[FIREBASE] Setting up background message handler...");
  // BUG FIX #2: Register background handler BEFORE runApp()
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  debugPrint("[FIREBASE] ✅ Background handler registered");
  
  debugPrint("[AUTH] Checking session...");
  // Check if user is already logged in
  final isLoggedIn = await LoginApi.checkSession();
  debugPrint("[AUTH] Session check result: isLoggedIn=$isLoggedIn");
  
  debugPrint("═════════════════════════════════════════");
  runApp(MyApp(isLoggedIn: isLoggedIn));
}

class MyApp extends StatelessWidget {
  final bool isLoggedIn;
  
  const MyApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "Homegenie Call App",
      home: isLoggedIn ? const HomePage() : const LoginPage(),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final userController = TextEditingController();
  final passController = TextEditingController();

  bool loading = false;

  Future<void> login() async {
    setState(() => loading = true);

    final result = await LoginApi.login(
      userController.text.trim(),
      passController.text.trim(),
    );

    if (!mounted) return;
    setState(() => loading = false);

    if (result["success"] == true) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomePage()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result["message"] ?? "Login Failed")),
      );
    }
  }

  @override
  void dispose() {
    userController.dispose();
    passController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Homegenie Call App"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 50),
            TextField(
              controller: userController,
              decoration: const InputDecoration(
                labelText: "Username",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: passController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: "Password",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: loading ? null : login,
                child: loading
                    ? const CircularProgressIndicator()
                    : const Text("LOGIN"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  String token = "";
  // Opportunities removed — queue is the main data source
  DateTime? pausedUntil;
  Timer? _pauseTimer;
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<Map<String, dynamic>>? _notificationSub;
  // Fix #2 & #7: Thread-safe duplicate detection with Set<String>
  Set<String> _recentLeadCalls = {};
  DateTime? _lastPushReceivedAt;
  String _lastPushSource = "-";
  String _lastPushAction = "-";
  int _pushReceivedCount = 0;
  Map<String, dynamic>? _lastPushRaw;
  Map<String, dynamic>? _lastPushNormalized;
  final CallQueue callQueue = CallQueue();
  bool _isLeadCallInProgress = false;
  bool _processingLock = false; // Prevents race condition on simultaneous notifications
  int _currentTab = 0; // 0 = Call Queue, 1 = Call History
  String _pauseReason = "";

  bool get isCallFlowPaused {
    if (pausedUntil == null) return false;
    return DateTime.now().isBefore(pausedUntil!);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  /// Permissions must be requested SEQUENTIALLY — Android silently drops a
  /// permission dialog if another one is already showing. This is why the
  /// notification permission was never asked on fresh installs.
  Future<void> _bootstrap() async {
    await _requestCallTelemetryPermissions();
    final notifStatus = await Permission.notification.request();
    debugPrint("[BOOT] Notification permission: $notifStatus");
    await getFcmToken();
    await _initializeNotifications();
    _listenForTokenRefresh();
    await _loadPendingQueue();
    await _drainBackgroundQueuedCalls();
    await _syncIncomingDeviceCalls();
    // Opportunities are loaded manually via Pull-to-refresh only
  }

  /// Reads the device call log for incoming/missed calls since the last
  /// sync and sends them to the backend. The backend matches numbers
  /// against Lead/Opportunity and creates Call Log entries when relevant.
  Future<void> _syncIncomingDeviceCalls() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastSyncMs = prefs.getInt('last_incoming_sync') ?? 0;
      // First run: look back 24h; after that, only since last sync
      final since = lastSyncMs > 0
          ? DateTime.fromMillisecondsSinceEpoch(lastSyncMs)
          : DateTime.now().subtract(const Duration(hours: 24));

      final calls = await AutoDialer.getIncomingCallsSince(since);
      debugPrint("[INCOMING_SYNC] Found ${calls.length} incoming call(s) since $since");
      if (calls.isEmpty) {
        await prefs.setInt('last_incoming_sync', DateTime.now().millisecondsSinceEpoch);
        return;
      }

      final ok = await IncomingCallSyncApi.syncIncomingCalls(calls);
      if (ok) {
        // Only advance the watermark on a successful sync, so failed
        // batches are retried on the next run
        await prefs.setInt('last_incoming_sync', DateTime.now().millisecondsSinceEpoch);
        debugPrint("[INCOMING_SYNC] ✅ Synced and watermark updated");
      } else {
        debugPrint("[INCOMING_SYNC] ⚠️ Sync failed — will retry next launch/resume");
      }
    } catch (e) {
      debugPrint("[INCOMING_SYNC] Error: $e");
    }
  }

  /// Calls received via FCM while the app was in background/killed are
  /// persisted by the background handler. Drain them into the queue here.
  Future<void> _drainBackgroundQueuedCalls() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // CRITICAL: the background isolate wrote to disk, but this isolate's
      // SharedPreferences cache is stale — reload() re-reads from disk.
      await prefs.reload();
      final stored = prefs.getStringList('bg_pending_calls') ?? [];
      debugPrint("[QUEUE][BG] Drain check — found ${stored.length} stored call(s)");
      if (stored.isEmpty) return;
      await prefs.remove('bg_pending_calls');
      debugPrint("[QUEUE][BG] Draining ${stored.length} background call(s) into queue");
      for (final s in stored) {
        try {
          final data = Map<String, dynamic>.from(jsonDecode(s) as Map);
          await _enqueueLeadCall(data, reason: 'background_fcm');
        } catch (e) {
          debugPrint("[QUEUE][BG] Failed to parse stored call: $e");
        }
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("[QUEUE][BG] Drain error: $e");
    }
  }

  Future<void> _requestCallTelemetryPermissions() async {
    debugPrint("[PERM] 🔐 Requesting call telemetry permissions...");
    
    final phoneStatus = await Permission.phone.request();
    debugPrint("[PERM] phone permission: $phoneStatus");
    debugPrint("[PERM] phone permission granted: ${phoneStatus.isGranted ? '✅ YES' : '❌ NO'}");
    
    final callLogReady = await AutoDialer.ensureCallLogPermission();
    debugPrint("[PERM] call log permission ready: $callLogReady");
    debugPrint("[PERM] READ_CALL_LOG permission: ${callLogReady ? '✅ GRANTED' : '❌ DENIED/NOT_REQUESTED'}");
    debugPrint("[PERM] ✅ Permission request cycle complete");
  }

  Future<void> _loadPendingQueue() async {
    try {
      debugPrint("[QUEUE][LOAD] Fetching call queue from API...");
      final result = await CallQueueApi.getCallQueue();
      if (!mounted) return;
      
      if (result['success'] == true) {
        final queueItems = result['queue'] as List<dynamic>? ?? [];
        setState(() {
          callQueue.clearAll();
          if (queueItems.isNotEmpty) {
            for (final item in queueItems) {
              if (item is CallQueueItem &&
                  !callQueue.containsCall(item.docname, item.mobileNo)) {
                callQueue.addItem(item);
              }
            }
          }
        });
        debugPrint("[QUEUE][LOAD] ✅ Loaded queue from API - ${queueItems.length} items");
      } else {
        debugPrint("[QUEUE][LOAD] ❌ API error: ${result['message']}");
      }
    } catch (e) {
      debugPrint("[QUEUE][LOAD] ❌ Failed to load queue from API: $e");
    }
  }

  Future<void> _enqueueLeadCall(
    Map<String, dynamic> normalized, {
    required String reason,
  }) async {
    final docname = normalized['docname']?.toString() ?? '';
    final mobileNo = normalized['mobile_no']?.toString() ?? '';

    // Duplicate guard — same doc + number must not be queued twice
    if (callQueue.containsCall(docname, mobileNo)) {
      debugPrint(
          "[QUEUE][FLOW] ⏭️ Skipped duplicate ($reason) — $docname / $mobileNo already in queue");
      return;
    }

    debugPrint("[QUEUE][FLOW] Adding to in-memory queue - reason=$reason");
    final item = CallQueueItem.fromMap(normalized);
    setState(() {
      callQueue.addItem(item);
    });
    debugPrint("[QUEUE][FLOW] ✅ Added to queue - queue length=${callQueue.length}");
  }

  Future<void> _initializeNotifications() async {
    debugPrint("[INIT] Starting notification initialization...");
    
    _notificationSub?.cancel();
    _notificationSub =
        NotificationService.notificationStream.stream.listen((data) {
          debugPrint("[STREAM] Notification stream received: $data");
          _handleIncomingLeadCall(data, source: "notification_stream");
        });

    // Initialize notification service
    await NotificationService().initialize();
    debugPrint("[INIT] NotificationService initialized");
    
    debugPrint("[INIT] ✅ Notification initialization complete");
  }

  Future<void> getFcmToken() async {
    final messaging = FirebaseMessaging.instance;

    debugPrint("═════════════════════════════════════════");
    debugPrint("[FCM] Starting FCM initialization...");
    
    // Request permissions
    debugPrint("[FCM] Requesting notification permissions...");
    final settings = await messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
    debugPrint("[FCM] Permission status: ${settings.authorizationStatus}");
    debugPrint("[FCM] Authorization status details:");
    debugPrint("     - isEnabled: ${settings.authorizationStatus == AuthorizationStatus.authorized}");
    debugPrint("     - isSilent: ${settings.authorizationStatus == AuthorizationStatus.provisional}");
    debugPrint("     - isDenied: ${settings.authorizationStatus == AuthorizationStatus.denied}");

    // Force delete cached token on every login so Firebase issues a fresh one.
    // This ensures the backend upserts (updates existing device entry for this
    // user+device instead of creating a duplicate on reinstall).
    debugPrint("[FCM] Deleting cached FCM token to force refresh on login...");
    try {
      await messaging.deleteToken();
      debugPrint("[FCM] Cached token deleted");
    } catch (e) {
      debugPrint("[FCM] Could not delete token (non-fatal): $e");
    }

    // Get fresh token after deletion
    debugPrint("[FCM] Getting fresh FCM token...");
    final fcmToken = await messaging.getToken();

    debugPrint("═════════════════════════════════════════");
    debugPrint("FCM TOKEN => $fcmToken");
    debugPrint("Token length: ${(fcmToken ?? "").length}");

    if (!mounted) return;

    setState(() {
      token = fcmToken ?? "";
    });

    if ((fcmToken ?? "").isNotEmpty) {
      debugPrint("📱 Registering device with token...");
      final registerResult = await DeviceApi.registerDevice(fcmToken!);
      debugPrint("REGISTER DEVICE RESULT => $registerResult");
      
      if (registerResult["success"] != true) {
        debugPrint("❌ Device registration failed: ${registerResult['message']}");
      } else {
        debugPrint("✅ Device registered successfully");
      }
    } else {
      debugPrint("❌ FCM Token is empty!");
    }
    debugPrint("═════════════════════════════════════════");
  }

  void _listenForTokenRefresh() {
    debugPrint("[FCM] Setting up token refresh listener...");
    _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen((
      refreshedToken,
    ) async {
      debugPrint("[FCM] 🔄 Token refreshed! New token: $refreshedToken");
      if (!mounted) return;
      setState(() {
        token = refreshedToken;
      });
      final registerResult = await DeviceApi.registerDevice(refreshedToken);
      debugPrint("REGISTER REFRESHED TOKEN => $registerResult");
    });
    debugPrint("[FCM] ✅ Token refresh listener set up");
  }


  Future<void> _handleCallBatch(
    Map<String, dynamic> batchData, {
    String source = "unknown",
  }) async {
    debugPrint("========== HANDLE CALL BATCH ==========");
    debugPrint("Source: $source");
    debugPrint("Batch Name: ${batchData['call_batch_name']}");
    debugPrint("Total Leads: ${batchData['total_leads']}");
    debugPrint("Is paused: $isCallFlowPaused");
    debugPrint("Queue length: ${callQueue.length}");
    
    if (!mounted) {
      debugPrint("❌ Not mounted, ignoring batch");
      return;
    }

    final totalLeads = batchData['total_leads'] ?? 0;
    final leads = batchData['leads'] ?? [];

    debugPrint("Processing ${leads.length} leads from batch");

    // Show notification about batch arrival
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Call Batch Added with Count: $totalLeads'),
        duration: const Duration(seconds: 3),
      ),
    );

    // Normalize and deduplicate all leads up front
    final normalizedLeads = <Map<String, dynamic>>[];
    for (int i = 0; i < leads.length; i++) {
      final leadData = leads[i];
      final normalized = NotificationService.normalizeLeadCallPayload(
        leadData is Map ? Map<String, dynamic>.from(leadData as Map) : {},
      );
      if (normalized == null) {
        debugPrint("[BATCH] ❌ Failed to normalize lead at index $i");
        continue;
      }
      if (_isDuplicateLeadCall(normalized)) {
        debugPrint("[BATCH] ⏭️ Skipping duplicate: ${normalized['docname']}");
        continue;
      }
      normalizedLeads.add(normalized);
    }

    if (normalizedLeads.isEmpty) {
      debugPrint("[BATCH] No valid leads to process");
      return;
    }

    final processFirstImmediately = !isCallFlowPaused && !_isLeadCallInProgress;

    // Queue all leads that won't be processed immediately — do this FIRST
    // so the queue badge appears before the first call screen opens.
    final queueStartIndex = processFirstImmediately ? 1 : 0;
    for (int i = queueStartIndex; i < normalizedLeads.length; i++) {
      await _enqueueLeadCall(normalizedLeads[i], reason: "batch_queued");
      if (!mounted) return;
    }

    if (processFirstImmediately) {
      debugPrint("[BATCH] ✅ Processing first lead immediately");
      setState(() { _isLeadCallInProgress = true; });

      final routeResult = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LeadCallScreen(data: normalizedLeads[0]),
        ),
      );

      if (!mounted) return;
      setState(() { _isLeadCallInProgress = false; });

      // Re-queue the first lead if the user cancelled it
      if (routeResult is Map<String, dynamic> && routeResult['status'] == 'cancelled') {
        debugPrint("[BATCH] ℹ️ First lead cancelled — re-queuing");
        await _enqueueLeadCall(normalizedLeads[0], reason: "batch_first_cancelled");
      }
    }

    debugPrint("[BATCH] ========== BATCH PROCESSING COMPLETE ==========");
    debugPrint("[BATCH] Total valid leads: ${normalizedLeads.length}");
    debugPrint("[BATCH] Queue length after batch: ${callQueue.length}");
    debugPrint("========== END CALL BATCH ==========");
  }

  Future<void> _handleIncomingLeadCall(
    Map<String, dynamic> data, {
    String source = "unknown",
  }) async {
    debugPrint("========== HANDLE INCOMING NOTIFICATION ==========");
    debugPrint("Source: $source");
    debugPrint("Raw data: $data");
    
    if (!mounted) {
      debugPrint("❌ Not mounted, ignoring");
      return;
    }

    // Check if this is a CALL_BATCH
    final batchData = NotificationService.normalizeCallBatchPayload(data);
    if (batchData != null && batchData["type"] == "CALL_BATCH") {
      debugPrint("✅ Detected CALL_BATCH - routing to batch handler");
      await _handleCallBatch(batchData, source: source);
      return;
    }

    // Otherwise, process as single LEAD_CALL (existing logic)
    debugPrint("========== HANDLE INCOMING LEAD CALL ==========");
    debugPrint("Is paused: $isCallFlowPaused");
    debugPrint("Queue length: ${callQueue.length}");

    final normalized = NotificationService.normalizeLeadCallPayload(data);
    debugPrint("Normalized: $normalized");
    
    setState(() {
      _pushReceivedCount++;
      _lastPushReceivedAt = DateTime.now();
      _lastPushSource = source;
      _lastPushRaw = Map<String, dynamic>.from(data);
      _lastPushNormalized = normalized != null
          ? Map<String, dynamic>.from(normalized)
          : null;
    });

    if (normalized == null) {
      debugPrint("❌ Lead payload ignored after normalize => $data");
      setState(() {
        _lastPushAction = "ignored_invalid_payload";
      });
      return;
    }
    
    if (_isDuplicateLeadCall(normalized)) {
      debugPrint("❌ Duplicate call detected");
      setState(() {
        _lastPushAction = "ignored_duplicate";
      });
      return;
    }

    // If already processing a call OR lock is held by another notification, queue immediately
    if (isCallFlowPaused || _isLeadCallInProgress || _processingLock) {
      debugPrint("⏸️ Call flow busy. Adding to queue...");
      final reason = isCallFlowPaused
          ? "paused_flow"
          : _processingLock
              ? "processing_lock"
              : "already_in_call";
      await _enqueueLeadCall(normalized, reason: reason);
      if (!mounted) return;
      setState(() {
        _lastPushAction = "queued_$reason";
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Call from ${normalized["customer_name"] ?? "Unknown"} queued',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      debugPrint("========== END INCOMING LEAD CALL ==========");
      return;
    }

    debugPrint("✅ Navigating to LeadCallScreen");
    // Acquire lock immediately to prevent race condition
    _processingLock = true;
    setState(() {
      _isLeadCallInProgress = true;
    });
    final routeResult = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LeadCallScreen(data: normalized),
      ),
    );
    if (!mounted) return;
    setState(() {
      _isLeadCallInProgress = false;
    });
    _processingLock = false;
    if (routeResult is Map<String, dynamic> && routeResult['status'] == 'cancelled') {
      // Add back to queue as pending — user can process it later
      await _enqueueLeadCall(normalized, reason: "manual_cancel");
      if (!mounted) return;
      debugPrint("[QUEUE] Call cancelled — re-queued as pending");
    }
    setState(() {
      _lastPushAction = "navigated_to_lead_call_screen";
    });
    debugPrint("========== END INCOMING LEAD CALL ==========");
  }

  void _showCallQueueScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallQueueScreen(
          callQueue: callQueue,
          onReorder: (oldIndex, newIndex) {
            setState(() {
              callQueue.reorder(oldIndex, newIndex);
            });
          },
          onMarkCancelled: (index) {
            setState(() {
              callQueue.markCancelled(index);
            });
            debugPrint("[QUEUE] Marked cancelled at index=$index");
          },
          onRestorePending: (index) {
            setState(() {
              callQueue.restorePending(index);
            });
            debugPrint("[QUEUE] Restored pending at index=$index");
          },
        ),
      ),
    ).then((selectedIndex) async {
      if (selectedIndex != null && selectedIndex is int) {
        final callItem = callQueue.get(selectedIndex);
        if (callItem != null) {
          // DON'T remove yet — keep in queue until we know the outcome
          _processingLock = true;
          setState(() { _isLeadCallInProgress = true; });

          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => LeadCallScreen(data: callItem.toMap()),
            ),
          );

          if (!mounted) return;
          setState(() { _isLeadCallInProgress = false; });
          _processingLock = false;

          // User cancelled — keep call in queue as PENDING (no strikethrough)
          if (result is Map<String, dynamic> && result['status'] == 'cancelled') {
            // Item stays at same position, status remains pending
            debugPrint("[QUEUE] Call cancelled — kept in queue as pending at index=$selectedIndex");
            return;
          }

          // Call was not answered — keep in queue as pending for retry
          if (result is Map<String, dynamic> && result['status'] == 'not_connected') {
            debugPrint("[QUEUE] Not connected — kept in queue as pending at index=$selectedIndex");
            return;
          }

          // Call completed successfully — now remove it
          setState(() {
            callQueue.remove(selectedIndex);
          });

          // Auto-process next pending call
          if (callQueue.pendingCount > 0) {
            _processFirstQueuedCall();
          }
        }
      }
    });
  }

  bool _isDuplicateLeadCall(Map<String, dynamic> data) {
    // Fix #7: Null-safe duplicate detection with Set<String>
    final docname = data["docname"]?.toString();
    final mobileNo = data["mobile_no"]?.toString();
    final customerName = data["customer_name"]?.toString();
    
    if (docname == null || mobileNo == null || customerName == null) {
      return false;
    }
    
    final key = '${docname}_${mobileNo}_${customerName}';
    if (_recentLeadCalls.contains(key)) {
      return true;
    }
    
    _recentLeadCalls.add(key);
    // Clean up old entries after 5 seconds to prevent memory bloat
    Future.delayed(const Duration(seconds: 5), () {
      _recentLeadCalls.remove(key);
    });
    
    return false;
  }

  Future<void> toggleCallFlow() async {
    if (isCallFlowPaused) {
      // Resume call flow
      _pauseTimer?.cancel();
      setState(() {
        pausedUntil = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Call flow resumed")),
      );
      
      // Auto-process next pending call directly without showing dialog
      if (callQueue.pendingCount > 0) {
        _processFirstQueuedCall();
      }
    } else {
      // Pause call flow for a selected reason
      final picked = await _selectPauseReason();
      if (picked == null || !mounted) return;
      final reason = picked.key;
      final minutes = picked.value;

      _pauseReason = reason;
      final until = DateTime.now().add(Duration(minutes: minutes));
      _pauseTimer?.cancel();
      _pauseTimer = Timer(Duration(minutes: minutes), () {
        if (!mounted) return;
        setState(() {
          pausedUntil = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Pause interval ended. Call flow resumed")),
        );
        if (callQueue.pendingCount > 0) {
          _processFirstQueuedCall();
        }
      });

      setState(() {
        pausedUntil = until;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("$reason — paused for $minutes minute(s)")),
      );
    }
  }

  /// Pause reasons mapped to their default durations (minutes).
  static const Map<String, int> _pauseReasons = {
    "Break": 15,
    "Lunch": 45,
    "Meeting": 30,
  };

  Future<MapEntry<String, int>?> _selectPauseReason() async {
    String selected = "Break";
    return showDialog<MapEntry<String, int>>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Pause Call Flow"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Select reason", style: TextStyle(fontSize: 13)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: selected,
                decoration: InputDecoration(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                items: _pauseReasons.entries
                    .map((e) => DropdownMenuItem(
                          value: e.key,
                          child: Text("${e.key}  (${e.value} min)"),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setDialogState(() => selected = v);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(
                context,
                MapEntry(selected, _pauseReasons[selected]!),
              ),
              child: const Text("Pause"),
            ),
          ],
        ),
      ),
    );
  }

  void _showQueueProcessingOption() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Process Queued Calls?"),
        content: Text(
          "You have ${callQueue.length} call(s) in the queue.\nWould you like to process them?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Later"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _processFirstQueuedCall();
            },
            child: const Text("Process"),
          ),
        ],
      ),
    );
  }

  Future<void> _processFirstQueuedCall() async {
    // Find first PENDING call — do NOT remove it yet.
    // It only leaves the queue after a successful completion.
    int? targetIndex;
    for (int i = 0; i < callQueue.length; i++) {
      final item = callQueue.get(i);
      if (item != null && item.isPending) {
        targetIndex = i;
        break;
      }
    }
    if (targetIndex == null || !mounted) return;
    await _processQueuedCallAt(targetIndex);
  }

  /// Calls a specific queued item (used by the per-row phone button).
  Future<void> _processQueuedCallAt(int targetIndex) async {
    if (!mounted) return;
    final call = callQueue.get(targetIndex);
    if (call == null || !call.isPending) return;
    if (_isLeadCallInProgress || _processingLock) return;

    _processingLock = true;
    setState(() { _isLeadCallInProgress = true; });

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LeadCallScreen(data: call.toMap()),
      ),
    );

    if (!mounted) return;
    setState(() { _isLeadCallInProgress = false; });
    _processingLock = false;

    // User cancelled (countdown or dialpad) — customer not ready right now.
    // Move this call to the END of the queue and continue with the next one,
    // so the team isn't stuck retrying the same customer.
    if (result is Map<String, dynamic> && result['status'] == 'cancelled') {
      debugPrint("[QUEUE] Cancelled — moved to end of queue, processing next");
      setState(() {
        callQueue.moveToEnd(targetIndex);
      });
      if (callQueue.pendingCount > 1) {
        _processFirstQueuedCall();
      }
      return;
    }

    // Not answered — same treatment: move to end, try the next customer
    if (result is Map<String, dynamic> && result['status'] == 'not_connected') {
      debugPrint("[QUEUE] Not connected — moved to end of queue, processing next");
      setState(() {
        callQueue.moveToEnd(targetIndex);
      });
      if (callQueue.pendingCount > 1) {
        _processFirstQueuedCall();
      }
      return;
    }

    // Call completed — NOW remove it from the queue
    setState(() {
      callQueue.remove(targetIndex);
    });
    debugPrint("[QUEUE] Call completed — removed from queue");

    // Auto-process next pending call
    if (callQueue.pendingCount > 0) {
      _processFirstQueuedCall();
    }
  }

  Future<void> logout() async {
    await LoginApi.logout();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(
              color: Colors.blue,
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'ERP Portal',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.assignment),
            title: const Text('Tasks'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const WebViewScreen(
                    title: 'Tasks',
                    url: 'https://erp.homegeniegroup.in/TG',
                  ),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.dashboard),
            title: const Text('Dashboard'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const WebViewScreen(
                    title: 'Dashboard',
                    url: 'https://erp.homegeniegroup.in/salesperson',
                  ),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.language),
            title: const Text('ERP Portal'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const WebViewScreen(
                    title: 'ERP Portal',
                    url: 'https://erp.homegeniegroup.in',
                  ),
                ),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.home),
            title: const Text('Back to Home'),
            onTap: () {
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // Pick up any calls that arrived while we were backgrounded
      _drainBackgroundQueuedCalls();
      _syncIncomingDeviceCalls();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pauseTimer?.cancel();
    _tokenRefreshSub?.cancel();
    _notificationSub?.cancel();
    super.dispose();
  }

  static const List<String> _kpiCategories = [
    "Hot Leads",
    "Followup Leads",
    "Order Followups",
    "B2B Followups",
  ];

  int _categoryCount(String category) =>
      callQueue.getAll().where((c) => c.category == category).length;

  String _formatRupees(num v) {
    final s = v.round().toString();
    // Indian grouping: 12,34,567
    if (s.length <= 3) return "₹$s";
    final last3 = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    return "₹${parts.join(',')},$last3";
  }

  Widget _buildScorecard() {
    return FutureBuilder<SharedPreferences>(
      future: SharedPreferences.getInstance(),
      builder: (context, snapshot) {
        // Actual collections — stored locally until the collections API
        // is ready; backend sync can write 'actual_collections'
        final actual =
            snapshot.data?.getDouble('actual_collections') ?? 0.0;
        const target = AppConfig.dailyCollectionTarget;
        final progress =
            target == 0 ? 0.0 : (actual / target).clamp(0.0, 1.0);
        final met = actual >= target;

        return Card(
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Collections Scorecard",
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold)),
                    Text(
                      "${_formatRupees(actual)} / ${_formatRupees(target)}",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: met ? Colors.green : Colors.orange.shade800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: Colors.grey.shade200,
                    color: met ? Colors.green : Colors.orange,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  met
                      ? "Collection target achieved! 🎯"
                      : "${_formatRupees(target - actual)} more to reach target",
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildConversionCard() {
    return FutureBuilder<List<CallHistoryEntry>>(
      future: CallHistoryStorage.getAll(),
      builder: (context, snapshot) {
        final all = snapshot.data ?? [];
        final total = all.length;
        final connected = all
            .where((e) => e.status.toLowerCase() == 'connected')
            .length;
        final pct = total == 0 ? 0 : ((connected / total) * 100).round();
        return Card(
          elevation: 1,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.trending_up,
                    color: pct >= 50 ? Colors.green : Colors.orange,
                    size: 20),
                const SizedBox(width: 10),
                const Text("Conversion",
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.bold)),
                const Spacer(),
                Text(
                  "$pct%",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: pct >= 50 ? Colors.green : Colors.orange.shade800,
                  ),
                ),
                const SizedBox(width: 6),
                Text("($connected/$total connected)",
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey[600])),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildKpiGrid() {
    final colors = {
      "Hot Leads": Colors.red,
      "Followup Leads": Colors.orange,
      "Order Followups": Colors.blue,
      "B2B Followups": Colors.purple,
    };
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.2,
      children: _kpiCategories.map((cat) {
        final color = colors[cat] ?? Colors.teal;
        final count = _categoryCount(cat);
        return Card(
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("$count",
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: color)),
                      Text(cat,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey[700])),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  void _showMessageSheet(CallQueueItem call) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Message ${call.customerName}",
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(call.mobileNo,
                  style: TextStyle(fontSize: 13, color: Colors.grey[600])),
              const SizedBox(height: 12),
              ...MessageTemplates.templates.entries.map((t) {
                final filled =
                    MessageTemplates.fill(t.value, call.customerName);
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t.key,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13)),
                              const SizedBox(height: 2),
                              Text(filled,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[600])),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.sms, color: Colors.blue),
                          tooltip: "SMS",
                          onPressed: () {
                            Navigator.pop(ctx);
                            MessageService.sendSms(call.mobileNo, filled);
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.chat, color: Colors.green),
                          tooltip: "WhatsApp",
                          onPressed: () {
                            Navigator.pop(ctx);
                            MessageService.sendWhatsApp(call.mobileNo, filled);
                          },
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategorizedQueue() {
    final all = callQueue.getAll();
    if (all.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              children: [
                Icon(Icons.done_all, size: 48, color: Colors.green.shade300),
                const SizedBox(height: 8),
                Text("No calls in queue",
                    style: TextStyle(color: Colors.grey[600])),
              ],
            ),
          ),
        ),
      );
    }

    // Group by category, preserving overall queue order inside each group
    final grouped = <String, List<MapEntry<int, CallQueueItem>>>{};
    for (int i = 0; i < all.length; i++) {
      grouped.putIfAbsent(all[i].category, () => []).add(MapEntry(i, all[i]));
    }
    final orderedCats = [
      ..._kpiCategories.where(grouped.containsKey),
      ...grouped.keys.where((k) => !_kpiCategories.contains(k)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("Call Queue (${all.length})",
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold)),
            ElevatedButton.icon(
              onPressed: _processFirstQueuedCall,
              icon: const Icon(Icons.phone, size: 18),
              label: const Text("Process"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...orderedCats.map((cat) {
          final items = grouped[cat]!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Row(
                  children: [
                    Text(cat,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[800])),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text("${items.length}",
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange.shade800)),
                    ),
                  ],
                ),
              ),
              ...items.asMap().entries.map((entry) {
                final call = entry.value.value;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        child: Text("${entry.key + 1}.",
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange.shade800)),
                      ),
                      Expanded(
                        child: Text(call.customerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                      ),
                      Text(call.mobileNo,
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[700])),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.call,
                            size: 18, color: Colors.green),
                        tooltip: "Call now",
                        onPressed: () =>
                            _processQueuedCallAt(entry.value.key),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.message,
                            size: 18, color: Colors.teal),
                        tooltip: "Send SMS / WhatsApp",
                        onPressed: () => _showMessageSheet(call),
                      ),
                    ],
                  ),
                );
              }),
            ],
          );
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("One Stop Many Solutions"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: logout,
            tooltip: "Logout",
          ),
        ],
      ),
      drawer: _buildDrawer(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentTab,
        onTap: (i) => setState(() => _currentTab = i),
        selectedItemColor: Colors.green,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.phone_in_talk),
            label: "Call Queue",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: "History",
          ),
        ],
      ),
      body: _currentTab == 1
          ? const CallHistoryTab()
          : Column(
        children: [
          // Call Flow Status Bar
          Container(
            color: isCallFlowPaused ? Colors.red.shade100 : Colors.green.shade100,
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isCallFlowPaused
                      ? "📴 Call Flow Paused"
                      : "📱 Call Flow Active",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isCallFlowPaused ? Colors.red : Colors.green,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: toggleCallFlow,
                  icon: Icon(
                    isCallFlowPaused ? Icons.play_arrow : Icons.pause,
                  ),
                  label: Text(isCallFlowPaused ? "Resume" : "Pause"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isCallFlowPaused ? Colors.green : Colors.red,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          if (isCallFlowPaused && pausedUntil != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.red.shade50,
              child: Text(
                "${_pauseReason.isEmpty ? 'Paused' : _pauseReason} until: ${pausedUntil!.toLocal().toString().split('.')[0]}",
                style: TextStyle(
                  color: Colors.red.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildScorecard(),
                  const SizedBox(height: 12),
                  _buildKpiGrid(),
                  const SizedBox(height: 10),
                  _buildConversionCard(),
                  const SizedBox(height: 16),
                  _buildCategorizedQueue(),
                ],
              ),
            ),
          ),
        ],
      ),

    );
  }
}

class LeadCallScreen extends StatefulWidget {
  final Map<String, dynamic> data;

  const LeadCallScreen({
    super.key,
    required this.data,
  });

  @override
  State<LeadCallScreen> createState() => _LeadCallScreenState();
}

class _LeadCallScreenState extends State<LeadCallScreen> with WidgetsBindingObserver {
  int countdown = 5;
  Timer? timer;
  bool callTriggered = false;
  bool callStarted = false;
  bool _wasBackgroundedDuringCall = false;
  DateTime? _backgroundedAt;
  DateTime? callStartTime;
  DateTime? _initiatedAt;
  Timer? callDurationTimer;

  static const EventChannel _callStateChannel = EventChannel('lead_calling/call_state');
  StreamSubscription? _callStateSubscription;
  bool _hasListenerSetup = false;

  Future<Map<String, dynamic>> _fetchCallInfoWithRetry(String mobileNo) async {
    debugPrint('[CALLLOG] Starting call log fetch with retries for: $mobileNo');
    final permissionGranted = await AutoDialer.ensureCallLogPermission();
    final initiatedAt = _initiatedAt ?? DateTime.now();
    final maxAttempts = permissionGranted ? 4 : 2;

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final callInfo = await AutoDialer.getLastCallInfoForSession(
          mobileNo,
          initiatedAt: initiatedAt,
        );
        final found = callInfo['found'] == true;
        if (found) {
          callInfo['dataSource'] = 'device';
          callInfo['permissionGranted'] = permissionGranted;
          callInfo['retrievedAttempt'] = attempt;
          return callInfo;
        }
        if (attempt < maxAttempts) {
          await Future.delayed(Duration(milliseconds: 300 + (attempt * 100)));
        }
      } catch (e) {
        debugPrint('[CALLLOG] Error on attempt $attempt: $e');
        if (attempt < maxAttempts) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }
    }
    return {
      'found': false,
      'durationSeconds': 0,
      'callStatus': 'Unknown',
      'disconnectedStatus': 'unknown',
      'attended': false,
      'timestamp': 0,
      'dataSource': 'fallback',
      'permissionGranted': permissionGranted,
      'retrievedAttempt': -1,
    };
  }

  @override
  void initState() {
    super.initState();
    startCountdown();
    WidgetsBinding.instance.addObserver(this);
    _setupCallStateListener();
  }

  void _setupCallStateListener() {
    if (_hasListenerSetup) return;
    _hasListenerSetup = true;
    _callStateSubscription = _callStateChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is Map) {
          final state = event['state'];
          if (state == 'CALL_ENDED' && callStarted && !_wasBackgroundedDuringCall) {
            _handleDirectCallEnd();
          }
        }
      },
      onError: (error) {
        debugPrint('[CALL_STATE] Error: $error');
      },
    );
  }

  Future<void> _handleDirectCallEnd() async {
    if (!mounted) return;
    callDurationTimer?.cancel();
    final mobileNo = widget.data["mobile_no"]?.toString() ?? "";
    if (mobileNo.isNotEmpty) {
      // Give Android time to write the call log entry before reading it.
      // Reading too early misclassifies attended calls as not_connected.
      await Future.delayed(const Duration(milliseconds: 1500));
      if (!mounted) return;
      final callInfo = await _fetchCallInfoWithRetry(mobileNo);
      if (callInfo['found'] == true) {
        final attended = callInfo['attended'] == true;
        final dceDuration = callInfo['durationSeconds'] is int
            ? callInfo['durationSeconds'] as int
            : int.tryParse(callInfo['durationSeconds']?.toString() ?? '0') ?? 0;
        // Only auto-skip when truly unanswered: not attended AND zero duration.
        // Any call with talk time must go through the completion dialog.
        if (!attended && dceDuration == 0) {
          callStarted = false;
          unawaited(CallHistoryStorage.add(CallHistoryEntry(
            customerName: widget.data["customer_name"]?.toString() ?? '',
            mobileNo: mobileNo,
            doctype: widget.data["doctype"]?.toString() ?? '',
            docname: widget.data["docname"]?.toString() ?? '',
            status: 'Not Answered',
            durationSeconds: 0,
            calledAt: _initiatedAt ?? DateTime.now(),
          )));
          unawaited(CallLogApi.updateCallLog(
            doctype: widget.data["doctype"]?.toString() ?? '',
            docname: widget.data["docname"]?.toString() ?? '',
            customerName: widget.data["customer_name"]?.toString() ?? '',
            mobileNo: mobileNo,
            initiatedTime: _initiatedAt ?? DateTime.now(),
            callDuration: callInfo['durationSeconds'] is int
                ? callInfo['durationSeconds'] as int
                : int.tryParse(callInfo['durationSeconds']?.toString() ?? '0') ?? 0,
            callStatus: callInfo['callStatus']?.toString() ?? 'Not Connected',
            disconnectedStatus: callInfo['disconnectedStatus']?.toString() ?? 'not_connected',
            attended: false,
            notes: '',
            dataSource: callInfo['dataSource']?.toString() ?? 'device',
            permissionGranted: callInfo['permissionGranted'] == true,
            retrievedAttempt: callInfo['retrievedAttempt'] is int
                ? callInfo['retrievedAttempt'] as int
                : int.tryParse(callInfo['retrievedAttempt']?.toString() ?? '-1') ?? -1,
          ));
          if (mounted) Navigator.pop(context, {'status': 'not_connected'});
          return;
        }
        final durationSeconds = callInfo['durationSeconds'] is int
            ? callInfo['durationSeconds'] as int
            : int.tryParse(callInfo['durationSeconds']?.toString() ?? '0') ?? 0;
        if (mounted) {
          await _showCallCompletionDialog(
            callDuration: Duration(seconds: durationSeconds),
            callStatus: callInfo['callStatus']?.toString() ?? 'Unknown',
            disconnectedStatus: callInfo['disconnectedStatus']?.toString() ?? 'unknown',
            attended: attended,
            dataSource: callInfo['dataSource']?.toString() ?? 'unknown',
            permissionGranted: callInfo['permissionGranted'] == true,
            retrievedAttempt: callInfo['retrievedAttempt'] is int
                ? callInfo['retrievedAttempt'] as int
                : int.tryParse(callInfo['retrievedAttempt']?.toString() ?? '-1') ?? -1,
          );
        }
      } else {
        if (mounted) {
          await _showCallCompletionDialog(
            dataSource: callInfo['dataSource']?.toString() ?? 'fallback',
            permissionGranted: callInfo['permissionGranted'] == true,
            retrievedAttempt: -1,
          );
        }
      }
    } else {
      if (mounted) await _showCallCompletionDialog();
    }
    callStarted = false;
  }

  void startCountdown() {
    timer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      if (countdown <= 1) {
        t.cancel();
        try {
          makeCall();
        } catch (e) {
          debugPrint("[TIMER] Error in makeCall: $e");
          t.cancel();
        }
      } else {
        if (!mounted) return;
        setState(() { countdown--; });
      }
    });
  }

  void _startCallDurationTracking() {
    callStartTime = DateTime.now();
    callDurationTimer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      if (mounted) setState(() {});
    });
  }

  Duration _getCallDuration() {
    if (callStartTime == null) return Duration.zero;
    return DateTime.now().difference(callStartTime!);
  }

  Future<void> _showCallCompletionDialog({
    Duration? callDuration,
    String? callStatus,
    String? disconnectedStatus,
    bool? attended,
    String dataSource = 'unknown',
    bool permissionGranted = false,
    int retrievedAttempt = -1,
  }) async {
    if (!mounted) return;
    final customerName = widget.data["customer_name"]?.toString() ?? "Unknown";
    final doctype = widget.data["doctype"]?.toString() ?? "Lead";
    final docname = widget.data["docname"]?.toString() ?? "";
    final mobileNo = widget.data["mobile_no"]?.toString() ?? "";
    callDurationTimer?.cancel();
    final duration = callDuration ?? _getCallDuration();

    // Record in local call history (status from device log, e.g. Connected/Missed)
    unawaited(CallHistoryStorage.add(CallHistoryEntry(
      customerName: customerName,
      mobileNo: mobileNo,
      doctype: doctype,
      docname: docname,
      status: (callStatus == null || callStatus.isEmpty || callStatus == 'Unknown')
          ? 'Connected'
          : callStatus,
      durationSeconds: duration.inSeconds,
      calledAt: _initiatedAt ?? DateTime.now(),
    )));

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => CallCompletionDialog(
        doctype: doctype,
        docname: docname,
        customerName: customerName,
        mobileNo: mobileNo,
        callDuration: duration,
        initiatedTime: _initiatedAt ?? DateTime.now(),
        initialCallStatus: callStatus,
        initialDisconnectedStatus: disconnectedStatus,
        initialAttended: attended,
        dataSource: dataSource,
        permissionGranted: permissionGranted,
        retrievedAttempt: retrievedAttempt,
      ),
    ).then((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> makeCall() async {
    if (callTriggered) return;
    callTriggered = true;
    timer?.cancel();

    final mobileNo = widget.data["mobile_no"]?.toString() ?? "";
    final customerName = widget.data["customer_name"]?.toString() ?? "Unknown";
    final doctype = widget.data["doctype"]?.toString() ?? "Lead";
    final docname = widget.data["docname"]?.toString() ?? "";

    if (mobileNo.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Phone number not available")),
      );
      return;
    }

    final phonePermission = await Permission.phone.request();
    if (!phonePermission.isGranted) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Phone permission required")),
      );
      return;
    }

    await AutoDialer.ensureCallLogPermission();

    final initiatedAt = DateTime.now();
    _initiatedAt = initiatedAt;

    try {
      await CallLogApi.logCallInitiation(
        doctype: doctype,
        docname: docname,
        customerName: customerName,
        mobileNo: mobileNo,
        initiatedAt: initiatedAt,
      );
    } catch (e) {
      debugPrint("[CALL] Failed to log initiation: $e");
    }

    final success = await AutoDialer.autoCall(mobileNo);
    callStarted = success;

    if (!success) {
      final fallbackSuccess = await AutoDialer.openDialer(mobileNo);
      callStarted = fallbackSuccess;
      if (!fallbackSuccess && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Unable to initiate call")),
        );
        await CallLogApi.logCallError(
          doctype: doctype,
          docname: docname,
          customerName: customerName,
          mobileNo: mobileNo,
          errorMessage: "Failed to initiate auto call",
        );
      }
    } else {
      callStarted = true;
    }

    if (callStarted) _startCallDurationTracking();
  }

  @override
  void dispose() {
    _callStateSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    callDurationTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.paused && callStarted) {
      _wasBackgroundedDuringCall = true;
      _backgroundedAt = DateTime.now();
      debugPrint('[CALL] App backgrounded during call');
    }

    if (state == AppLifecycleState.resumed && _wasBackgroundedDuringCall) {
      final pausedDuration = _backgroundedAt == null
          ? Duration.zero
          : DateTime.now().difference(_backgroundedAt!);

      debugPrint('[CALL] App resumed; pausedDuration=$pausedDuration');

      _wasBackgroundedDuringCall = false;
      _backgroundedAt = null;

      if (!callStarted) return;

      if (pausedDuration < const Duration(seconds: 2)) {
        // User cancelled quickly on dialpad — treat as skip, go back to queue
        debugPrint('[CALL] Quick resume — dialpad cancel detected, returning to queue');
        timer?.cancel();
        callDurationTimer?.cancel();
        callStarted = false;
        callTriggered = false;
        if (mounted) Navigator.pop(context, {'status': 'cancelled'});
      } else {
        // User was on the call — check call log to determine outcome
        debugPrint('[CALL] Resume after call — checking outcome');
        callDurationTimer?.cancel();
        callStarted = false;
        callStartTime = null;
        if (mounted) _handleResumeAfterCall();
      }
    }
  }

  Future<void> _handleResumeAfterCall() async {
    final mobileNo = widget.data["mobile_no"]?.toString() ?? "";
    if (mobileNo.isEmpty) {
      _showCallCompletionDialog();
      return;
    }

    // Give Android time to write the call log entry before reading it.
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;

    final callInfo = await _fetchCallInfoWithRetry(mobileNo);
    if (callInfo['found'] == true) {
      final attended = callInfo['attended'] == true;
      final durationSeconds = callInfo['durationSeconds'] is int
          ? callInfo['durationSeconds'] as int
          : int.tryParse(callInfo['durationSeconds']?.toString() ?? '0') ?? 0;

      // Only auto-skip when truly unanswered: not attended AND zero duration.
      // Any call with talk time must go through the completion dialog.
      if (!attended && durationSeconds == 0) {
        // Full ring, no answer — log and return to queue
        unawaited(CallHistoryStorage.add(CallHistoryEntry(
          customerName: widget.data["customer_name"]?.toString() ?? '',
          mobileNo: mobileNo,
          doctype: widget.data["doctype"]?.toString() ?? '',
          docname: widget.data["docname"]?.toString() ?? '',
          status: 'Not Answered',
          durationSeconds: 0,
          calledAt: _initiatedAt ?? DateTime.now(),
        )));
        unawaited(CallLogApi.updateCallLog(
          doctype: widget.data["doctype"]?.toString() ?? '',
          docname: widget.data["docname"]?.toString() ?? '',
          customerName: widget.data["customer_name"]?.toString() ?? '',
          mobileNo: mobileNo,
          initiatedTime: _initiatedAt ?? DateTime.now(),
          callDuration: durationSeconds,
          callStatus: callInfo['callStatus']?.toString() ?? 'Not Connected',
          disconnectedStatus: callInfo['disconnectedStatus']?.toString() ?? 'not_connected',
          attended: false,
          notes: '',
          dataSource: callInfo['dataSource']?.toString() ?? 'device',
          permissionGranted: callInfo['permissionGranted'] == true,
          retrievedAttempt: callInfo['retrievedAttempt'] is int
              ? callInfo['retrievedAttempt'] as int
              : int.tryParse(callInfo['retrievedAttempt']?.toString() ?? '-1') ?? -1,
        ));
        if (mounted) Navigator.pop(context, {'status': 'not_connected'});
        return;
      }

      // Call was answered — show completion dialog
      _showCallCompletionDialog(
        callDuration: Duration(seconds: durationSeconds),
        callStatus: callInfo['callStatus']?.toString() ?? 'Unknown',
        disconnectedStatus: callInfo['disconnectedStatus']?.toString() ?? 'unknown',
        attended: true,
        dataSource: callInfo['dataSource']?.toString() ?? 'unknown',
        permissionGranted: callInfo['permissionGranted'] == true,
        retrievedAttempt: callInfo['retrievedAttempt'] is int
            ? callInfo['retrievedAttempt'] as int
            : int.tryParse(callInfo['retrievedAttempt']?.toString() ?? '-1') ?? -1,
      );
    } else {
      // Could not determine outcome — show manual completion dialog
      _showCallCompletionDialog(
        dataSource: callInfo['dataSource']?.toString() ?? 'fallback',
        permissionGranted: callInfo['permissionGranted'] == true,
        retrievedAttempt: -1,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        timer?.cancel();
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Incoming Call"),
          automaticallyImplyLeading: false,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.call, size: 80, color: Colors.green),
              const SizedBox(height: 20),
              Text(
                widget.data["customer_name"] ?? "Incoming Call",
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text(
                widget.data["mobile_no"] ?? "Unknown",
                style: const TextStyle(fontSize: 18, color: Colors.grey),
              ),
              const SizedBox(height: 40),
              if (!callTriggered)
                Text(
                  "Calling in $countdown...",
                  style: const TextStyle(
                    fontSize: 18,
                    color: Colors.blue,
                    fontWeight: FontWeight.w600,
                  ),
                )
              else
                const Text(
                  "Launching call...",
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.blue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: () {
                  // Cancel button — always go back to queue as pending
                  timer?.cancel();
                  callDurationTimer?.cancel();
                  _callStateSubscription?.cancel();
                  callStarted = false;
                  Navigator.pop(context, {'status': 'cancelled'});
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                ),
                child: const Text("Cancel"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
