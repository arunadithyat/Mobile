import 'package:flutter/material.dart';

import '../api/call_log_api.dart';

class UnansweredCallDialog extends StatefulWidget {
  final String leadName; // e.g. CRM-LEAD-2026-14403
  final String customerName;
  final String mobileNo;

  const UnansweredCallDialog({
    super.key,
    required this.leadName,
    required this.customerName,
    required this.mobileNo,
  });

  @override
  State<UnansweredCallDialog> createState() => _UnansweredCallDialogState();
}

class _UnansweredCallDialogState extends State<UnansweredCallDialog> {
  String _selectedStatus = 'RNR';
  DateTime? _followUpDate;
  bool _isSubmitting = false;

  static const List<Map<String, dynamic>> _statusOptions = [
    {'label': 'Ring No Response', 'value': 'RNR', 'icon': Icons.phone_missed, 'color': Colors.orange},
    {'label': 'Busy', 'value': 'Busy', 'icon': Icons.phone_locked, 'color': Colors.red},
    {'label': 'Switched Off', 'value': 'Switched Off', 'icon': Icons.power_off, 'color': Colors.grey},
    {'label': 'Wrong Number', 'value': 'Wrong Number', 'icon': Icons.error_outline, 'color': Colors.red},
    {'label': 'Call Back Later', 'value': 'Call Back Later', 'icon': Icons.schedule, 'color': Colors.blue},
  ];

  Future<void> _pickFollowUpDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _followUpDate = picked);
    }
  }

  Future<void> _submit() async {
    if (_followUpDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a follow-up date")),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final result = await CallLogApi.updateLeadRnr(
        leadName: widget.leadName,
        status: _selectedStatus,
        followUpDate: _followUpDate!.toIso8601String().split('T')[0],
      );

      if (!mounted) return;

      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("✅ ${widget.customerName} marked as $_selectedStatus"),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, {'status': 'updated', 'lead_status': _selectedStatus});
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("❌ Failed to update: ${result['message']}"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint('[RNR_UPDATE] Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            const Icon(Icons.phone_missed, size: 40, color: Colors.red),
            const SizedBox(height: 10),
            const Text("Call Not Connected",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(widget.customerName,
                style: TextStyle(fontSize: 14, color: Colors.grey[600])),
            Text(widget.mobileNo,
                style: TextStyle(fontSize: 13, color: Colors.grey[500])),
            const SizedBox(height: 20),

            // Status options
            const Align(
              alignment: Alignment.centerLeft,
              child: Text("What happened?",
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 8),
            ...(_statusOptions.map((opt) {
              final isSelected = _selectedStatus == opt['value'];
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: InkWell(
                  onTap: () => setState(() => _selectedStatus = opt['value']),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? (opt['color'] as Color)
                            : Colors.grey.shade300,
                        width: isSelected ? 2 : 1,
                      ),
                      color: isSelected
                          ? (opt['color'] as Color).withValues(alpha: 0.08)
                          : null,
                    ),
                    child: Row(
                      children: [
                        Icon(opt['icon'] as IconData,
                            size: 20, color: opt['color'] as Color),
                        const SizedBox(width: 10),
                        Text(opt['label'] as String,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight:
                                  isSelected ? FontWeight.w600 : FontWeight.normal,
                              color: isSelected
                                  ? opt['color'] as Color
                                  : Colors.black87,
                            )),
                        const Spacer(),
                        if (isSelected)
                          Icon(Icons.check_circle,
                              size: 20, color: opt['color'] as Color),
                      ],
                    ),
                  ),
                ),
              );
            })),
            const SizedBox(height: 14),

            // Follow-up date picker
            const Align(
              alignment: Alignment.centerLeft,
              child: Text("Next Follow-up Date *",
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: _pickFollowUpDate,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today, size: 18, color: Colors.blue),
                    const SizedBox(width: 10),
                    Text(
                      _followUpDate != null
                          ? "${_followUpDate!.day.toString().padLeft(2, '0')}-${_followUpDate!.month.toString().padLeft(2, '0')}-${_followUpDate!.year}"
                          : "Select date",
                      style: TextStyle(
                        fontSize: 14,
                        color: _followUpDate != null ? Colors.black87 : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSubmitting
                        ? null
                        : () => Navigator.pop(context, {'status': 'skipped'}),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text("Skip"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A73E8),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text("Submit"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
