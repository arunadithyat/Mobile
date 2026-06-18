import 'package:flutter/material.dart';
import 'package:lead_calling/services/call_history_storage.dart';

/// History of outgoing calls made through the app.
/// Embedded as a tab — no Scaffold of its own.
class CallHistoryTab extends StatefulWidget {
  const CallHistoryTab({super.key});

  @override
  State<CallHistoryTab> createState() => _CallHistoryTabState();
}

class _CallHistoryTabState extends State<CallHistoryTab> {
  List<CallHistoryEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await CallHistoryStorage.getAll();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'connected':
        return Colors.green;
      case 'customer called back':
        return Colors.blue;
      case 'missed':
      case 'missed call':
        return Colors.orange;
      case 'not answered':
      case 'not connected':
        return Colors.red;
      case 'rejected':
        return Colors.red.shade800;
      case 'cancelled':
        return Colors.grey;
      default:
        return Colors.blueGrey;
    }
  }

  bool _isIncoming(String status) {
    return ['customer called back', 'missed call', 'rejected']
        .contains(status.toLowerCase());
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) return '-';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m == 0) return '${s}s';
    return '${m}m ${s}s';
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();
    final isToday = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    if (isToday) return '$hh:$mm';
    return '${local.day.toString().padLeft(2, '0')}-${local.month.toString().padLeft(2, '0')} $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_entries.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: 400,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.history, size: 70, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text(
                      'No calls made yet',
                      style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: _entries.length,
        separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey[200]),
        itemBuilder: (context, index) {
          final e = _entries[index];
          final color = _statusColor(e.status);
          return ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 18,
              backgroundColor: color.withValues(alpha: 0.12),
              child: Icon(
                _isIncoming(e.status) ? Icons.call_received : Icons.call_made,
                size: 18,
                color: color,
              ),
            ),
            title: Text(
              e.customerName.isEmpty ? e.mobileNo : e.customerName,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            subtitle: Text(
              '${e.mobileNo}  •  ${_formatTime(e.calledAt)}'
              '${e.durationSeconds > 0 ? '  •  ${_formatDuration(e.durationSeconds)}' : ''}',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                e.status,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
