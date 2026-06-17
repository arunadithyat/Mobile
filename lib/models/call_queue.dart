enum CallQueueStatus { pending, cancelled }

class CallQueueItem {
  final String callLogName;
  final String doctype;
  final String docname;
  final String lead;         // e.g. CRM-LEAD-2026-14403 (empty if opportunity)
  final String opportunity;  // e.g. CRM-OPP-2026-004 (empty if lead)
  final String customerName;
  final String mobileNo;
  final String productEnquired; // custom_product_enquired
  final DateTime queuedAt;
  final String autoCall;
  final String category;
  CallQueueStatus status;

  CallQueueItem({
    this.callLogName = '',
    required this.doctype,
    required this.docname,
    this.lead = '',
    this.opportunity = '',
    required this.customerName,
    required this.mobileNo,
    this.productEnquired = '',
    required this.queuedAt,
    this.autoCall = "1",
    this.category = "Hot Leads",
    this.status = CallQueueStatus.pending,
  });

  bool get isCancelled => status == CallQueueStatus.cancelled;
  bool get isPending => status == CallQueueStatus.pending;

  /// True if this is a Lead reference
  bool get isLead => lead.isNotEmpty;

  /// True if this is an Opportunity reference
  bool get isOpportunity => opportunity.isNotEmpty && lead.isEmpty;

  /// The reference document name (Lead or Opportunity)
  String get referenceName => isOpportunity ? opportunity : lead;

  /// The reference doctype name
  String get referenceDoctype => isOpportunity ? 'Opportunity' : 'Lead';

  Map<String, dynamic> toMap() {
    return {
      'type': 'NEW_LEAD_CALL',
      'call_log_name': callLogName,
      'doctype': doctype,
      'docname': docname,
      'lead': lead,
      'opportunity': opportunity,
      'customer_name': customerName,
      'mobile_no': mobileNo,
      'product_enquired': productEnquired,
      'auto_call': autoCall,
      'category': category,
      'queued_at': queuedAt.toIso8601String(),
      'status': status.name,
    };
  }

  factory CallQueueItem.fromMap(Map<String, dynamic> data) {
    final doctype = (data['doctype'] ?? data['reference_doctype'] ?? '').toString();
    final docname = (data['docname'] ?? data['reference_docname'] ?? '').toString();

    return CallQueueItem(
      callLogName: (data['name'] ?? data['call_log_name'] ??
              (doctype == 'Call Log' ? docname : '') ?? '')
          .toString(),
      doctype: doctype,
      docname: docname,
      lead: (data['lead'] ?? data['lead_name'] ?? '').toString(),
      opportunity: (data['opportunity'] ?? data['opportunity_name'] ?? '').toString(),
      customerName: data['customer_name'] ?? '',
      mobileNo: data['mobile_no'] ?? '',
      productEnquired: (data['product_enquired'] ?? data['custom_product_enquired'] ?? '').toString(),
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

  static String _resolveCategory(Map<String, dynamic> data, String doctype) {
    final explicit =
        (data['category'] ?? data['lead_category'] ?? '').toString().trim();
    if (explicit.isNotEmpty) return explicit;
    // Check reference fields for Call Log items
    if ((data['opportunity'] ?? data['opportunity_name'] ?? '').toString().isNotEmpty) {
      return 'Order Followups';
    }
    if ((data['lead'] ?? data['lead_name'] ?? '').toString().isNotEmpty) {
      return 'Hot Leads';
    }
    switch (doctype) {
      case 'Lead':
        return 'Hot Leads';
      case 'Opportunity':
        return 'Followup Leads';
      case 'Sales Order':
        return 'Order Followups';
      default:
        return 'Hot Leads';
    }
  }
}

class CallQueue {
  final List<CallQueueItem> _queue = [];

  void add(Map<String, dynamic> callData) {
    final item = CallQueueItem.fromMap(callData);
    _queue.add(item);
  }

  void addItem(CallQueueItem item) { _queue.add(item); }

  CallQueueItem? removeFirst() {
    if (_queue.isNotEmpty) return _queue.removeAt(0);
    return null;
  }

  void remove(int index) {
    if (index >= 0 && index < _queue.length) _queue.removeAt(index);
  }

  void moveToEnd(int index) {
    if (index >= 0 && index < _queue.length) {
      final item = _queue.removeAt(index);
      _queue.add(item);
    }
  }

  bool containsCall(String docname, String mobileNo) {
    return _queue.any((item) => item.docname == docname && item.mobileNo == mobileNo);
  }

  CallQueueItem? get(int index) {
    if (index >= 0 && index < _queue.length) return _queue[index];
    return null;
  }

  List<CallQueueItem> getAll() => List.from(_queue);
  int get length => _queue.length;
  bool get isEmpty => _queue.isEmpty;
  bool get isNotEmpty => _queue.isNotEmpty;

  void markCancelled(int index) {
    if (index >= 0 && index < _queue.length) _queue[index].status = CallQueueStatus.cancelled;
  }

  void restorePending(int index) {
    if (index >= 0 && index < _queue.length) _queue[index].status = CallQueueStatus.pending;
  }

  int get pendingCount => _queue.where((i) => i.isPending).length;

  void reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _queue.length) return;
    if (newIndex < 0 || newIndex > _queue.length) return;
    if (newIndex > oldIndex) newIndex--;
    final item = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, item);
  }

  void clear() { _queue.clear(); }
  void clearAll() { _queue.clear(); }
}
