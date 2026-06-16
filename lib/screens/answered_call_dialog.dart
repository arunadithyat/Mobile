import 'package:flutter/material.dart';

import '../api/call_log_api.dart';
import '../api/lead_api.dart';
import '../services/auto_dialer.dart';

class AnsweredCallDialog extends StatefulWidget {
  final String leadName;
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
    required this.leadName,
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

  @override
  State<AnsweredCallDialog> createState() => _AnsweredCallDialogState();
}

class _AnsweredCallDialogState extends State<AnsweredCallDialog> {
  bool _loading = true;
  bool _isSubmitting = false;

  // Lead field values (pre-populated from API)
  String _status = '';
  String _customerCategory = '';
  String _customerType = '';
  String _district = '';
  String _cityTown = '';
  DateTime? _followUpDate;
  final _commentsController = TextEditingController();

  // Field options (from API response)
  List<String> _statusOptions = [];
  List<String> _categoryOptions = [];
  List<String> _typeOptions = [];
  List<String> _districtOptions = [];
  List<String> _cityOptions = [];

  @override
  void initState() {
    super.initState();
    _fetchLeadData();
  }

  Future<void> _fetchLeadData() async {
    final data = await LeadApi.getLeadValues(widget.leadName);
    if (!mounted) return;

    setState(() {
      // Current values
      _status = (data['status'] ?? '').toString();
      _customerCategory = (data['custom_customer_category'] ?? '').toString();
      _customerType = (data['custom_customer_type'] ?? '').toString();
      _district = (data['custom_district'] ?? '').toString();
      _cityTown = (data['custom_citytown'] ?? '').toString();

      final followUp = data['custom_next_followup_date1']?.toString() ?? '';
      if (followUp.isNotEmpty) _followUpDate = DateTime.tryParse(followUp);

      // Field options from API
      _statusOptions = _toList(data['status_options']);
      _categoryOptions = _toList(data['category_options']);
      _typeOptions = _toList(data['type_options']);
      _districtOptions = _toList(data['district_options']);
      _cityOptions = _toList(data['city_options']);

      // Default status if empty
      if (_status.isEmpty && _statusOptions.isNotEmpty) {
        _status = _statusOptions.first;
      }

      _loading = false;
    });
  }

  List<String> _toList(dynamic value) {
    if (value is List) return value.map((e) => e.toString()).toList();
    return [];
  }

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

  Future<void> _submit() async {
    if (_status.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a status")),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      // 1. Update Call Log doctype (duration, status, times)
      final fromNumber = await AutoDialer.getOwnNumber();
      await CallLogDoctypeApi.updateCallLog(
        callLogName: widget.callLogName,
        mobileNo: widget.mobileNo,
        fromNumber: fromNumber,
        startTime: widget.initiatedTime,
        durationSeconds: widget.callDuration.inSeconds,
        attended: widget.attended,
      );

      // 2. Update Error Log (existing flow)
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

      // 3. Update Lead fields
      final leadFields = <String, dynamic>{
        'status': _status,
        'custom_customer_category': _customerCategory,
        'custom_district': _district,
        'custom_citytown': _cityTown,
      };

      // Only include customer_type if category != B2C
      if (_customerCategory.isNotEmpty && _customerCategory != 'B2C') {
        leadFields['custom_customer_type'] = _customerType;
      }

      if (_followUpDate != null) {
        leadFields['custom_next_followup_date1'] =
            _followUpDate!.toIso8601String().split('T')[0];
      }

      final comments = _commentsController.text.trim();
      if (comments.isNotEmpty) {
        leadFields['comments'] = comments;
      }

      final leadResult = await LeadApi.updateLead(
        leadName: widget.leadName,
        fields: leadFields,
      );

      if (!mounted) return;

      if (leadResult['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✅ Call logged & Lead updated"),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("⚠️ Call logged but Lead update failed: ${leadResult['message']}"),
            backgroundColor: Colors.orange,
          ),
        );
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint('[ANSWERED] Error: $e');
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
  void dispose() {
    _commentsController.dispose();
    super.dispose();
  }

  Widget _buildDropdown(
    String label,
    String value,
    List<String> options,
    ValueChanged<String> onChanged, {
    bool visible = true,
  }) {
    if (!visible) return const SizedBox.shrink();
    // Ensure current value is in options list
    final safeOptions = [...options];
    if (value.isNotEmpty && !safeOptions.contains(value)) {
      safeOptions.insert(0, value);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: value.isEmpty ? null : value,
            isExpanded: true,
            hint: Text("Select $label"),
            decoration: InputDecoration(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              filled: value.isNotEmpty,
              fillColor: value.isNotEmpty ? Colors.green.shade50 : null,
            ),
            items: safeOptions
                .map((o) => DropdownMenuItem(value: o, child: Text(o, style: const TextStyle(fontSize: 14))))
                .toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ],
      ),
    );
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
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text("Loading lead data..."),
            ],
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
              const SizedBox(height: 12),

              // Auto-captured info
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
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.shade100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text("Connected",
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.green)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Dynamic fields
              _buildDropdown("Lead Status", _status, _statusOptions,
                  (v) => setState(() => _status = v)),

              _buildDropdown("Customer Category", _customerCategory,
                  _categoryOptions,
                  (v) => setState(() => _customerCategory = v)),

              _buildDropdown(
                "Customer Type",
                _customerType,
                _typeOptions,
                (v) => setState(() => _customerType = v),
                visible: _customerCategory.isNotEmpty &&
                    _customerCategory != 'B2C',
              ),

              _buildDropdown("District", _district, _districtOptions,
                  (v) => setState(() => _district = v)),

              _buildDropdown("City / Town", _cityTown, _cityOptions,
                  (v) => setState(() => _cityTown = v)),

              // Follow-up date
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Next Follow-up Date",
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: _pickFollowUpDate,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade300),
                          color: _followUpDate != null
                              ? Colors.green.shade50
                              : null,
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
                  ],
                ),
              ),

              // Comments
              const Align(
                alignment: Alignment.centerLeft,
                child: Text("Comments",
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _commentsController,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: "Add notes about the call...",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
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
