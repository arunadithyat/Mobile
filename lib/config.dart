class AppConfig {

  static const String baseUrl =
      "https://erp.itgenie.online";

  static const String loginApi =
      "$baseUrl/api/method/login";

  static const String registerDeviceApi =
      "$baseUrl/api/method/itgenie.lead_calling.mobile_api.register_device";

  static const String opportunitiesApi =
      "$baseUrl/api/method/itgenie.lead_calling.mobile_api.get_opportunities";

  static const String pauseCallApi =
      "$baseUrl/api/method/itgenie.lead_calling.mobile_api.pause_call";

  static const String callQueueApi =
      "$baseUrl/api/method/callqueue";

  // Fix #9: Pause interval options moved to config
  static const List<int> pauseIntervalOptions = [5, 15, 30];
}