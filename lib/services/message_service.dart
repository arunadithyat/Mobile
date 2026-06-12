import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Standard message templates. {name} is replaced with the customer name.
class MessageTemplates {
  static const Map<String, String> templates = {
    'Missed you':
        'Hello {name}, this is HomeGenie — One Stop Many Solutions. We tried reaching you regarding your enquiry. Please share a convenient time to call you back.',
    'Follow up':
        'Hello {name}, following up on your enquiry with HomeGenie. We would love to assist you further. Reply here or call us back at your convenience.',
    'Order update':
        'Hello {name}, this is regarding your order with HomeGenie. Our team would like to share an update. Please let us know a good time to connect.',
    'Thank you':
        'Thank you {name} for speaking with HomeGenie today! For anything else, we are just a message away — One Stop Many Solutions.',
  };

  static String fill(String template, String customerName) {
    final name = customerName.trim().isEmpty ? 'Customer' : customerName.trim();
    return template.replaceAll('{name}', name);
  }
}

class MessageService {
  static String _cleanNumber(String number) {
    var n = number.replaceAll(RegExp(r'[^\d+]'), '');
    // WhatsApp needs country code; assume India if 10 digits
    if (!n.startsWith('+') && n.length == 10) n = '91$n';
    return n.replaceAll('+', '');
  }

  static Future<bool> sendWhatsApp(String number, String message) async {
    final n = _cleanNumber(number);
    final uri = Uri.parse(
        'https://wa.me/$n?text=${Uri.encodeComponent(message)}');
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[MSG] WhatsApp launch failed: $e');
      return false;
    }
  }

  static Future<bool> sendSms(String number, String message) async {
    final uri = Uri(
      scheme: 'sms',
      path: number,
      queryParameters: {'body': message},
    );
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[MSG] SMS launch failed: $e');
      return false;
    }
  }
}
