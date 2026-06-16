enum CallQueueStatus { pending, cancelled }

class CallQueueItem {
  final String callLogName; // Call Log document name (e.g. "CALL-0001") for post-call updates
  final String doctype;
  final String docname;
  final String lead; // Lead/Opportunity reference (e.g. CRM-LEAD-2026-14403)
  final String customerName;
  final String mobileNo;
  final DateTime queuedAt;
  final String autoCall;
  final String category;
  CallQueueStatus status;

  CallQueueItem({
    this.callLogName = '',
    required this.doctype,
    required this.docname,
    this.lead = '',
    required this.customerName,
    required this.mobileNo,
    required this.queuedAt,
    this.autoCall = "1",
    this.category = "Hot Leads",
    this.status = CallQueueStatus.pending,
  });

  bool get isCancelled => status == CallQueueStatus.cancelled;
  bool get isPending => status == CallQueueStatus.pending;

  Map<String, dynamic> toMap() {
    return {
      'type': 'NEW_LEAD_CALL',
      'call_log_name': callLogName,
      'doctype': doctype,
      'docname': docname,
      'lead': lead,
      'customer_name': customerName,
      'mobile_no': mobileNo,
      'auto_call': autoCall,
      'category': category,
      'queued_at': queuedAt.toIso8601String(),
      'status': status.name,
    };
  }

  /// Handles both FCM payload format and API (get_pending_calls) format:
  ///   FCM:  { doctype, docname, customer_name, mobile_no }
  ///   API:  { name, reference_doctype, reference_docname, customer_name, mobile_no, creation }
  factory CallQueueItem.fromMap(Map<String, dynamic> data) {
    final doctype = (data['doctype'] ?? data['reference_doctype'] ?? '').toString();
    final docname = (data['docname'] ?? data['reference_docname'] ?? '').toString();

    return CallQueueItem(
      // callLogName: from API 'name', FCM 'call_log_name', or docname when doctype is Call Log
      callLogName: (data['name'] ?? data['call_log_name'] ??
              (doctype == 'Call Log' ? docname : '') ?? '')
          .toString(),
      doctype: doctype,
      docname: docname,
      lead: (data['lead'] ?? data['lead_name'] ?? data['reference_docname'] ?? '').toString(),
      customerName: data['customer_name'] ?? '',
      mobileNo: data['mobile_no'] ?? '',
      queuedAt: _parseDateTime(data),
      autoCall: data['auto_call'] ?? '1',
      category: _resolveCategory(data, doctype),
      status: data['status'] == 'cancelled'
          ? CallQueueStatus.cancelled
          : CallQueueStatus.pending,
    );
  }

  static DateTime _parseDateTime(Map<String, dynamic> data) {
    for (final key in ['queued_at', 'creation']) {
      final v = data[key]?.toString();
      if (v != null && v.isNotEmpty) {
        final dt = DateTime.tryParse(v);
        if (dt != null) return dt;
      }
    }
    return DateTime.now();
  }

  String get formattedTime => queuedAt.toString().split('.')[0];

  /// Category from payload, else derived from doctype.
  static String _resolveCategory(Map<String, dynamic> data, String doctype) {
    final explicit =
        (data['category'] ?? data['lead_category'] ?? '').toString().trim();
    if (explicit.isNotEmpty) return explicit;
    switch (doctype) {
      case 'Lead':
        return 'Hot Leads';
      case 'Opportunity':
        return 'Followup Leads';
      case 'Sales Order':
        return 'Order Followups';
      default:
        return 'B2B Followups';
    }
  }
}

class CallQueue {
  final List<CallQueueItem> _queue = [];

  void add(Map<String, dynamic> callData) {
    final item = CallQueueItem.fromMap(callData);
    _queue.add(item);
  }

  void addItem(CallQueueItem item) {
    _queue.add(item);
  }

  CallQueueItem? removeFirst() {
    if (_queue.isNotEmpty) {
      return _queue.removeAt(0);
    }
    return null;
  }

  void remove(int index) {
    if (index >= 0 && index < _queue.length) {
      _queue.removeAt(index);
    }
  }

  /// Moves a call to the end of the queue (e.g. after cancel —
  /// customer not ready, so the team calls the next one first).
  void moveToEnd(int index) {
    if (index >= 0 && index < _queue.length) {
      final item = _queue.removeAt(index);
      _queue.add(item);
    }
  }

  /// Returns true if a call for the same document + mobile number
  /// is already sitting in the queue (any status).
  bool containsCall(String docname, String mobileNo) {
    return _queue.any(
      (item) => item.docname == docname && item.mobileNo == mobileNo,
    );
  }

  CallQueueItem? get(int index) {
    if (index >= 0 && index < _queue.length) {
      return _queue[index];
    }
    return null;
  }

  List<CallQueueItem> getAll() => List.from(_queue);

  int get length => _queue.length;

  bool get isEmpty => _queue.isEmpty;

  bool get isNotEmpty => _queue.isNotEmpty;

  /// Marks a call as cancelled but keeps it in the same position
  void markCancelled(int index) {
    if (index >= 0 && index < _queue.length) {
      _queue[index].status = CallQueueStatus.cancelled;
    }
  }

  /// Restores a cancelled call back to pending
  void restorePending(int index) {
    if (index >= 0 && index < _queue.length) {
      _queue[index].status = CallQueueStatus.pending;
    }
  }

  int get pendingCount => _queue.where((i) => i.isPending).length;

  void reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _queue.length) return;
    if (newIndex < 0 || newIndex > _queue.length) return;
    if (newIndex > oldIndex) newIndex--;
    final item = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, item);
  }

  void clear() {
    _queue.clear();
  }

  void clearAll() {
    _queue.clear();
  }
}
