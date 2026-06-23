class AppConfig {

  static const String baseUrl =
      "https://erp.itgenie.online";

  static const String loginApi =
      "$baseUrl/api/method/login";

  // Version check
  static const String updateRequiredApi =
      "$baseUrl/api/method/update_required";

  // Get field owners
  static const String getFieldOwnersApi =
      "$baseUrl/api/method/get_fieldowners";

  // Get comments/notes for a call
  static const String getCommentsApi =
      "$baseUrl/api/method/get_comments";

  static const String registerDeviceApi =
      "$baseUrl/api/method/itgenie.lead_calling.mobile_api.register_device";

  static const String opportunitiesApi =
      "$baseUrl/api/method/itgenie.lead_calling.mobile_api.get_opportunities";

  static const String pauseCallApi =
      "$baseUrl/api/method/itgenie.lead_calling.mobile_api.pause_call";

  // READ-only endpoint — returns pending calls, no FCM, no side effects
  static const String callQueueApi =
      "$baseUrl/api/method/get_pending_calls";

  // Receives device incoming-call entries; backend matches the number
  // against Lead/Opportunity and creates a Call Log when relevant.
  static const String syncIncomingCallsApi =
      "$baseUrl/api/method/itgenie.lead_calling.mobile_api.sync_incoming_calls";

  // Post-call: update the actual Call Log doctype in ERPNext
  static const String updateCallLogApi =
      "$baseUrl/api/resource/Call%20Log";

  // Create incoming Call Log via custom server script
  static const String createIncomingCallLogApi =
      "$baseUrl/api/method/calllog";

  // KPI card counts
  static const String kpiApi =
      "$baseUrl/api/method/kpi";

  // Fetch current Lead field values
  static const String leadValuesApi =
      "$baseUrl/api/method/leadvalues";

  // Update Lead fields after answered call
  static const String updateLeadApi =
      "$baseUrl/api/method/update_lead";

  // Create Opportunity from Lead
  static const String createOpportunityApi =
      "$baseUrl/api/method/create_opportunity";

  // Fetch Opportunity field options
  static const String opportunityValuesApi =
      "$baseUrl/api/method/opportunity_values";

  // Update Opportunity fields
  static const String updateOpportunityApi =
      "$baseUrl/api/method/opportunity_update";

  // Update Lead status (RNR/Busy/etc.) after unanswered call
  static const String updateLeadRnrApi =
      "$baseUrl/api/method/update_lead_rnr_followup";

  // Update Opportunity status (RNR/Junk) after unanswered call
  static const String updateOpportunityRnrApi =
      "$baseUrl/api/method/update_opportunity_rnr";

  // Fix #9: Pause interval options moved to config
  static const List<int> pauseIntervalOptions = [5, 15, 30];

  // Daily collection target (₹) for the scorecard, until target API is ready
  static const double dailyCollectionTarget = 100000;
}