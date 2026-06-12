// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:lead_calling/models/call_queue.dart';

void main() {
  test('call queue can be replaced with endpoint items', () {
    final queue = CallQueue();
    final endpointItem = CallQueueItem.fromMap({
      'name': 'LEAD-001',
      'customer_name': 'Test Customer',
      'mobile_no': '1234567890',
      'queued_at': '2026-06-12T10:00:00.000',
    });

    queue.addItem(endpointItem);
    expect(queue.length, 1);
    expect(queue.get(0)?.docname, 'LEAD-001');

    queue.clearAll();
    expect(queue.isEmpty, isTrue);
  });
}
