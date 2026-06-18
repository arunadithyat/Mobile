
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:lead_calling/services/auto_dialer.dart';
import 'package:lead_calling/api/call_log_api.dart';
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
import 'screens/chatbot_screen.dart';
import 'screens/answered_call_dialog.dart';
import 'screens/unanswered_call_dialog.dart';
import 'package:lead_calling/screens/webview_screen.dart';
import 'services/message_service.dart';

/// Launches the phone dialer to call the given phone number
Future<bool> launchPhoneCall(String phoneNumber) async {
  return await AutoDialer.openDialer(phoneNumber);
}

Future<void> savePendingDialog(Map<String, dynamic> data) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('pending_dialog', jsonEncode(data));
  debugPrint("[DIALOG] Saved pending dialog state");
}

Future<void> clearPendingDialog() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('pending_dialog');
  debugPrint("[DIALOG] Cleared pending dialog state");
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
  bool _obscurePassword = true;

  Future<void> login() async {
    if (userController.text.trim().isEmpty || passController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter username and password")),
      );
      return;
    }

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
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const SizedBox(height: 60),

              // Logo
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.asset(
                  'assets/images/salesgenie_logo.png',
                  height: 180,
                  width: 180,
                  fit: BoxFit.cover,
                ),
              ),

              const SizedBox(height: 20),

              // App name
              const Text(
                "SalesGenie",
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A73E8),
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "Collaborate. Sell More.",
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[500],
                  letterSpacing: 0.5,
                ),
              ),

              const SizedBox(height: 50),

              // Username field
              TextField(
                controller: userController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: "Username",
                  hintText: "Enter your email or username",
                  prefixIcon: const Icon(Icons.person_outline, color: Color(0xFF1A73E8)),
                  filled: true,
                  fillColor: Colors.grey[50],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF1A73E8), width: 2),
                  ),
                ),
              ),

              const SizedBox(height: 18),

              // Password field with eye icon
              TextField(
                controller: passController,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => login(),
                decoration: InputDecoration(
                  labelText: "Password",
                  hintText: "Enter your password",
                  prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFF1A73E8)),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_off : Icons.visibility,
                      color: Colors.grey[600],
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF1A73E8), width: 2),
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Login button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: loading ? null : login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A73E8),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFF1A73E8).withValues(alpha: 0.6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  child: loading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          "LOGIN",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.5,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 40),

              // Footer
              Text(
                "One Stop Many Solutions",
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[400],
                ),
              ),
            ],
          ),
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
  bool _isPaused = false;
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
  Map<String, int> _kpiCounts = {};
  String _pauseReason = "";

  bool get isCallFlowPaused => _isPaused;

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
    // Restore pause state from SharedPreferences
    await _restorePauseState();

    // Load queue FIRST so user sees data immediately
    _refreshQueueDisplay();

    // Restore pending dialog if app was killed during post-call update
    await _restorePendingDialog();

    // Then permissions + FCM (these can take time with dialogs)
    await _requestCallTelemetryPermissions();
    final notifStatus = await Permission.notification.request();
    debugPrint("[BOOT] Notification permission: $notifStatus");
    await getFcmToken();
    await _initializeNotifications();
    _listenForTokenRefresh();
    await _syncIncomingDeviceCalls();

    // Always check for app update on every open
    await _checkAppUpdate();
  }

  /// Scans device incoming calls, matches against call queue, and
  /// logs matched calls in call history.
  Future<void> _syncIncomingDeviceCalls() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastSyncMs = prefs.getInt('last_incoming_sync') ?? 0;
      final since = lastSyncMs > 0
          ? DateTime.fromMillisecondsSinceEpoch(lastSyncMs)
          : DateTime.now().subtract(const Duration(hours: 24));

      final calls = await AutoDialer.getIncomingCallsSince(since);
      debugPrint("[INCOMING_SYNC] Found ${calls.length} incoming call(s) since $since");
      if (calls.isEmpty) {
        await prefs.setInt('last_incoming_sync', DateTime.now().millisecondsSinceEpoch);
        return;
      }

      // Match incoming calls against call queue entries
      final queueItems = callQueue.getAll();
      int matched = 0;

      for (final call in calls) {
        final incomingNumber = _last10(call['number']?.toString() ?? '');
        if (incomingNumber.isEmpty) continue;

        // Find matching queue entry by last 10 digits
        for (final item in queueItems) {
          final queueNumber = _last10(item.mobileNo);
          if (queueNumber == incomingNumber) {
            matched++;
            final callType = call['type']?.toString() ?? 'unknown';
            final attended = call['attended'] == true;
            final durationSeconds = call['durationSeconds'] is int
                ? call['durationSeconds'] as int
                : int.tryParse(call['durationSeconds']?.toString() ?? '0') ?? 0;
            final timestamp = call['timestamp'] is int
                ? DateTime.fromMillisecondsSinceEpoch(call['timestamp'] as int)
                : DateTime.now();

            // Determine status
            String status;
            if (callType == 'missed') {
              status = 'Missed Call';
            } else if (callType == 'rejected') {
              status = 'Rejected';
            } else if (attended && durationSeconds > 0) {
              status = 'Customer Called Back';
            } else {
              status = 'Missed Call';
            }

            // Add to local call history
            await CallHistoryStorage.add(CallHistoryEntry(
              customerName: item.customerName,
              mobileNo: item.mobileNo,
              doctype: item.doctype,
              docname: item.docname,
              status: status,
              durationSeconds: durationSeconds,
              calledAt: timestamp,
            ));

            // Create Call Log in ERPNext — dedup by number+timestamp
            final syncKey = '${item.mobileNo}_${timestamp.millisecondsSinceEpoch}';
            final syncedCalls = prefs.getStringList('synced_incoming_calls') ?? [];
            if (!syncedCalls.contains(syncKey)) {
              final ownNumber = await AutoDialer.getOwnNumber();
              await CallLogDoctypeApi.createIncomingCallLog(
                fromNumber: item.mobileNo,
                toNumber: ownNumber,
                startTime: timestamp,
                durationSeconds: durationSeconds,
                attended: attended,
              );
              syncedCalls.add(syncKey);
              // Keep only last 200 entries to avoid unbounded growth
              if (syncedCalls.length > 200) {
                syncedCalls.removeRange(0, syncedCalls.length - 200);
              }
              await prefs.setStringList('synced_incoming_calls', syncedCalls);
            } else {
              debugPrint("[INCOMING_SYNC] Skipped duplicate Call Log: $syncKey");
            }

            debugPrint(
                "[INCOMING_SYNC] 📞 Matched: ${item.customerName} ($incomingNumber) — $status ${durationSeconds}s");
            break; // one match per incoming call
          }
        }
      }

      debugPrint("[INCOMING_SYNC] ✅ $matched matched out of ${calls.length} incoming calls");

      // Also sync to backend
      final ok = await IncomingCallSyncApi.syncIncomingCalls(calls);
      if (ok) {
        await prefs.setInt('last_incoming_sync', DateTime.now().millisecondsSinceEpoch);
        debugPrint("[INCOMING_SYNC] ✅ Synced and watermark updated");
      } else {
        debugPrint("[INCOMING_SYNC] ⚠️ Backend sync failed — will retry next launch/resume");
      }

      if (matched > 0 && mounted) setState(() {});
    } catch (e) {
      debugPrint("[INCOMING_SYNC] Error: $e");
    }
  }

  /// Returns last 10 digits of a phone number for matching.
  String _last10(String number) {
    final digits = number.replaceAll(RegExp(r'[^\d]'), '');
    return digits.length >= 10 ? digits.substring(digits.length - 10) : digits;
  }

  Future<void> _restorePendingDialog() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('pending_dialog');
    if (raw == null || raw.isEmpty) return;

    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final dialogType = data['dialog_type']?.toString() ?? '';
      debugPrint("[DIALOG] Restoring pending dialog: $dialogType");

      if (!mounted) return;

      if (dialogType == 'answered') {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AnsweredCallDialog(
            leadName: data['lead'] ?? '',
            opportunityName: data['opportunity'] ?? '',
            callLogName: data['call_log_name'] ?? '',
            customerName: data['customer_name'] ?? 'Unknown',
            mobileNo: data['mobile_no'] ?? '',
            doctype: data['doctype'] ?? '',
            docname: data['docname'] ?? '',
            callDuration: Duration(seconds: data['duration_seconds'] ?? 0),
            initiatedTime: DateTime.tryParse(data['initiated_time'] ?? '') ?? DateTime.now(),
            callStatus: data['call_status'] ?? 'Connected',
            attended: true,
          ),
        ).then((_) => clearPendingDialog());
      } else if (dialogType == 'unanswered') {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => UnansweredCallDialog(
            leadName: data['lead'] ?? '',
            opportunityName: data['opportunity'] ?? '',
            customerName: data['customer_name'] ?? 'Unknown',
            mobileNo: data['mobile_no'] ?? '',
          ),
        ).then((_) => clearPendingDialog());
      }
    } catch (e) {
      debugPrint("[DIALOG] Error restoring: $e");
      final prefs2 = await SharedPreferences.getInstance();
      await prefs2.remove('pending_dialog');
    }
  }

  Future<void> _restorePauseState() async {
    final prefs = await SharedPreferences.getInstance();
    final paused = prefs.getBool('is_paused') ?? false;
    final reason = prefs.getString('pause_reason') ?? '';
    if (paused && reason.isNotEmpty) {
      setState(() {
        _isPaused = true;
        _pauseReason = reason;
      });
      debugPrint("[PAUSE] ✅ Restored: On $reason");
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

  /// Fetches call queue from API and updates the display. NO auto-call.
  /// Used by: swipe-down refresh, cancel recovery, busy-path refresh.
  Future<void> _refreshQueueDisplay() async {
    try {
      debugPrint("[QUEUE] Refreshing display from API...");
      _fetchKpiData(); // refresh KPI counts in parallel
      final items = await CallQueueApi.fetchCallQueue();
      if (!mounted) return;
      setState(() {
        callQueue.clearAll();
        for (final item in items) {
          callQueue.addItem(item);
        }
      });
      debugPrint("[QUEUE] ✅ ${items.length} item(s) loaded");
    } catch (e) {
      debugPrint("[QUEUE] ❌ Refresh failed: $e");
    }
  }

  /// Fetches KPI counts from the backend API.
  Future<void> _fetchKpiData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cookie = prefs.getString('cookie') ?? '';
      if (cookie.isEmpty) return;

      final response = await http.get(
        Uri.parse(AppConfig.kpiApi),
        headers: {'Cookie': cookie},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final message = data['message'];
        if (message is Map<String, dynamic>) {
          if (!mounted) return;
          setState(() {
            _kpiCounts = {
              'pending_count': _toInt(message['pending_count']),
              'lead_followup_count': _toInt(message['lead_followup_count']),
              'opportunity_followup_count': _toInt(message['opportunity_followup_count']),
              'b2b_count': _toInt(message['b2b_count']),
            };
          });
          debugPrint("[KPI] ✅ Counts: $_kpiCounts");
        }
      }
    } catch (e) {
      debugPrint("[KPI] ❌ Error: $e");
    }
  }

  int _toInt(dynamic v) => v is int ? v : int.tryParse(v?.toString() ?? '0') ?? 0;

  /// Called ONLY on FCM foreground trigger — refreshes queue then
  /// auto-calls the first pending call exactly once. No loop.
  Future<void> _refreshAndAutoCallOnce() async {
    await _refreshQueueDisplay();
    if (!mounted) return;
    if (callQueue.pendingCount > 0 && !_isLeadCallInProgress && !_processingLock) {
      debugPrint("[QUEUE] FCM trigger — auto-calling first pending call");
      _processFirstQueuedCall();
    }
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
        // Check if app update is required
        final updateResult = await DeviceApi.checkForUpdate();
        debugPrint("🔍 UPDATE CHECK => $updateResult");
        if (updateResult['update_required'] == true) {
          final latestVersion = updateResult['latest_version'] ?? '';
          debugPrint("⚠️ App update required! Latest: $latestVersion");
          if (mounted) _showUpdateRequiredDialog(latestVersion);
        } else {
          debugPrint("✅ App is up to date");
        }
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

    // Refresh queue from API — backend already created Call Logs for all leads
    await _refreshQueueDisplay();
    if (!mounted) return;

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
        debugPrint("[BATCH] ℹ️ First lead cancelled — refreshing queue");
        await _refreshQueueDisplay();
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

    // If already processing a call OR lock is held, refresh queue from API
    // (Call Log already exists in backend since it's created before FCM)
    if (isCallFlowPaused || _isLeadCallInProgress || _processingLock) {
      debugPrint("⏸️ Call flow busy — refreshing queue from API");
      await _refreshQueueDisplay();
      if (!mounted) return;
      setState(() {
        _lastPushAction = "queued_busy";
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

    debugPrint("✅ FCM trigger — checking if user is already on a call...");

    // Check if user is already on a phone call — don't interrupt!
    final alreadyOnCall = await AutoDialer.isOnCall();
    if (alreadyOnCall) {
      debugPrint("📞 User is on another call — queuing silently, no auto-dial");
      await _refreshQueueDisplay();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'New call from ${normalized["customer_name"] ?? "Unknown"} added to queue',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      setState(() { _lastPushAction = "queued_on_call"; });
      debugPrint("========== END INCOMING LEAD CALL ==========");
      return;
    }

    debugPrint("✅ User is free — showing Incoming Lead and auto-calling");
    // Show Incoming Lead screen directly with FCM payload data
    _processingLock = true;
    setState(() { _isLeadCallInProgress = true; });

    final routeResult = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LeadCallScreen(data: normalized),
      ),
    );

    if (!mounted) return;
    setState(() { _isLeadCallInProgress = false; });
    _processingLock = false;

    // Refresh queue from API after call ends — shows remaining pending calls
    await _refreshQueueDisplay();

    setState(() {
      _lastPushAction = "fcm_auto_call";
    });
    debugPrint("========== END INCOMING LEAD CALL ==========");
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
    final prefs = await SharedPreferences.getInstance();

    if (isCallFlowPaused) {
      final prevReason = _pauseReason;
      setState(() {
        _isPaused = false;
        _pauseReason = "";
      });
      await prefs.setBool('is_paused', false);
      await prefs.setString('pause_reason', '');
      _postPauseLog("RESUMED", prevReason);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Call flow resumed")),
      );
    } else {
      final reason = await _selectPauseReason();
      if (reason == null || !mounted) return;

      setState(() {
        _isPaused = true;
        _pauseReason = reason;
      });
      await prefs.setBool('is_paused', true);
      await prefs.setString('pause_reason', reason);
      _postPauseLog("PAUSED", reason);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Call flow paused — $reason")),
      );
    }
  }

  Future<void> _postPauseLog(String action, String reason) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cookie = prefs.getString('cookie') ?? '';
      final username = prefs.getString('username') ?? '';
      if (cookie.isEmpty) return;

      await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/resource/Error%20Log'),
        headers: {
          'Content-Type': 'application/json',
          'Cookie': cookie,
        },
        body: jsonEncode({
          'title': 'Call Flow $action — $reason',
          'error': jsonEncode({
            'type': 'CALL_FLOW_$action',
            'reason': reason,
            'user': username,
            'timestamp': DateTime.now().toIso8601String(),
          }),
        }),
      ).timeout(const Duration(seconds: 5));
      debugPrint('[PAUSE_LOG] ✅ $action — $reason logged');
    } catch (e) {
      debugPrint('[PAUSE_LOG] ❌ $e');
    }
  }

  static const List<String> _pauseReasons = ["Break", "Lunch", "Meeting"];

  Future<String?> _selectPauseReason() async {
    String selected = "Break";
    return showDialog<String>(
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
                items: _pauseReasons
                    .map((r) => DropdownMenuItem(value: r, child: Text(r)))
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
              onPressed: () => Navigator.pop(context, selected),
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

    // User cancelled — move to end of queue, STOP processing.
    // Agent picks the next call manually when ready.
    if (result is Map<String, dynamic> && result['status'] == 'cancelled') {
      debugPrint("[QUEUE] Cancelled — moved to end of queue, stopped");
      setState(() {
        callQueue.moveToEnd(targetIndex);
      });
      return;
    }

    // Not answered — same: move to end, stop.
    if (result is Map<String, dynamic> && result['status'] == 'not_connected') {
      debugPrint("[QUEUE] Not connected — moved to end of queue, stopped");
      setState(() {
        callQueue.moveToEnd(targetIndex);
      });
      return;
    }

    // Call completed — NOW remove it from the queue
    setState(() {
      callQueue.remove(targetIndex);
    });
    debugPrint("[QUEUE] Call completed — removed from queue");

    // Call completed — agent processes next call manually
  }

  Future<void> logout() async {
    // Clear app state so next user starts fresh
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('is_paused');
    await prefs.remove('pause_reason');
    await prefs.remove('synced_incoming_calls');
    await prefs.remove('last_incoming_sync');
    await prefs.remove('call_history');
    await prefs.remove('pending_dialog');

    await LoginApi.logout();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }

  Future<void> _checkAppUpdate() async {
    try {
      debugPrint('[UPDATE] Checking for app update...');
      final result = await DeviceApi.checkForUpdate();
      debugPrint('[UPDATE] Result: $result');
      if (result['update_required'] == true) {
        final latestVersion = result['latest_version'] ?? '';
        debugPrint('[UPDATE] ⚠️ Update required! Latest: $latestVersion');
        if (mounted) _showUpdateRequiredDialog(latestVersion);
      } else {
        debugPrint('[UPDATE] ✅ App is up to date');
      }
    } catch (e) {
      debugPrint('[UPDATE] ❌ Error: $e');
    }
  }

  void _showUpdateRequiredDialog(String latestVersion) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.system_update, color: Colors.blue, size: 28),
              SizedBox(width: 10),
              Text("Update Available"),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("A new version ($latestVersion) is available.",
                  style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 8),
              const Text("Please update SalesGenie to continue using the app.",
                  style: TextStyle(fontSize: 14, color: Colors.grey)),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                // Close app — user updates manually via APK
                SystemNavigator.pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A73E8),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text("OK, Close App"),
            ),
          ],
        ),
      ),
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
                  builder: (_) => WebViewScreen(
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
                  builder: (_) => WebViewScreen(
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
                  builder: (_) => WebViewScreen(
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
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Logout', style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(context); // close drawer
              logout();
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
      _syncIncomingDeviceCalls();
      // No queue refresh or auto-call on resume
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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

  int _categoryCount(String category) {
    // Count from local queue (already categorized from API)
    final queueCount = callQueue.getAll().where((c) => c.category == category).length;
    if (queueCount > 0) return queueCount;

    // Fallback to KPI API counts
    switch (category) {
      case 'Hot Leads':
        return _kpiCounts['pending_count'] ?? 0;
      case 'Followup Leads':
        return _kpiCounts['lead_followup_count'] ?? 0;
      case 'Order Followups':
        return _kpiCounts['opportunity_followup_count'] ?? 0;
      case 'B2B Followups':
        return _kpiCounts['b2b_count'] ?? 0;
      default:
        return 0;
    }
  }

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
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: color)),
                      Text(cat,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 15, color: Colors.grey[700])),
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
                    fontSize: 19, fontWeight: FontWeight.bold)),
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
                            fontSize: 17,
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
                              fontSize: 13,
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
                        width: 28,
                        child: Text("${entry.key + 1}.",
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange.shade800)),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(call.customerName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600)),
                            if (call.productEnquired.isNotEmpty)
                              Text(call.productEnquired,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.blue.shade700,
                                      fontWeight: FontWeight.w500)),
                            if (call.isOpportunity && call.opportunityAmount.isNotEmpty && call.opportunityAmount != '0' && call.opportunityAmount != '0.0')
                              Text("₹ ${call.opportunityAmount}",
                                  style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.green.shade700,
                                      fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      Text(call.mobileNo,
                          style: TextStyle(
                              fontSize: 15, color: Colors.grey[700])),
                      if (!_isPaused)
                        IconButton(
                          icon: const Icon(Icons.call,
                              size: 26, color: Colors.green),
                          tooltip: "Call now",
                          onPressed: () =>
                              _processQueuedCallAt(entry.value.key),
                        ),
                      IconButton(
                        icon: const Icon(Icons.message,
                            size: 26, color: Colors.teal),
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

  void _openChatbot() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatbotScreen(
          onNavigate: (route) {
            Navigator.pop(context); // close chatbot
            if (route == 'history') {
              setState(() => _currentTab = 1);
            } else if (route == 'queue') {
              setState(() => _currentTab = 0);
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("One Stop Many Solutions"),
      ),
      drawer: _buildDrawer(),
      floatingActionButton: FloatingActionButton(
        onPressed: _openChatbot,
        backgroundColor: const Color(0xFF1A73E8),
        child: const Icon(Icons.chat, color: Colors.white),
      ),
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
          if (isCallFlowPaused && _pauseReason.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.red.shade50,
              child: Text(
                "On $_pauseReason",
                style: TextStyle(
                  color: Colors.red.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshQueueDisplay,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildKpiGrid(),
                  const SizedBox(height: 16),
                  _buildCategorizedQueue(),
                ],
              ),
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
  Timer? _pollTimer;

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
          if (state == 'CALL_ENDED' && callStarted) {
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
    if (!mounted || !callStarted) return; // guard against double-trigger with poll
    callStarted = false;
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
          if (mounted) _showUnansweredDialog();
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
    final callLogName = widget.data["call_log_name"]?.toString() ?? "";
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

    final leadName = widget.data['lead']?.toString() ?? '';
    final opportunityName = widget.data['opportunity']?.toString() ?? '';

    // Persist dialog state so it survives app kills
    savePendingDialog({
      'dialog_type': 'answered',
      'lead': leadName,
      'opportunity': opportunityName,
      'call_log_name': callLogName,
      'customer_name': customerName,
      'mobile_no': mobileNo,
      'doctype': doctype,
      'docname': docname,
      'duration_seconds': duration.inSeconds,
      'initiated_time': (_initiatedAt ?? DateTime.now()).toIso8601String(),
      'call_status': callStatus ?? 'Connected',
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AnsweredCallDialog(
        leadName: leadName,
        opportunityName: opportunityName,
        callLogName: callLogName,
        customerName: customerName,
        mobileNo: mobileNo,
        doctype: doctype,
        docname: docname,
        callDuration: duration,
        initiatedTime: _initiatedAt ?? DateTime.now(),
        callStatus: callStatus ?? 'Connected',
        attended: attended ?? true,
        dataSource: dataSource,
        permissionGranted: permissionGranted,
        retrievedAttempt: retrievedAttempt,
      ),
    ).then((_) {
      clearPendingDialog();
      if (mounted) Navigator.pop(context);
    });
  }

  /// Shows the unanswered call dialog for RNR/Busy/etc. status update.
  /// The lead field from the queue data tells us which Lead to update.
  Future<void> _showUnansweredDialog() async {
    final leadName = widget.data['lead']?.toString() ?? '';
    final opportunityName = widget.data['opportunity']?.toString() ?? '';
    final customerName = widget.data['customer_name']?.toString() ?? 'Unknown';
    final mobileNo = widget.data['mobile_no']?.toString() ?? '';

    if (leadName.isEmpty && opportunityName.isEmpty) {
      debugPrint('[RNR] No lead/opportunity reference — skipping dialog');
      if (mounted) Navigator.pop(context, {'status': 'not_connected'});
      return;
    }

    // Persist dialog state so it survives app kills
    savePendingDialog({
      'dialog_type': 'unanswered',
      'lead': leadName,
      'opportunity': opportunityName,
      'customer_name': customerName,
      'mobile_no': mobileNo,
    });

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => UnansweredCallDialog(
        leadName: leadName,
        opportunityName: opportunityName,
        customerName: customerName,
        mobileNo: mobileNo,
      ),
    );

    await clearPendingDialog();

    if (mounted) {
      Navigator.pop(context, {'status': 'not_connected', ...?result});
    }
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
    _pollTimer?.cancel();
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
        // User came back to app — call might still be active.
        // Wait a moment then check device call log to detect if call ended.
        // This handles both: user still on call (no dialog) and
        // call ended while backgrounded (CALL_ENDED event missed).
        debugPrint('[CALL] Resume — checking if call is still active...');
        _wasBackgroundedDuringCall = false;
        _pollForCallEnd();
      }
    }
  }

  /// Polls to detect when the call actually ends.
  /// First checks if phone is still on a call — only reads call log
  /// when the phone is idle (prevents reading old entries).
  void _pollForCallEnd() {
    int attempts = 0;
    const maxAttempts = 20; // 60 seconds max

    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      attempts++;
      if (!mounted || !callStarted) {
        timer.cancel();
        return;
      }

      // CHECK 1: Is the phone still on a call?
      final stillOnCall = await AutoDialer.isOnCall();
      if (stillOnCall) {
        debugPrint('[CALL] Poll #$attempts — phone still on call, waiting...');
        return; // keep polling, don't check call log yet
      }

      // Phone is idle — call has ended. Now check call log for outcome.
      debugPrint('[CALL] Poll #$attempts — phone idle, checking call log...');
      timer.cancel();

      // Wait 1.5s for Android to write the call log entry
      await Future.delayed(const Duration(milliseconds: 1500));
      if (!mounted || !callStarted) return;

      final mobileNo = widget.data["mobile_no"]?.toString() ?? "";
      if (mobileNo.isEmpty) {
        callStarted = false;
        if (mounted) _showCallCompletionDialog();
        return;
      }

      final callInfo = await _fetchCallInfoWithRetry(mobileNo);
      callDurationTimer?.cancel();
      callStarted = false;
      callStartTime = null;

      if (callInfo['found'] == true) {
        final attended = callInfo['attended'] == true;
        final durationSeconds = callInfo['durationSeconds'] is int
            ? callInfo['durationSeconds'] as int
            : int.tryParse(callInfo['durationSeconds']?.toString() ?? '0') ?? 0;

        if (!attended && durationSeconds == 0) {
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
            callDuration: 0,
            callStatus: callInfo['callStatus']?.toString() ?? 'Not Connected',
            disconnectedStatus: callInfo['disconnectedStatus']?.toString() ?? 'not_connected',
            attended: false,
            notes: '',
            dataSource: callInfo['dataSource']?.toString() ?? 'device',
            permissionGranted: callInfo['permissionGranted'] == true,
            retrievedAttempt: callInfo['retrievedAttempt'] is int
                ? callInfo['retrievedAttempt'] as int
                : -1,
          ));
          if (mounted) _showUnansweredDialog();
        } else {
          if (mounted) {
            _showCallCompletionDialog(
              callDuration: Duration(seconds: durationSeconds),
              callStatus: callInfo['callStatus']?.toString(),
              disconnectedStatus: callInfo['disconnectedStatus']?.toString(),
              attended: attended,
              dataSource: callInfo['dataSource']?.toString() ?? 'device',
              permissionGranted: callInfo['permissionGranted'] == true,
              retrievedAttempt: callInfo['retrievedAttempt'] is int
                  ? callInfo['retrievedAttempt'] as int
                  : -1,
            );
          }
        }
      } else {
        if (mounted) _showCallCompletionDialog();
      }
    });
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
        if (mounted) _showUnansweredDialog();
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
        // Always block back — user must complete post-call update
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Incoming Call"),
          automaticallyImplyLeading: false, // always hide back arrow
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
                Text(
                  callStarted ? "On Call..." : "Launching call...",
                  style: TextStyle(
                    fontSize: 18,
                    color: callStarted ? Colors.green : Colors.blue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              // Cancel only during countdown — hidden after call starts
              if (!callTriggered) ...[
                const SizedBox(height: 40),
                ElevatedButton(
                  onPressed: () {
                    timer?.cancel();
                    callDurationTimer?.cancel();
                    _callStateSubscription?.cancel();
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
            ],
          ),
        ),
      ),
    );
  }
}
