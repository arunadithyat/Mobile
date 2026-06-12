
import 'dart:async';
import 'dart:convert';

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

import 'api/device_api.dart';
import 'api/login_api.dart';
import 'api/opportunities_api.dart';
import 'api/call_queue_api.dart';
import 'config.dart';
import 'services/notification_service.dart';
import 'models/call_queue.dart';

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

class _HomePageState extends State<HomePage> {
  String token = "";
  List<Map<String, dynamic>> opportunities = [];
  bool isLoading = true;
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

  bool get isCallFlowPaused {
    if (pausedUntil == null) return false;
    return DateTime.now().isBefore(pausedUntil!);
  }

  @override
  void initState() {
    super.initState();
    _loadPendingQueue();
    _requestCallTelemetryPermissions();
    getFcmToken();
    _initializeNotifications();
    _listenForTokenRefresh();
    fetchOpportunities();
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
              if (item is CallQueueItem) {
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
    debugPrint("[QUEUE][FLOW] Adding to in-memory queue - reason=$reason");
    // Create CallQueueItem from the normalized data
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

    // Get token
    debugPrint("[FCM] Getting FCM token...");
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

  Future<void> fetchOpportunities() async {
    if (!mounted) return;
    setState(() {
      isLoading = true;
    });

    final result = await OpportunitiesApi.getOpportunities();

    if (!mounted) return;

    setState(() {
      isLoading = false;
      if (result["success"] == true) {
        opportunities = List<Map<String, dynamic>>.from(
          result["opportunities"] ?? [],
        );
      } else {
        opportunities = [];
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result["message"] ?? "Failed to fetch opportunities"),
          ),
        );
      }
    });
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

    if (isCallFlowPaused || _isLeadCallInProgress) {
      debugPrint("⏸️ Call flow is paused. Adding to queue...");
      final reason = isCallFlowPaused ? "paused_flow" : "already_in_call";
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
    if (routeResult is Map<String, dynamic> && routeResult['status'] == 'cancelled') {
      // Add to queue as cancelled — keeps position, user can restore and call later
      final enqueueResult = await _enqueueLeadCall(normalized, reason: "manual_cancel");
      if (!mounted) return;
      if (enqueueResult != null) {
        // Find the item just added and mark it cancelled
        final idx = callQueue.length - 1;
        setState(() {
          callQueue.markCancelled(idx);
        });
        debugPrint("[QUEUE] Marked cancelled at index=$idx");
      }
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
          callQueue.remove(selectedIndex);
          setState(() {});

          setState(() { _isLeadCallInProgress = true; });

          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => LeadCallScreen(data: callItem.toMap()),
            ),
          );

          if (!mounted) return;
          setState(() { _isLeadCallInProgress = false; });

          // User cancelled — keep it in queue as cancelled instead of removing
          if (result is Map<String, dynamic> && result['status'] == 'cancelled') {
            final enqueueResult = await _enqueueLeadCall(callItem.toMap(), reason: 'queue_call_cancelled');
            if (enqueueResult != null && mounted) {
              final idx = callQueue.length - 1;
              setState(() {
                callQueue.markCancelled(idx);
              });
              debugPrint("[QUEUE] Re-queued cancelled call at index=$idx");
            }
            return;
          }

          // Call was not answered — re-queue it and stop the loop
          if (result is Map<String, dynamic> && result['status'] == 'not_connected') {
            await _enqueueLeadCall(callItem.toMap(), reason: 'not_connected_requeue');
            return;
          }

          // Auto-process next call if queue still has items
          if (callQueue.isNotEmpty) {
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
      
      // Optionally process queued calls
      if (callQueue.isNotEmpty) {
        _showQueueProcessingOption();
      }
    } else {
      // Pause call flow for a selected interval
      final minutes = await _selectPauseMinutes();
      if (minutes == null || minutes <= 0 || !mounted) return;

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
        if (callQueue.isNotEmpty) {
          _showQueueProcessingOption();
        }
      });

      setState(() {
        pausedUntil = until;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Call flow paused for $minutes minute(s)")),
      );
    }
  }

  Future<int?> _selectPauseMinutes() async {
    // Fix #9: Use pauseIntervalOptions from config
    return showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Pause Call Flow"),
        content: const Text("Select pause interval"),
        actions: [
          ...AppConfig.pauseIntervalOptions.map(
            (minutes) => TextButton(
              onPressed: () => Navigator.pop(context, minutes),
              child: Text("$minutes min"),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
        ],
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
    final call = callQueue.removeFirst();
    if (call == null || !mounted) return;

    setState(() { _isLeadCallInProgress = true; });

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LeadCallScreen(data: call.toMap()),
      ),
    );

    if (!mounted) return;
    setState(() { _isLeadCallInProgress = false; });

    // Call was not answered — re-queue it and stop the loop
    if (result is Map<String, dynamic> && result['status'] == 'not_connected') {
      await _enqueueLeadCall(call.toMap(), reason: 'not_connected_requeue');
      return;
    }

    // Auto-process next call if queue still has items
    if (callQueue.isNotEmpty) {
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
  void dispose() {
    _pauseTimer?.cancel();
    _tokenRefreshSub?.cancel();
    _notificationSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Assigned Opportunities"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: logout,
            tooltip: "Logout",
          ),
        ],
      ),
      drawer: _buildDrawer(),
      body: Column(
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
                "Paused until: ${pausedUntil!.toLocal().toString().split('.')[0]}",
                style: TextStyle(
                  color: Colors.red.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Card(
              color: Colors.blueGrey.shade50,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Push Debug",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _lastPushReceivedAt = null;
                              _lastPushSource = "-";
                              _lastPushAction = "-";
                              _lastPushRaw = null;
                              _lastPushNormalized = null;
                              _pushReceivedCount = 0;
                            });
                          },
                          child: const Text("Clear"),
                        ),
                      ],
                    ),
                    Text("Count: $_pushReceivedCount"),
                    Text(
                      "Last At: ${_lastPushReceivedAt?.toLocal().toString().split('.').first ?? '-'}",
                    ),
                    Text("Source: $_lastPushSource"),
                    Text("Action: $_lastPushAction"),
                    const SizedBox(height: 6),
                    Text(
                      "Raw: ${_lastPushRaw == null ? '-' : jsonEncode(_lastPushRaw)}",
                      style: const TextStyle(fontSize: 11),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Normalized: ${_lastPushNormalized == null ? '-' : jsonEncode(_lastPushNormalized)}",
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Call Queue Section
          if (callQueue.isNotEmpty)
            Container(
              color: Colors.orange.shade50,
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.hourglass_empty, color: Colors.orange),
                          const SizedBox(width: 8),
                          Text(
                            "Queued Calls: ${callQueue.length}",
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                            ),
                          ),
                        ],
                      ),
                      ElevatedButton.icon(
                        onPressed: _processFirstQueuedCall,
                        icon: const Icon(Icons.phone),
                        label: const Text("Process"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 80,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: callQueue.length,
                      itemBuilder: (context, index) {
                        final call = callQueue.get(index);
                        if (call == null) return const SizedBox.shrink();
                        return Card(
                          margin: const EdgeInsets.only(right: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  call.customerName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  call.mobileNo,
                                  style: const TextStyle(fontSize: 11),
                                ),
                                Text(
                                  call.formattedTime,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          // Opportunities List
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : opportunities.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.inbox,
                              size: 80,
                              color: Colors.grey,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              "No opportunities assigned",
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
                              onPressed: fetchOpportunities,
                              icon: const Icon(Icons.refresh),
                              label: const Text("Refresh"),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: fetchOpportunities,
                        child: ListView.builder(
                          itemCount: opportunities.length,
                          itemBuilder: (context, index) {
                            final opp = opportunities[index];
                            return OpportunityCard(
                              opportunity: opp,
                              onPause: () async {
                                final result = await OpportunitiesApi.pauseCall(
                                  opp["name"] ?? "",
                                );
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      result["message"] ??
                                          (result["success"]
                                              ? "Call paused"
                                              : "Failed to pause"),
                                    ),
                                  ),
                                );
                                if (result["success"] == true) {
                                  fetchOpportunities();
                                }
                              },
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (callQueue.isNotEmpty)
            FloatingActionButton(
              onPressed: () => _showCallQueueScreen(),
              tooltip: "Call Queue (${callQueue.length})",
              heroTag: "queue_btn",
              backgroundColor: Colors.orange,
              child: Stack(
                alignment: Alignment.topRight,
                children: [
                  const Icon(Icons.queue_music),
                  Positioned(
                    right: -5,
                    top: -5,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        "${callQueue.length}",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          FloatingActionButton.extended(
            onPressed: fetchOpportunities,
            icon: const Icon(Icons.refresh),
            label: const Text("Refresh"),
            heroTag: "refresh_btn",
          ),
        ],
      ),
    );
  }
}

class OpportunityCard extends StatelessWidget {
  final Map<String, dynamic> opportunity;
  final VoidCallback onPause;

  const OpportunityCard({
    super.key,
    required this.opportunity,
    required this.onPause,
  });

  @override
  Widget build(BuildContext context) {
    final customerName = opportunity["customer_name"] ?? "N/A";
    final mobileNo = opportunity["mobile_no"] ?? "N/A";
    final oppName = opportunity["name"] ?? "N/A";
    final amount = opportunity["amount"] ?? "N/A";
    final stage = opportunity["stage"] ?? "N/A";

    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customerName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        mobileNo,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.phone_in_talk, color: Colors.green),
                  onPressed: () {
                    // Trigger call directly
                    _makeCall(context, mobileNo);
                  },
                  tooltip: "Call now",
                ),
              ],
            ),
            const SizedBox(height: 12),
            Divider(),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Opportunity",
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    Text(
                      oppName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      "Amount",
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    Text(
                      amount.toString(),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Stage",
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    Text(
                      stage,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: onPause,
                  icon: const Icon(Icons.pause),
                  label: const Text("Pause"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _makeCall(BuildContext context, String phoneNumber) async {
    if (phoneNumber.isEmpty || phoneNumber == "N/A") return;

    final phonePermission = await Permission.phone.request();

    if (!phonePermission.isGranted) {
      debugPrint("PHONE PERMISSION NOT GRANTED");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Phone permission not granted")),
        );
      }
      return;
    }

    final success = await launchPhoneCall(phoneNumber);
    if (!success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Unable to launch phone app")),
      );
    }
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
    debugPrint('[CALLLOG] 📞 Starting call log fetch with retries for: $mobileNo');
    
    // NEW: Check permission first
    final permissionGranted = await AutoDialer.ensureCallLogPermission();
    debugPrint('[CALLLOG] READ_CALL_LOG permission: ${permissionGranted ? '✅ GRANTED' : '❌ DENIED'}');
    
    final initiatedAt = _initiatedAt ?? DateTime.now();
    final maxAttempts = permissionGranted ? 4 : 2;

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      debugPrint('[CALLLOG] 🔄 Attempt $attempt/$maxAttempts for: $mobileNo');

      try {
        final callInfo = await AutoDialer.getLastCallInfoForSession(
          mobileNo,
          initiatedAt: initiatedAt,
        );

        final found = callInfo['found'] == true;
        final durationSeconds = callInfo['durationSeconds'] is int
            ? callInfo['durationSeconds'] as int
            : int.tryParse(callInfo['durationSeconds']?.toString() ?? '0') ?? 0;

        if (found) {
          debugPrint('[CALLLOG] ✅ Found call info on attempt $attempt');
          debugPrint('[CALLLOG] Duration: ${durationSeconds}s, Status: ${callInfo['callStatus']}, Attended: ${callInfo['attended']}');

          callInfo['dataSource'] = 'device';
          callInfo['permissionGranted'] = permissionGranted;
          callInfo['retrievedAttempt'] = attempt;
          return callInfo;
        }

        if (attempt < maxAttempts) {
          final delayMs = 300 + (attempt * 100);
          debugPrint('[CALLLOG] ⏳ No data on attempt $attempt, waiting ${delayMs}ms before retry...');
          await Future.delayed(Duration(milliseconds: delayMs));
        }
      } catch (e) {
        debugPrint('[CALLLOG] ❌ Error on attempt $attempt: $e');
        if (attempt < maxAttempts) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }
    }
    
    debugPrint('[CALLLOG] ❌ Failed to retrieve call info after $maxAttempts attempts');
    debugPrint('[CALLLOG] Using fallback - user will enter data manually');
    
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
        debugPrint('[CALL_STATE] Event received: $event');
        if (event is Map) {
          final state = event['state'];
          if (state == 'CALL_ENDED' && callStarted && !_wasBackgroundedDuringCall) {
            debugPrint('[CALL_STATE] Call ended while app is active');
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
    debugPrint('[CALL] Call ended - showing completion dialog directly');
    
    final mobileNo = widget.data["mobile_no"]?.toString() ?? "";
    if (mobileNo.isNotEmpty) {
      final callInfo = await _fetchCallInfoWithRetry(mobileNo);
      if (callInfo['found'] == true) {
        final attended = callInfo['attended'] == true;

        // Call log shows customer did not answer — auto-log and re-queue
        if (!attended) {
          callStarted = false;
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
        final callDuration = Duration(seconds: durationSeconds);
        final callStatus = callInfo['callStatus']?.toString() ?? 'Unknown';
        final disconnectedStatus =
            callInfo['disconnectedStatus']?.toString() ?? 'unknown';

        if (mounted) {
          await _showCallCompletionDialog(
            callDuration: callDuration,
            callStatus: callStatus,
            disconnectedStatus: disconnectedStatus,
            attended: attended,
            dataSource: callInfo['dataSource']?.toString() ?? 'unknown',
            permissionGranted: callInfo['permissionGranted'] == true,
            retrievedAttempt: callInfo['retrievedAttempt']?.toString() != null
                ? int.tryParse(callInfo['retrievedAttempt']?.toString() ?? '-1') ?? -1
                : -1,
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
      if (mounted) {
        await _showCallCompletionDialog();
      }
    }

    callStarted = false;
  }

  void startCountdown() {
    // Fix #5: Add try-catch around makeCall to cancel timer on error
    timer = Timer.periodic(
      const Duration(seconds: 1),
      (Timer t) {
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
          setState(() {
            countdown--;
          });
        }
      },
    );
  }

  void _startCallDurationTracking() {
    debugPrint("[CALL] Starting to track call duration");
    callStartTime = DateTime.now();
    
    // Track call duration every second
    callDurationTimer = Timer.periodic(
      const Duration(seconds: 1),
      (Timer t) {
        // We can update UI with call duration if needed
        if (mounted) {
          setState(() {});
        }
      },
    );
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
    debugPrint("[CALL] Showing call completion dialog");
    
    if (!mounted) return;

    final customerName = widget.data["customer_name"]?.toString() ?? "Unknown";
    final doctype = widget.data["doctype"]?.toString() ?? "Lead";
    final docname = widget.data["docname"]?.toString() ?? "";
    final mobileNo = widget.data["mobile_no"]?.toString() ?? "";

    // Stop tracking duration
    callDurationTimer?.cancel();
    final duration = callDuration ?? _getCallDuration();

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
    ).then((value) {
      // Dialog closed
      if (mounted) {
        Navigator.pop(context);
      }
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Phone number not available")),
        );
      }
      return;
    }

    debugPrint("[CALL] 🔐 Verifying permissions before dial...");
    final phonePermission = await Permission.phone.request();
    if (!phonePermission.isGranted) {
      debugPrint("[CALL] ❌ Phone permission not granted");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Phone permission required")),
        );
      }
      return;
    }
    debugPrint("[CALL] ✅ Phone permission verified");

    final callLogPermissionGranted = await AutoDialer.ensureCallLogPermission();
    if (!callLogPermissionGranted) {
      debugPrint("[CALL] ⚠️ READ_CALL_LOG permission not granted - will use fallback logic");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Cannot read device call logs - will use manual entry"),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } else {
      debugPrint("[CALL] ✅ READ_CALL_LOG permission confirmed");
    }

    // Log call initiation
    final initiatedAt = DateTime.now();
    _initiatedAt = initiatedAt;
    debugPrint("[CALL] 📞 Initiating call to: $customerName ($mobileNo)");
    
    try {
      // Log to backend
      await CallLogApi.logCallInitiation(
        doctype: doctype,
        docname: docname,
        customerName: customerName,
        mobileNo: mobileNo,
        initiatedAt: initiatedAt,
      );
      debugPrint("[CALL] ✅ Call logged to backend");
    } catch (e) {
      debugPrint("[CALL] ⚠️ Failed to log call: $e");
    }

    // Auto-dial directly without showing dialer
    debugPrint("[CALL] 🚀 Using AutoDialer to initiate call directly");
    
    final success = await AutoDialer.autoCall(mobileNo);
    // Fix #1: Set callStarted to actual success status (not always false)
    callStarted = success;

    if (!success) {
      debugPrint("[CALL] ❌ AutoDialer failed, trying fallback");
      // Try opening dialer as fallback
      final fallbackSuccess = await AutoDialer.openDialer(mobileNo);
      callStarted = fallbackSuccess;
      
      if (!fallbackSuccess && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Unable to initiate call")),
        );
        
        // Log error
        await CallLogApi.logCallError(
          doctype: doctype,
          docname: docname,
          customerName: customerName,
          mobileNo: mobileNo,
          errorMessage: "Failed to initiate auto call - both AutoDialer and fallback failed",
        );
      }
    } else {
      debugPrint("[CALL] ✅ Call initiated successfully via AutoDialer");
      callStarted = true;
    }

    if (callStarted) {
      _startCallDurationTracking();
    }

    // Do not show the completion dialog automatically.
    // Completion should be triggered when the call actually ends or by user action.
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
    if (state == AppLifecycleState.paused) {
      if (callStarted) {
        _wasBackgroundedDuringCall = true;
        _backgroundedAt = DateTime.now();
        debugPrint('[CALL] App paused after call launch');
      }
    }

    if (state == AppLifecycleState.resumed) {
      if (callStarted && _wasBackgroundedDuringCall) {
        final pausedDuration = _backgroundedAt == null
            ? Duration.zero
            : DateTime.now().difference(_backgroundedAt!);

        debugPrint(
            '[CALL] App resumed after background; pausedDuration=$pausedDuration');

        if (pausedDuration >= const Duration(seconds: 2)) {
          debugPrint(
              '[CALL] Showing completion dialog after resume from call');
          callDurationTimer?.cancel();
          if (mounted) {
            _handleResumeAfterCall();
          }
          callStarted = false;
          callStartTime = null;
          _wasBackgroundedDuringCall = false;
          _backgroundedAt = null;
        } else {
          debugPrint(
              '[CALL] Resume detected too quickly after pause; skipping completion dialog');
        }
      }
    }
  }

  Future<void> _handleResumeAfterCall() async {
    final mobileNo = widget.data["mobile_no"]?.toString() ?? "";
    if (mobileNo.isEmpty) {
      _showCallCompletionDialog();
      return;
    }

    final callInfo = await _fetchCallInfoWithRetry(mobileNo);
    if (callInfo['found'] == true) {
      final attended = callInfo['attended'] == true;

      // Call log shows customer did not answer — auto-log and re-queue
      if (!attended) {
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
      final callDuration = Duration(seconds: durationSeconds);
      final callStatus = callInfo['callStatus']?.toString() ?? 'Unknown';
      final disconnectedStatus =
          callInfo['disconnectedStatus']?.toString() ?? 'unknown';
      _showCallCompletionDialog(
        callDuration: callDuration,
        callStatus: callStatus,
        disconnectedStatus: disconnectedStatus,
        attended: attended,
        dataSource: callInfo['dataSource']?.toString() ?? 'unknown',
        permissionGranted: callInfo['permissionGranted'] == true,
        retrievedAttempt: callInfo['retrievedAttempt']?.toString() != null
            ? int.tryParse(callInfo['retrievedAttempt']?.toString() ?? '-1') ?? -1
            : -1,
      );
    } else {
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
              const Icon(
                Icons.call,
                size: 80,
                color: Colors.green,
              ),
              const SizedBox(height: 20),
              Text(
                widget.data["customer_name"] ?? "Incoming Call",
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                widget.data["mobile_no"] ?? "Unknown",
                style: const TextStyle(
                  fontSize: 18,
                  color: Colors.grey,
                ),
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
                  timer?.cancel();
                  Navigator.pop(context, {'status': 'cancelled'});
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 16,
                  ),
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
