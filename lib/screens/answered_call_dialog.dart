import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/call_log_api.dart';
import '../api/lead_api.dart';
import '../services/auto_dialer.dart';

class AnsweredCallDialog extends StatefulWidget {
  final String leadName;       // CRM-LEAD-xxx or empty
  final String opportunityName; // CRM-OPP-xxx or empty
  final String callLogName;
  final String callOutcome;
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
    this.callOutcome = '',
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
  String _errorMessage = '';

  // Shared fields
  String _status = '';
  DateTime? _followUpDate;
  final _commentsController = TextEditingController();
  final _areaController = TextEditingController();
  String _junkReason = '';
  List<String> _junkReasonOptions = [];
  String _notInterestedReason = '';
  List<String> _notInterestedReasonOptions = [];

  // Lead-specific fields
  String _customerCategory = '';
  String _customerType = '';
  String _district = '';
  String _cityTown = '';

  // Opportunity-specific fields
  String _opportunityAmount = '';
  final _amountController = TextEditingController();
  DateTime? _expectedClosing;
  String _reasonForNotInterested = '';
  List<String> _notInterestedReasons = [];

  // Dropdown options
  Map<String, List<String>> _options = {};

  // Opportunity statuses that require mandatory follow-up date
  static const _oppDateMandatoryStatuses = [
    'Demo', 'Quotation', 'Prospect', 'Pipeline'
  ];

  bool get _isJunk => !widget.isOpportunity && _status == 'Junk';
  bool get _isNotInterestedLead => !widget.isOpportunity && _status == 'Not Interested';

  bool get _isExpectedClosingMandatory {
    return widget.isOpportunity &&
        (_status == 'Prospect' || _status == 'Pipeline');
  }

  bool get _isNotInterested {
    return widget.isOpportunity && _status == 'Not Interested';
  }

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
        _notInterestedReasons = options['custom_reason_for_not_interested'] ?? [];
        _status = (values['status'] ?? '').toString();
        _opportunityAmount = (values['opportunity_amount'] ?? '').toString();
        _amountController.text = _opportunityAmount;
        final followUp = (values['custom_next_followup_date1'] ?? '').toString();
        if (followUp.isNotEmpty) _followUpDate = DateTime.tryParse(followUp);
        final expClose = (values['expected_closing'] ?? '').toString();
        if (expClose.isNotEmpty) _expectedClosing = DateTime.tryParse(expClose);
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
        _junkReasonOptions = options['custom_reason_for_junk'] ?? [];
        _notInterestedReasonOptions = options['custom_reason_for_not_interested'] ?? [];
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
    if (widget.isOpportunity) {
      return _status != 'Not Interested';
    }
    // Lead: mandatory for Followup status
    return _status == 'Followup';
  }

  Future<void> _submit() async {
    if (_status.isEmpty) {
      _showSnack("Please select a status");
      return;
    }
    if (_isFollowUpMandatory && _followUpDate == null) {
      _showSnack("Follow-up date is required");
      return;
    }

    if (_isExpectedClosingMandatory && _expectedClosing == null) {
      _showSnack("Expected closing date is required for $_status");
      return;
    }

    if (_isNotInterested && _reasonForNotInterested.isEmpty) {
      _showSnack("Reason for Not Interested is required");
      return;
    }

    if (widget.isOpportunity && !_isNotInterested && _amountController.text.trim().isEmpty) {
      _showSnack("Opportunity amount is required");
      return;
    }

    // Lead mandatory field checks (skip for Junk)
    if (!widget.isOpportunity && !_isJunk && !_isNotInterestedLead) {
      if (_customerCategory.isNotEmpty && _customerCategory != 'B2C' && _customerType.isEmpty) {
        _showSnack("Customer Type is mandatory"); return;
      }
      if (_district.isEmpty) { _showSnack("District is mandatory"); return; }
      if (_areaController.text.trim().isEmpty) { _showSnack("Area is mandatory"); return; }
      if (_cityTown.isEmpty) { _showSnack("City / Town is mandatory"); return; }
    }

    if (_isJunk && _junkReason.isEmpty) {
      _showSnack("Reason for Junk is mandatory"); return;
    }
    if (_isNotInterestedLead && _notInterestedReason.isEmpty) {
      _showSnack("Reason for Not Interested is mandatory"); return;
    }

    final comments = _commentsController.text.trim();
    if ((_isNotInterestedLead || (!_isJunk && !_isNotInterestedLead)) && comments.isEmpty) {
      _showSnack("Comments are mandatory"); return;
    }

    setState(() => _isSubmitting = true);

    try {
      final fromNumber = await AutoDialer.getOwnNumber();

      // 1. Update Call Log doctype
      final callLogResult = await CallLogDoctypeApi.updateCallLog(
        callLogName: widget.callLogName,
        mobileNo: widget.mobileNo,
        fromNumber: fromNumber,
        startTime: widget.initiatedTime,
        durationSeconds: widget.callDuration.inSeconds,
        attended: widget.attended,
        summary: widget.callOutcome,
      );
      if (callLogResult['success'] != true) {
        debugPrint('[ANSWERED] ⚠️ Call Log update failed: ${callLogResult['message']}');
        debugPrint('[ANSWERED] callLogName: ${widget.callLogName}');
      }

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
        };
        if (!_isNotInterested) {
          fields['opportunity_amount'] = _amountController.text.trim();
          if (_areaController.text.trim().isNotEmpty) {
            fields['city'] = _areaController.text.trim();
          }
        }
        if (_followUpDate != null && !_isNotInterested) {
          fields['custom_next_followup_date1'] =
              _followUpDate!.toIso8601String().split('T')[0];
        }
        if (_expectedClosing != null) {
          fields['expected_closing'] =
              _expectedClosing!.toIso8601String().split('T')[0];
        }
        if (_isNotInterested && _reasonForNotInterested.isNotEmpty) {
          fields['custom_reason_for_not_interested'] = _reasonForNotInterested;
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
        if (_areaController.text.trim().isNotEmpty) {
          fields['custom_area'] = _areaController.text.trim();
        }
        if (_isJunk && _junkReason.isNotEmpty) {
          fields['custom_reason_for_junk'] = _junkReason;
        }
        if (_isNotInterestedLead && _notInterestedReason.isNotEmpty) {
          fields['custom_reason_for_not_interested'] = _notInterestedReason;
        }
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

        // Create Opportunity when status = "Opportunity"
        if (_status == 'Opportunity' && result['success'] == true) {
          final oppResult = await LeadApi.createOpportunity(
            leadName: widget.leadName,
            fields: {
              'customer_name': widget.customerName,
              'mobile_no': widget.mobileNo,
              'custom_district': _district,
              'custom_area': _areaController.text.trim(),
              'custom_citytown': _cityTown,
              'comments': comments,
            },
          );
          debugPrint('[ANSWERED] Create Opportunity result: $oppResult');
        }
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
    if (bg == Colors.green) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: bg),
      );
    } else {
      setState(() => _errorMessage = msg);
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _errorMessage = '');
      });
    }
  }

  Widget _buildDropdown(String label, String fieldKey, String value,
      ValueChanged<String> onChanged, {bool visible = true, bool mandatory = false}) {
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
          Text("$label${mandatory ? ' *' : ''}",
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          InkWell(
            onTap: () => _showSearchableDropdown(label, safeOptions, value, onChanged),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade400),
                color: hasFill ? Colors.green.shade50 : null,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      value.isEmpty ? "Select $label" : value,
                      style: TextStyle(
                        fontSize: 14,
                        color: value.isEmpty ? Colors.grey : Colors.black87,
                      ),
                    ),
                  ),
                  Icon(Icons.arrow_drop_down, color: Colors.grey[600]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSearchableDropdown(
      String label, List<String> options, String current, ValueChanged<String> onChanged) {
    final searchController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final query = searchController.text.toLowerCase();
            final filtered = query.isEmpty
                ? options
                : options.where((o) => o.toLowerCase().contains(query)).toList();
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.7,
              maxChildSize: 0.9,
              minChildSize: 0.4,
              builder: (_, scrollCtrl) => Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text("Select $label",
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: searchController,
                      autofocus: false,
                      decoration: InputDecoration(
                        hintText: "Search...",
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      onChanged: (_) => setSheetState(() {}),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        controller: scrollCtrl,
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final item = filtered[i];
                          final selected = item == current;
                          return ListTile(
                            title: Text(item,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                                  color: selected ? Colors.blue : Colors.black87,
                                )),
                            trailing: selected ? const Icon(Icons.check, color: Colors.blue, size: 18) : null,
                            onTap: () {
                              onChanged(item);
                              Navigator.pop(ctx);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _commentsController.dispose();
    _areaController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return PopScope(
        canPop: false,
        child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Padding(
          padding: EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [CircularProgressIndicator(), SizedBox(height: 16), Text("Loading data...")],
          ),
        ),
      ));
    }

    return PopScope(
      canPop: false,
      child: Dialog(
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
                  style: TextStyle(fontSize: 16, color: Colors.grey[600])),
              Text(widget.mobileNo,
                  style: TextStyle(fontSize: 15, color: Colors.grey[500])),
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
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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
              const SizedBox(height: 12),

              // Inline error message
              if (_errorMessage.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red.shade700, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_errorMessage,
                            style: TextStyle(color: Colors.red.shade700, fontSize: 13, fontWeight: FontWeight.w500)),
                      ),
                    ],
                  ),
                ),

              // Status dropdown
              _buildDropdown("Status", "status", _status,
                  (v) => setState(() => _status = v)),

              // --- Lead-specific fields ---
              if (!widget.isOpportunity) ...[
                _buildDropdown("Customer Category", "custom_customer_category",
                    _customerCategory, (v) => setState(() => _customerCategory = v)),
                if (!_isJunk && !_isNotInterestedLead) ...[
                  _buildDropdown("Customer Type", "custom_customer_type",
                      _customerType, (v) => setState(() => _customerType = v),
                      visible: _customerCategory.isNotEmpty && _customerCategory != 'B2C',
                      mandatory: true),
                  _buildDropdown("District", "custom_district", _district,
                      (v) => setState(() => _district = v), mandatory: true),
                  _buildDropdown("City / Town", "custom_citytown", _cityTown,
                      (v) => setState(() => _cityTown = v), mandatory: true),
                ],
                if (_isJunk)
                  _buildDropdown("Reason for Junk", "custom_reason_for_junk", _junkReason,
                      (v) => setState(() => _junkReason = v), mandatory: true),
                if (_isNotInterestedLead)
                  _buildDropdown("Reason for Not Interested", "custom_reason_for_not_interested", _notInterestedReason,
                      (v) => setState(() => _notInterestedReason = v), mandatory: true),
              ],

              // --- Opportunity-specific fields ---
              if (widget.isOpportunity && !_isNotInterested) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Opportunity Amount *",
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                        ],
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

              // Area field
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Area${(_isJunk || _isNotInterestedLead) ? '' : ' *'}",
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _areaController,
                      decoration: InputDecoration(
                        hintText: "Enter area",
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        filled: _areaController.text.isNotEmpty,
                        fillColor: Colors.green.shade50,
                      ),
                    ),
                  ],
                ),
              ),

              // Expected Closing Date (Prospect/Pipeline)
              if (_isExpectedClosingMandatory)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Expected Closing Date *",
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _expectedClosing ?? DateTime.now().add(const Duration(days: 30)),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(const Duration(days: 730)),
                          );
                          if (picked != null) setState(() => _expectedClosing = picked);
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _expectedClosing == null ? Colors.red.shade300 : Colors.grey.shade300),
                            color: _expectedClosing != null ? Colors.green.shade50 : null,
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.event, size: 18, color: Colors.purple),
                              const SizedBox(width: 10),
                              Text(
                                _expectedClosing != null
                                    ? "${_expectedClosing!.day.toString().padLeft(2, '0')}-${_expectedClosing!.month.toString().padLeft(2, '0')}-${_expectedClosing!.year}"
                                    : "Select date",
                                style: TextStyle(fontSize: 14, color: _expectedClosing != null ? Colors.black87 : Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Reason for Not Interested
              if (_isNotInterested)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Reason for Not Interested *",
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: _reasonForNotInterested.isEmpty ? null : _reasonForNotInterested,
                        isExpanded: true,
                        hint: const Text("Select reason"),
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        items: _notInterestedReasons
                            .map((o) => DropdownMenuItem(value: o, child: Text(o, style: const TextStyle(fontSize: 14))))
                            .toList(),
                        onChanged: (v) { if (v != null) setState(() => _reasonForNotInterested = v); },
                      ),
                    ],
                  ),
                ),

              // Follow-up date (hidden for Not Interested)
              if (!_isNotInterested && !_isNotInterestedLead && !_isJunk) Padding(
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
              Align(
                alignment: Alignment.centerLeft,
                child: Text("Comments${(_isJunk) ? '' : ' *'}",
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
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
    ));
  }
}
