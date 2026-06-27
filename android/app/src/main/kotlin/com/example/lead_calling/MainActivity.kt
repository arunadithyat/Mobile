package com.example.lead_calling

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.CallLog
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.telephony.PhoneNumberUtils
import android.telephony.PhoneStateListener
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
  private val CHANNEL = "lead_calling/dialer"
  private val CALL_STATE_CHANNEL = "lead_calling/call_state"
  private val REQUEST_CALL_LOG_PERMISSION = 1001
  private val REQUEST_PHONE_STATE_PERMISSION = 1002
  private var pendingResult: MethodChannel.Result? = null
  private var pendingPermissionResult: MethodChannel.Result? = null
  private var pendingPhoneNumber: String? = null
  private var pendingInitiatedAtMs: Long = 0L
  private var callStateEventSink: EventChannel.EventSink? = null
  private var callStateListener: CallStateListener? = null
  private var isCallActive = false

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    
    // Method channel for dialer methods
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
      when (call.method) {
        "autoCall" -> {
          val phoneNumber = call.argument<String>("phoneNumber") ?: ""
          val simId = call.argument<String>("simId")
          result.success(startCall(phoneNumber, simId))
        }
        "getAvailableSims" -> {
          result.success(getAvailableSims())
        }
        "openDialer" -> {
          val phoneNumber = call.argument<String>("phoneNumber") ?: ""
          result.success(openDialer(phoneNumber))
        }
        "getLastCallInfo" -> {
          val phoneNumber = call.argument<String>("phoneNumber") ?: ""
          val initiatedAtMs = call.argument<Number>("initiatedAtMs")?.toLong() ?: 0L
          if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CALL_LOG) != PackageManager.PERMISSION_GRANTED) {
            pendingResult = result
            pendingPhoneNumber = phoneNumber
            pendingInitiatedAtMs = initiatedAtMs
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.READ_CALL_LOG), REQUEST_CALL_LOG_PERMISSION)
          } else {
            result.success(getLastCallInfo(phoneNumber, initiatedAtMs))
          }
        }
        "isOnCall" -> {
          val tm = getSystemService(Context.TELEPHONY_SERVICE) as android.telephony.TelephonyManager
          val onCall = tm.callState != android.telephony.TelephonyManager.CALL_STATE_IDLE
          println("[NATIVE] isOnCall: $onCall (state=${tm.callState})")
          result.success(onCall)
        }
        "getOwnNumber" -> {
          try {
            val tm = getSystemService(Context.TELEPHONY_SERVICE) as android.telephony.TelephonyManager
            val number = tm.line1Number ?: ""
            result.success(number)
          } catch (e: Exception) {
            result.success("")
          }
        }
        "ensureCallLogPermission" -> {
          if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CALL_LOG) == PackageManager.PERMISSION_GRANTED) {
            result.success(true)
          } else {
            pendingPermissionResult = result
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.READ_CALL_LOG), REQUEST_CALL_LOG_PERMISSION)
          }
        }
        "getIncomingCallsSince" -> {
          val sinceMs = call.argument<Number>("sinceMs")?.toLong() ?: 0L
          val simId = call.argument<String>("simId")
          if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CALL_LOG) != PackageManager.PERMISSION_GRANTED) {
            result.success(emptyList<Map<String, Any>>())
          } else {
            result.success(getIncomingCallsSince(sinceMs, simId))
          }
        }
        else -> result.notImplemented()
      }
    }

    // Event channel for call state events
    EventChannel(flutterEngine.dartExecutor.binaryMessenger, CALL_STATE_CHANNEL).setStreamHandler(
      object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
          callStateEventSink = events
          startListeningToCallState()
        }

        override fun onCancel(arguments: Any?) {
          callStateEventSink = null
          stopListeningToCallState()
        }
      }
    )
  }

  override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
    super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    if (requestCode == REQUEST_CALL_LOG_PERMISSION) {
      val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
      if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
        val phoneNumber = pendingPhoneNumber ?: ""
        pendingResult?.success(getLastCallInfo(phoneNumber, pendingInitiatedAtMs))
      } else {
        pendingResult?.error("PERMISSION_DENIED", "Read call log permission denied", null)
      }
      pendingPermissionResult?.success(granted)
      pendingResult = null
      pendingPermissionResult = null
      pendingPhoneNumber = null
      pendingInitiatedAtMs = 0L
    }
    if (requestCode == REQUEST_PHONE_STATE_PERMISSION) {
      val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
      if (granted) {
        startListeningToCallState()
      }
    }
  }

  private fun startListeningToCallState() {
    if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE) != PackageManager.PERMISSION_GRANTED) {
      ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.READ_PHONE_STATE), REQUEST_PHONE_STATE_PERMISSION)
      return
    }

    val telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
    callStateListener = CallStateListener()
    telephonyManager.listen(callStateListener, PhoneStateListener.LISTEN_CALL_STATE)
  }

  private fun stopListeningToCallState() {
    if (callStateListener != null) {
      val telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
      telephonyManager.listen(callStateListener, PhoneStateListener.LISTEN_NONE)
      callStateListener = null
    }
  }

  private inner class CallStateListener : PhoneStateListener() {
    override fun onCallStateChanged(state: Int, incomingNumber: String?) {
      super.onCallStateChanged(state, incomingNumber)
      when (state) {
        TelephonyManager.CALL_STATE_OFFHOOK -> {
          isCallActive = true
          callStateEventSink?.success(mapOf("state" to "CALL_STARTED", "timestamp" to System.currentTimeMillis()))
        }
        TelephonyManager.CALL_STATE_IDLE -> {
          if (isCallActive) {
            isCallActive = false
            callStateEventSink?.success(mapOf("state" to "CALL_ENDED", "timestamp" to System.currentTimeMillis()))
          }
        }
        else -> {}
      }
    }
  }

  /// Returns incoming + missed + rejected calls since the given timestamp,
  /// newest first, capped at 100 entries.
  /// If simId is provided, only returns calls from that SIM.
  private fun getIncomingCallsSince(sinceMs: Long, simId: String? = null): List<Map<String, Any>> {
    val projection = arrayOf(CallLog.Calls.NUMBER, CallLog.Calls.TYPE, CallLog.Calls.DURATION, CallLog.Calls.DATE, CallLog.Calls.PHONE_ACCOUNT_ID)
    
    var selection = "${CallLog.Calls.DATE} > ? AND ${CallLog.Calls.TYPE} IN (?, ?, ?)"
    val args = mutableListOf(
      sinceMs.toString(),
      CallLog.Calls.INCOMING_TYPE.toString(),
      CallLog.Calls.MISSED_TYPE.toString(),
      CallLog.Calls.REJECTED_TYPE.toString(),
    )
    
    // Filter by SIM if configured
    if (simId != null && simId.isNotEmpty()) {
      selection += " AND ${CallLog.Calls.PHONE_ACCOUNT_ID} = ?"
      args.add(simId)
      println("[NATIVE] Filtering incoming calls by SIM: $simId")
    }
    
    val cursor = contentResolver.query(
      CallLog.Calls.CONTENT_URI,
      projection,
      selection,
      args.toTypedArray(),
      "${CallLog.Calls.DATE} DESC"
    )

    val results = mutableListOf<Map<String, Any>>()
    cursor?.use {
      val numberIndex = it.getColumnIndexOrThrow(CallLog.Calls.NUMBER)
      val typeIndex = it.getColumnIndexOrThrow(CallLog.Calls.TYPE)
      val durationIndex = it.getColumnIndexOrThrow(CallLog.Calls.DURATION)
      val dateIndex = it.getColumnIndexOrThrow(CallLog.Calls.DATE)

      while (it.moveToNext() && results.size < 100) {
        val callType = it.getInt(typeIndex)
        val duration = it.getInt(durationIndex)
        val typeName = when (callType) {
          CallLog.Calls.INCOMING_TYPE -> "incoming"
          CallLog.Calls.MISSED_TYPE -> "missed"
          CallLog.Calls.REJECTED_TYPE -> "rejected"
          else -> "other"
        }
        results.add(mapOf(
          "number" to (it.getString(numberIndex) ?: ""),
          "type" to typeName,
          "durationSeconds" to duration,
          "timestamp" to it.getLong(dateIndex),
          "attended" to (callType == CallLog.Calls.INCOMING_TYPE && duration > 0),
        ))
      }
    }
    return results
  }

  private fun getLastCallInfo(phoneNumber: String, initiatedAtMs: Long): Map<String, Any> {
    val projection = arrayOf(CallLog.Calls.NUMBER, CallLog.Calls.TYPE, CallLog.Calls.DURATION, CallLog.Calls.DATE)
    val cursor = contentResolver.query(
      CallLog.Calls.CONTENT_URI,
      projection,
      null,
      null,
      "${CallLog.Calls.DATE} DESC"
    )

    val now = System.currentTimeMillis()
    val maxWindowMs = 15 * 60 * 1000L
    var bestMatch: Map<String, Any>? = null
    var bestDelta = Long.MAX_VALUE

    cursor?.use {
      val numberIndex = it.getColumnIndexOrThrow(CallLog.Calls.NUMBER)
      val typeIndex = it.getColumnIndexOrThrow(CallLog.Calls.TYPE)
      val durationIndex = it.getColumnIndexOrThrow(CallLog.Calls.DURATION)
      val dateIndex = it.getColumnIndexOrThrow(CallLog.Calls.DATE)

      while (it.moveToNext()) {
        val loggedNumber = it.getString(numberIndex)
        if (PhoneNumberUtils.compare(loggedNumber, phoneNumber)) {
          val callType = it.getInt(typeIndex)
          val duration = it.getInt(durationIndex)
          val timestamp = it.getLong(dateIndex)
          if (now - timestamp > maxWindowMs) continue

          val baseline = if (initiatedAtMs > 0L) initiatedAtMs else now
          val delta = kotlin.math.abs(timestamp - baseline)
          val status = mapCallTypeToStatus(callType, duration)
          val attended = callType == CallLog.Calls.OUTGOING_TYPE && duration > 0
          val disconnectedStatus = mapDisconnectedStatus(callType, duration)
          val candidate = mapOf(
            "found" to true,
            "durationSeconds" to duration,
            "callType" to callType,
            "callStatus" to status,
            "disconnectedStatus" to disconnectedStatus,
            "attended" to attended,
            "timestamp" to timestamp,
          )
          if (delta < bestDelta) {
            bestDelta = delta
            bestMatch = candidate
          }
        }
      }
    }

    if (bestMatch != null) return bestMatch!!

    return mapOf(
      "found" to false,
      "durationSeconds" to 0,
      "callType" to 0,
      "callStatus" to "Unknown",
      "disconnectedStatus" to "Unknown",
      "attended" to false,
      "timestamp" to 0,
    )
  }

  private fun mapCallTypeToStatus(callType: Int, duration: Int): String {
    return when (callType) {
      CallLog.Calls.OUTGOING_TYPE -> if (duration > 0) "Connected" else "Disconnected"
      CallLog.Calls.MISSED_TYPE -> "Missed"
      CallLog.Calls.REJECTED_TYPE -> "Rejected"
      CallLog.Calls.INCOMING_TYPE -> if (duration > 0) "Answered" else "Missed"
      else -> "Unknown"
    }
  }

  private fun mapDisconnectedStatus(callType: Int, duration: Int): String {
    return when (callType) {
      CallLog.Calls.OUTGOING_TYPE -> if (duration > 0) "remote_or_normal_hangup" else "not_connected"
      CallLog.Calls.MISSED_TYPE -> "not_answered"
      CallLog.Calls.REJECTED_TYPE -> "rejected"
      CallLog.Calls.INCOMING_TYPE -> if (duration > 0) "remote_or_normal_hangup" else "not_answered"
      else -> "unknown"
    }
  }

  private fun startCall(phoneNumber: String, simId: String? = null): Boolean {
    return try {
      val intent = Intent(Intent.ACTION_CALL, Uri.parse("tel:$phoneNumber"))
      intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

      // If SIM ID provided, set PhoneAccountHandle to skip SIM chooser
      if (simId != null && simId.isNotEmpty()) {
        try {
          val telecomManager = getSystemService(Context.TELECOM_SERVICE) as TelecomManager
          if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE) == PackageManager.PERMISSION_GRANTED) {
            val accounts = telecomManager.callCapablePhoneAccounts
            var matched: PhoneAccountHandle? = null

            // Try 1: direct ID match
            for (account in accounts) {
              if (account.id == simId) {
                matched = account
                println("[NATIVE] SIM matched by ID: $simId")
                break
              }
            }

            // Try 2: match by subscription ID → slot index
            if (matched == null) {
              try {
                val subscriptionManager = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as SubscriptionManager
                val subscriptions = subscriptionManager.activeSubscriptionInfoList ?: emptyList()
                for ((index, sub) in subscriptions.withIndex()) {
                  if (sub.subscriptionId.toString() == simId && index < accounts.size) {
                    matched = accounts[index]
                    println("[NATIVE] SIM matched by subscriptionId: $simId → slot $index")
                    break
                  }
                }
              } catch (e: Exception) {
                println("[NATIVE] Subscription match error: ${e.message}")
              }
            }

            if (matched != null) {
              intent.putExtra("android.telecom.extra.PHONE_ACCOUNT_HANDLE", matched)
              println("[NATIVE] Using SIM: ${matched.id}")
            } else {
              println("[NATIVE] No SIM match found for: $simId — system chooser will appear")
            }
          }
        } catch (e: Exception) {
          println("[NATIVE] SIM selection error (falling back): ${e.message}")
        }
      }

      startActivity(intent)
      true
    } catch (e: Exception) {
      e.printStackTrace()
      false
    }
  }

  private fun getAvailableSims(): List<Map<String, String>> {
    val sims = mutableListOf<Map<String, String>>()
    try {
      if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE) != PackageManager.PERMISSION_GRANTED) {
        println("[NATIVE] READ_PHONE_STATE not granted — can't list SIMs")
        return sims
      }

      // Primary: Use TelecomManager for PhoneAccountHandle IDs
      val telecomManager = getSystemService(Context.TELECOM_SERVICE) as TelecomManager
      var accounts: List<PhoneAccountHandle> = emptyList()
      try {
        accounts = telecomManager.callCapablePhoneAccounts
        println("[NATIVE] TelecomManager found ${accounts.size} account(s)")
      } catch (e: Exception) {
        println("[NATIVE] TelecomManager error: ${e.message}")
      }

      // Get subscription info for labels and numbers
      val subscriptionManager = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as SubscriptionManager
      val subscriptions = try {
        subscriptionManager.activeSubscriptionInfoList ?: emptyList()
      } catch (e: Exception) {
        println("[NATIVE] SubscriptionManager error: ${e.message}")
        emptyList()
      }
      println("[NATIVE] SubscriptionManager found ${subscriptions.size} subscription(s)")

      if (accounts.isNotEmpty()) {
        // Use TelecomManager accounts (preferred — has PhoneAccountHandle ID)
        for ((index, account) in accounts.withIndex()) {
          val phoneAccount = telecomManager.getPhoneAccount(account)
          val label = phoneAccount?.label?.toString() ?: "SIM ${index + 1}"
          val number = if (index < subscriptions.size) {
            subscriptions[index].number ?: ""
          } else ""

          sims.add(mapOf(
            "id" to account.id,
            "label" to label,
            "number" to number,
            "slot" to (index + 1).toString()
          ))
        }
      } else if (subscriptions.isNotEmpty()) {
        // Fallback: Use SubscriptionManager (no PhoneAccountHandle, but has SIM info)
        for ((index, sub) in subscriptions.withIndex()) {
          sims.add(mapOf(
            "id" to sub.subscriptionId.toString(),
            "label" to (sub.carrierName?.toString() ?: "SIM ${index + 1}"),
            "number" to (sub.number ?: ""),
            "slot" to (sub.simSlotIndex + 1).toString()
          ))
        }
      }

      println("[NATIVE] Returning ${sims.size} SIM(s): $sims")
    } catch (e: Exception) {
      println("[NATIVE] getAvailableSims error: ${e.message}")
    }
    return sims
  }

  private fun openDialer(phoneNumber: String): Boolean {
    return try {
      val intent = Intent(Intent.ACTION_DIAL, Uri.parse("tel:$phoneNumber"))
      intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      startActivity(intent)
      true
    } catch (e: Exception) {
      e.printStackTrace()
      false
    }
  }
}
