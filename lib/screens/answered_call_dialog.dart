import 'package:flutter/material.dart';

import '../api/call_log_api.dart';
import '../api/lead_api.dart';
import '../services/auto_dialer.dart';

class AnsweredCallDialog extends StatefulWidget {
  final String leadName;       // CRM-LEAD-xxx or empty
  final String opportunityName; // CRM-OPP-xxx or empty
  final String callLogName;
  final String customerName;
  final String mobileNo;
  final String doctype;
  final String docname;
  final Duration callDuration;
  final DateTime initiatedTime;
  final String callStatus;
  final bool attended;
  final String dataSource;
  final bool permissionGranted;
  final int retrievedAttempt;

  const AnsweredCallDialog({
    super.key,
    this.leadName = '',
    this.opportunityName = '',
    required this.callLogName,
    required this.customerName,
    required this.mobileNo,
    required this.doctype,
    required this.docname,
    required this.callDuration,
    required this.initiatedTime,
    this.callStatus = 'Connected',
    this.attended = true,
    this.dataSource = 'unknown',
    this.permissionGranted = false,
    this.retrievedAttempt = -1,
  });

  bool get isOpportunity => opportunityName.isNotEmpty && leadName.isEmpty;
  String get referenceName => isOpportunity ? opportunityName : leadName;

  @override
  State<AnsweredCallDialog> createState() => _AnsweredCallDialogState();
}

class _AnsweredCallDialogState extends State<AnsweredCallDialog> {
  bool _loading = true;
  bool _isSubmitting = false;

  // Shared fields
  String _status = '';
  DateTime? _followUpDate;
  final _commentsController = TextEditingController();

  // Lead-specific fields
  String _customerCategory = '';
  String _customerType = '';
  String _district = '';
  String _cityTown = '';

  // Opportunity-specific fields
  String _opportunityAmount = '';
  final _amountController = TextEditingController();

  // Dropdown options
  Map<String, List<String>> _options = {};

  // Opportunity statuses that require mandatory follow-up date
  static const _oppDateMandatoryStatuses = [
    'Demo', 'Quotation', 'Prospect', 'Pipeline'
  ];

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    if (widget.isOpportunity) {
      final results = await Future.wait([
        OpportunityApi.getFieldOptions(),
        OpportunityApi.getCurrentValues(widget.opportunityName),
      ]);
      final options = results[0] as Map<String, List<String>>;
      final values = results[1] as Map<String, dynamic>;

      if (!mounted) return;
      setState(() {
        _options = options;
        _status = (values['status'] ?? '').toString();
        _opportunityAmount = (values['opportunity_amount'] ?? '').toString();
        _amountController.text = _opportunityAmount;
        final followUp = (values['custom_next_followup_date1'] ?? '').toString();
        if (followUp.isNotEmpty) _followUpDate = DateTime.tryParse(followUp);
        _loading = false;
      });
    } else {
      final results = await Future.wait([
        LeadApi.getFieldOptions(),
        LeadApi.getLeadCurrentValues(widget.leadName),
      ]);
      final options = results[0] as Map<String, List<String>>;
      final values = results[1] as Map<String, dynamic>;

      if (!mounted) return;
      setState(() {
        _options = options;
        _status = (values['status'] ?? '').toString();
        _customerCategory = (values['custom_customer_category'] ?? '').toString();
        _customerType = (values['custom_customer_type'] ?? '').toString();
        _district = (values['custom_district'] ?? '').toString();
        _cityTown = (values['custom_citytown'] ?? '').toString();
        final followUp = (values['custom_next_followup_date1'] ?? '').toString();
        if (followUp.isNotEmpty) _followUpDate = DateTime.tryParse(followUp);
        _loading = false;
      });
    }
  }

  List<String> _getOptions(String key) => _options[key] ?? [];

  Future<void> _pickFollowUpDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _followUpDate ?? DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _followUpDate = picked);
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    if (m == 0) return '${s}s';
    return '$m:${s.toString().padLeft(2, '0')} min';
  }

  bool get _isFollowUpMandatory {
    if (!widget.isOpportunity) return false;
    return _oppDateMandatoryStatuses.contains(_status);
  }

  Future<void> _submit() async {
    if (_status.isEmpty) {
      _showSnack("Please select a status");
      return;
    }
    if (_isFollowUpMandatory && _followUpDate == null) {
      _showSnack("Follow-up date is required for $_status");
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final fromNumber = await AutoDialer.getOwnNumber();

      // 1. Update Call Log doctype
      await CallLogDoctypeApi.updateCallLog(
        callLogName: widget.callLogName,
        mobileNo: widget.mobileNo,
        fromNumber: fromNumber,
        startTime: widget.initiatedTime,
        durationSeconds: widget.callDuration.inSeconds,
        attended: widget.attended,
      );

      // 2. Update Error Log
      await CallLogApi.updateCallLog(
        doctype: widget.doctype,
        docname: widget.docname,
        customerName: widget.customerName,
        mobileNo: widget.mobileNo,
        callDuration: widget.callDuration.inSeconds,
        initiatedTime: widget.initiatedTime,
        callStatus: widget.callStatus,
        disconnectedStatus: 'remote_or_normal_hangup',
        notes: _commentsController.text.trim(),
        attended: widget.attended,
        fromNumber: fromNumber,
        dataSource: widget.dataSource,
        permissionGranted: widget.permissionGranted,
        retrievedAttempt: widget.retrievedAttempt,
      );

      // 3. Update Lead or Opportunity
      Map<String, dynamic> result;
      if (widget.isOpportunity) {
        final fields = <String, dynamic>{
          'status': _status,
          'opportunity_amount': _amountController.text.trim(),
        };
        if (_followUpDate != null) {
          fields['custom_next_followup_date1'] =
              _followUpDate!.toIso8601String().split('T')[0];
        }
        final comments = _commentsController.text.trim();
        if (comments.isNotEmpty) fields['comments'] = comments;

        result = await OpportunityApi.updateOpportunity(
          oppName: widget.opportunityName,
          fields: fields,
        );
      } else {
        final fields = <String, dynamic>{
          'status': _status,
          'custom_customer_category': _customerCategory,
          'custom_district': _district,
          'custom_citytown': _cityTown,
        };
        if (_customerCategory.isNotEmpty && _customerCategory != 'B2C') {
          fields['custom_customer_type'] = _customerType;
        }
        if (_followUpDate != null) {
          fields['custom_next_followup_date1'] =
              _followUpDate!.toIso8601String().split('T')[0];
        }
        final comments = _commentsController.text.trim();
        if (comments.isNotEmpty) fields['comments'] = comments;

        result = await LeadApi.updateLead(
          leadName: widget.leadName,
          fields: fields,
        );
      }

      if (!mounted) return;

      final docLabel = widget.isOpportunity ? 'Opportunity' : 'Lead';
      if (result['success'] == true) {
        _showSnack("✅ Call logged & $docLabel updated", Colors.green);
      } else {
        _showSnack("⚠️ Call logged but $docLabel update failed", Colors.orange);
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint('[ANSWERED] Error: $e');
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

  Widget _buildDropdown(String label, String fieldKey, String value,
      ValueChanged<String> onChanged, {bool visible = true}) {
    if (!visible) return const SizedBox.shrink();
    final options = _getOptions(fieldKey);
    final safeOptions = [...options];
    if (value.isNotEmpty && !safeOptions.contains(value)) {
      safeOptions.insert(0, value);
    }
    final hasFill = value.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: value.isEmpty ? null : value,
            isExpanded: true,
            hint: Text("Select $label"),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              filled: hasFill,
              fillColor: hasFill ? Colors.green.shade50 : null,
            ),
            items: safeOptions
                .map((o) => DropdownMenuItem(value: o, child: Text(o, style: const TextStyle(fontSize: 14))))
                .toList(),
            onChanged: (v) { if (v != null) onChanged(v); },
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _commentsController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Padding(
          padding: EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [CircularProgressIndicator(), SizedBox(height: 16), Text("Loading data...")],
          ),
        ),
      );
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              const Text("Post Call Update",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(widget.customerName,
                  style: TextStyle(fontSize: 14, color: Colors.grey[600])),
              Text(widget.mobileNo,
                  style: TextStyle(fontSize: 13, color: Colors.grey[500])),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: widget.isOpportunity ? Colors.blue.shade50 : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  widget.isOpportunity ? "Opportunity" : "Lead",
                  style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600,
                    color: widget.isOpportunity ? Colors.blue : Colors.orange.shade800,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Auto-captured
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.timer, size: 18, color: Colors.blue),
                    const SizedBox(width: 8),
                    Text("Duration: ${_formatDuration(widget.callDuration)}",
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.shade100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text("Connected",
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.green)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Status dropdown
              _buildDropdown("Status", "status", _status,
                  (v) => setState(() => _status = v)),

              // --- Lead-specific fields ---
              if (!widget.isOpportunity) ...[
                _buildDropdown("Customer Category", "custom_customer_category",
                    _customerCategory, (v) => setState(() => _customerCategory = v)),
                _buildDropdown("Customer Type", "custom_customer_type",
                    _customerType, (v) => setState(() => _customerType = v),
                    visible: _customerCategory.isNotEmpty && _customerCategory != 'B2C'),
                _buildDropdown("District", "custom_district", _district,
                    (v) => setState(() => _district = v)),
                _buildDropdown("City / Town", "custom_citytown", _cityTown,
                    (v) => setState(() => _cityTown = v)),
              ],

              // --- Opportunity-specific fields ---
              if (widget.isOpportunity) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Opportunity Amount",
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _amountController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          hintText: "Enter amount",
                          prefixText: "₹ ",
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          filled: _amountController.text.isNotEmpty,
                          fillColor: Colors.green.shade50,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Follow-up date
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Next Follow-up Date${_isFollowUpMandatory ? ' *' : ''}",
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: _pickFollowUpDate,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _isFollowUpMandatory && _followUpDate == null
                              ? Colors.red.shade300 : Colors.grey.shade300),
                          color: _followUpDate != null ? Colors.green.shade50 : null,
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
                  ],
                ),
              ),

              // Comments
              const Align(
                alignment: Alignment.centerLeft,
                child: Text("Comments",
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _commentsController,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: "Add notes about the call...",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 18),

              // Submit
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A73E8),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(height: 18, width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text("Submit", style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
