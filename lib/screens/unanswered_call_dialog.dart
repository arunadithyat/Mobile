import 'package:flutter/material.dart';

import '../api/call_log_api.dart';
import '../api/lead_api.dart';

class UnansweredCallDialog extends StatefulWidget {
  final String leadName;
  final String opportunityName;
  final String customerName;
  final String mobileNo;

  bool get isOpportunity => opportunityName.isNotEmpty && leadName.isEmpty;

  const UnansweredCallDialog({
    super.key,
    this.leadName = '',
    this.opportunityName = '',
    required this.customerName,
    required this.mobileNo,
  });

  @override
  State<UnansweredCallDialog> createState() => _UnansweredCallDialogState();
}

class _UnansweredCallDialogState extends State<UnansweredCallDialog> {
  String _status = 'RNR';
  String _rnrReason = 'Ringing No Response';
  String _junkReason = '';
  DateTime? _followUpDate;
  final _commentsController = TextEditingController();
  bool _isSubmitting = false;
  bool _loading = true;

  List<String> get _statusOptions => widget.isOpportunity ? ['RNR'] : ['RNR', 'Junk'];

  static const List<Map<String, dynamic>> _rnrReasons = [
    {'label': 'Ringing No Response', 'icon': Icons.phone_missed},
    {'label': 'Switched Off', 'icon': Icons.power_off},
    {'label': 'Wrong Number', 'icon': Icons.error_outline},
    {'label': 'Not Reachable', 'icon': Icons.signal_cellular_off},
    {'label': 'Busy', 'icon': Icons.phone_locked},
  ];

  List<String> _junkReasonOptions = [];

  @override
  void initState() {
    super.initState();
    _fetchOptions();
  }

  Future<void> _fetchOptions() async {
    final options = await LeadApi.getFieldOptions();
    if (!mounted) return;
    setState(() {
      _junkReasonOptions = options['custom_reason_for_junk'] ?? [];
      if (_junkReasonOptions.isNotEmpty) _junkReason = _junkReasonOptions.first;
      _loading = false;
    });
  }

  Future<void> _pickFollowUpDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _followUpDate = picked);
  }

  Future<void> _submit() async {
    // Validate follow-up date for RNR
    if (_status == 'RNR' && _followUpDate == null) {
      _showSnack("Follow-up date is required for RNR");
      return;
    }

    // Validate junk reason
    if (_status == 'Junk' && _junkReason.isEmpty) {
      _showSnack("Please select a reason for Junk");
      return;
    }

    // Validate comments (mandatory)
    final comments = _commentsController.text.trim();
    if (comments.isEmpty) {
      _showSnack("Comments are mandatory");
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final fullComment = _status == 'RNR'
          ? '[$_rnrReason] $comments'
          : '[Junk - $_junkReason] $comments';

      Map<String, dynamic> result;
      if (widget.isOpportunity) {
        result = await CallLogApi.updateOpportunityRnr(
          opportunityName: widget.opportunityName,
          status: _status,
          followUpDate: _status == 'RNR'
              ? _followUpDate!.toIso8601String().split('T')[0]
              : DateTime.now().toIso8601String().split('T')[0],
          comments: fullComment,
        );
      } else {
        result = await CallLogApi.updateLeadRnr(
          leadName: widget.leadName,
          status: _status,
          followUpDate: _status == 'RNR'
              ? _followUpDate!.toIso8601String().split('T')[0]
              : DateTime.now().toIso8601String().split('T')[0],
          comments: fullComment,
          junkReason: _status == 'Junk' ? _junkReason : '',
        );
      }

      if (!mounted) return;

      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("✅ ${widget.customerName} marked as $_status"),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, {'status': 'updated', 'lead_status': _status});
      } else {
        _showSnack("❌ ${result['message']}", Colors.red);
      }
    } catch (e) {
      debugPrint('[RNR_UPDATE] Error: $e');
      if (mounted) _showSnack("❌ Error: $e", Colors.red);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSnack(String msg, [Color? bg]) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: bg),
    );
  }

  @override
  void dispose() {
    _commentsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              const Icon(Icons.phone_missed, size: 36, color: Colors.red),
              const SizedBox(height: 8),
              const Text("Call Not Connected",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text("${widget.customerName} · ${widget.mobileNo}",
                  style: TextStyle(fontSize: 13, color: Colors.grey[600])),
              const SizedBox(height: 20),

              // Status: RNR / Junk
              const Align(
                alignment: Alignment.centerLeft,
                child: Text("Status",
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 8),
              Row(
                children: _statusOptions.map((s) {
                  final selected = _status == s;
                  final color = s == 'RNR' ? Colors.orange : Colors.red;
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                          right: s == 'RNR' ? 6 : 0,
                          left: s == 'Junk' ? 6 : 0),
                      child: InkWell(
                        onTap: () => setState(() => _status = s),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: selected
                                ? color.withValues(alpha: 0.1)
                                : null,
                            border: Border.all(
                              color: selected ? color : Colors.grey.shade300,
                              width: selected ? 2 : 1,
                            ),
                          ),
                          child: Center(
                            child: Text(s,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: selected ? color : Colors.grey[700],
                                )),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // RNR reasons (only when RNR selected)
              if (_status == 'RNR') ...[
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text("Reason",
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _rnrReasons.map((r) {
                    final label = r['label'] as String;
                    final selected = _rnrReason == label;
                    return InkWell(
                      onTap: () => setState(() => _rnrReason = label),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          color: selected
                              ? Colors.orange.withValues(alpha: 0.1)
                              : null,
                          border: Border.all(
                            color:
                                selected ? Colors.orange : Colors.grey.shade300,
                            width: selected ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(r['icon'] as IconData,
                                size: 16,
                                color:
                                    selected ? Colors.orange : Colors.grey),
                            const SizedBox(width: 6),
                            Text(label,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  color: selected
                                      ? Colors.orange.shade800
                                      : Colors.grey[700],
                                )),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // Follow-up date (mandatory for RNR)
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text("Next Follow-up Date *",
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: _pickFollowUpDate,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today,
                            size: 18, color: Colors.blue),
                        const SizedBox(width: 10),
                        Text(
                          _followUpDate != null
                              ? "${_followUpDate!.day.toString().padLeft(2, '0')}-${_followUpDate!.month.toString().padLeft(2, '0')}-${_followUpDate!.year}"
                              : "Select date",
                          style: TextStyle(
                            fontSize: 14,
                            color: _followUpDate != null
                                ? Colors.black87
                                : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Junk reason (only when Junk selected)
              if (_status == 'Junk') ...[
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text("Reason for Junk *",
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 8),
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else
                  DropdownButtonFormField<String>(
                    value: _junkReason.isEmpty ? null : _junkReason,
                    isExpanded: true,
                    hint: const Text("Select reason"),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    items: _junkReasonOptions
                        .map((o) => DropdownMenuItem(
                            value: o,
                            child:
                                Text(o, style: const TextStyle(fontSize: 14))))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _junkReason = v);
                    },
                  ),
                const SizedBox(height: 16),
              ],

              // Comments (mandatory)
              const Align(
                alignment: Alignment.centerLeft,
                child: Text("Comments *",
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _commentsController,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: "Add a note... (required)",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Submit
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A73E8),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text("Submit",
                          style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
