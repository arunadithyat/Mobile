enum CallQueueStatus { pending, cancelled }

class CallQueueItem {
  final String doctype;
  final String docname;
  final String customerName;
  final String mobileNo;
  final DateTime queuedAt;
  final String autoCall;
  CallQueueStatus status;

  CallQueueItem({
    required this.doctype,
    required this.docname,
    required this.customerName,
    required this.mobileNo,
    required this.queuedAt,
    this.autoCall = "1",
    this.status = CallQueueStatus.pending,
  });

  bool get isCancelled => status == CallQueueStatus.cancelled;
  bool get isPending => status == CallQueueStatus.pending;

  Map<String, dynamic> toMap() {
    return {
      'type': 'NEW_LEAD_CALL',
      'doctype': doctype,
      'docname': docname,
      'customer_name': customerName,
      'mobile_no': mobileNo,
      'auto_call': autoCall,
      'queued_at': queuedAt.toIso8601String(),
      'status': status.name,
    };
  }

  factory CallQueueItem.fromMap(Map<String, dynamic> data) {
    return CallQueueItem(
      doctype: data['doctype'] ?? '',
      docname: data['docname'] ?? data['name'] ?? '',
      customerName: data['customer_name'] ?? '',
      mobileNo: data['mobile_no'] ?? '',
      queuedAt: data['queued_at'] != null
          ? DateTime.parse(data['queued_at'])
          : DateTime.now(),
      autoCall: data['auto_call'] ?? '1',
      status: data['status'] == 'cancelled'
          ? CallQueueStatus.cancelled
          : CallQueueStatus.pending,
    );
  }

  String get formattedTime => queuedAt.toString().split('.')[0];
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
