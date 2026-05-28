import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

class OpportunitiesApi {
  // Fix #10: Add opportunity data validation
  static bool _validateOpportunity(Map<String, dynamic> opp) {
    final name = opp['name']?.toString() ?? '';
    final mobileNo = opp['mobile_no']?.toString() ?? '';
    
    if (name.isEmpty || mobileNo.isEmpty) {
      debugPrint('[OPP] ❌ Invalid opportunity - missing required fields');
      return false;
    }
    
    return true;
  }

  static Future<Map<String, dynamic>> getOpportunities() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final cookie = prefs.getString("cookie") ?? "";
      final username = prefs.getString("username") ?? "";

      if (cookie.isEmpty || username.isEmpty) {
        return {
          "success": false,
          "message": "Session not found. Please login again.",
          "opportunities": []
        };
      }

      // Fix #4: Add network timeout
      final response = await http.get(
        Uri.parse(AppConfig.opportunitiesApi),
        headers: {
          'Content-Type': 'application/json',
          'Cookie': cookie,
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);

        // Assuming the API returns a list of opportunities
        // Adjust this based on your actual API response structure
        final rawOpportunities = jsonData["message"] is List
            ? jsonData["message"]
            : jsonData["message"]?["data"] ?? [];

        // Fix #10: Validate opportunities before returning
        final opportunities = (rawOpportunities as List?)
            ?.whereType<Map<String, dynamic>>()
            .where((opp) => _validateOpportunity(opp))
            .toList() ?? [];

        debugPrint('[OPP] ✅ Fetched ${opportunities.length} valid opportunities');
        return {
          "success": true,
          "opportunities": opportunities
        };
      } else {
        return {
          "success": false,
          "message": "Failed to fetch opportunities",
          "opportunities": []
        };
      }
    } catch (e) {
      debugPrint('[OPP] ❌ Error fetching opportunities: $e');
      return {
        "success": false,
        "message": e.toString(),
        "opportunities": []
      };
    }
  }

  static Future<Map<String, dynamic>> pauseCall(String opportunityId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cookie = prefs.getString("cookie") ?? "";

      // Fix #4: Add network timeout
      final response = await http.post(
        Uri.parse(AppConfig.pauseCallApi),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Cookie': cookie,
        },
        body: {
          "opportunity_id": opportunityId,
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return {
          "success": true,
          "message": "Call paused successfully"
        };
      } else {
        return {
          "success": false,
          "message": "Failed to pause call"
        };
      }
    } catch (e) {
      return {
        "success": false,
        "message": e.toString()
      };
    }
  }
}
