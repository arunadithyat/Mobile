import 'package:flutter/material.dart';
import 'package:lead_calling/api/call_log_api.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class CallCompletionDialog extends StatefulWidget {
  final String doctype;
  final String docname;
  final String customerName;
  final String mobileNo;
  final Duration callDuration;
  final DateTime initiatedTime;
  final String? initialCallStatus;
  final String? initialDisconnectedStatus;
  final bool? initialAttended;
  final String dataSource;
  final bool permissionGranted;
  final int retrievedAttempt;

  const CallCompletionDialog({
    super.key,
    required this.doctype,
    required this.docname,
    required this.customerName,
    required this.mobileNo,
    required this.callDuration,
    required this.initiatedTime,
    this.initialCallStatus,
    this.initialDisconnectedStatus,
    this.initialAttended,
    this.dataSource = 'unknown',
    this.permissionGranted = false,
    this.retrievedAttempt = -1,
  });

  @override
  State<CallCompletionDialog> createState() => _CallCompletionDialogState();
}

class _CallCompletionDialogState extends State<CallCompletionDialog> {
  late String _callStatus;
  late bool _attended;
  late String _disconnectedStatus;
  String _notes = "";
  bool _isSubmitting = false;
  late final TextEditingController _disconnectedController;
  late final TextEditingController _notesController;
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  bool _speechAvailable = false;

  @override
  void initState() {
    super.initState();
    _callStatus = widget.initialCallStatus ?? "Connected";
    _attended = widget.initialAttended ?? true;
    _disconnectedStatus =
        widget.initialDisconnectedStatus ?? "remote_or_normal_hangup";
    _disconnectedController = TextEditingController(text: _disconnectedStatus);
    _notesController = TextEditingController();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    _speechAvailable = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          if (mounted) setState(() => _isListening = false);
        }
      },
      onError: (error) {
        debugPrint('[VOICE] Error: $error');
        if (mounted) setState(() => _isListening = false);
      },
    );
    debugPrint('[VOICE] Speech available: $_speechAvailable');
  }

  void _toggleListening() async {
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
    } else {
      if (!_speechAvailable) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Voice input not available on this device")),
        );
        return;
      }
      setState(() => _isListening = true);
      await _speech.listen(
        onResult: (result) {
          setState(() {
            // Append recognized words to existing notes
            final current = _notesController.text;
            if (current.isEmpty) {
              _notesController.text = result.recognizedWords;
            } else {
              _notesController.text = '$current ${result.recognizedWords}';
            }
            _notes = _notesController.text;
            // Move cursor to end
            _notesController.selection = TextSelection.fromPosition(
              TextPosition(offset: _notesController.text.length),
            );
          });
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
        localeId: 'en_IN', // Indian English
      );
    }
  }

  final List<String> _statusOptions = [
    "Connected",
    "Disconnected",
    "Missed",
    "Dropped",
    "Busy",
  ];

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false, // Prevent back button
      child: Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Call Completed",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.customerName,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 20),
                
                // Duration display
                Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.timer, color: Colors.blue),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Call Duration",
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                          Text(
                            _formatDuration(widget.callDuration),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Call Status dropdown
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Call Status",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButton<String>(
                      value: _callStatus,
                      isExpanded: true,
                      items: _statusOptions.map((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          setState(() {
                            _callStatus = newValue;
                          });
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Disconnected Status",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _disconnectedController,
                      onChanged: (value) {
                        _disconnectedStatus = value.trim();
                      },
                      decoration: InputDecoration(
                        hintText: "ex: remote_or_normal_hangup",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Attended checkbox
                CheckboxListTile(
                  value: _attended,
                  onChanged: (bool? value) {
                    setState(() {
                      _attended = value ?? true;
                    });
                  },
                  title: const Text("Customer Attended"),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 15),

                // Notes field with voice input
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Notes (Optional)",
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        GestureDetector(
                          onTap: _toggleListening,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _isListening
                                  ? Colors.red.shade50
                                  : Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _isListening
                                    ? Colors.red.shade300
                                    : Colors.blue.shade300,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _isListening ? Icons.mic : Icons.mic_none,
                                  size: 18,
                                  color: _isListening ? Colors.red : Colors.blue,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _isListening ? "Listening..." : "Voice",
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: _isListening ? Colors.red : Colors.blue,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _notesController,
                      onChanged: (value) {
                        _notes = value;
                      },
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: _isListening
                            ? "Speak now..."
                            : "Add notes or tap Voice to speak...",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: _isListening ? Colors.red : Colors.grey,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: _isListening ? Colors.red : Colors.blue,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 25),

                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isSubmitting
                            ? null
                            : () {
                                Navigator.pop(context);
                              },
                        child: const Text("Cancel"),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submitCallCompletion,
                        child: _isSubmitting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text("Submit"),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _speech.stop();
    _disconnectedController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submitCallCompletion() async {
    setState(() {
      _isSubmitting = true;
    });

    debugPrint("[COMPLETION] Submitting call completion...");

    try {
      // Log call completion to Error Log
      final result = await CallLogApi.updateCallLog(
        doctype: widget.doctype,
        docname: widget.docname,
        customerName: widget.customerName,
        mobileNo: widget.mobileNo,
        callDuration: widget.callDuration.inSeconds,
        initiatedTime: widget.initiatedTime,
        callStatus: _callStatus,
        disconnectedStatus: _disconnectedStatus.isEmpty
            ? "unknown"
            : _disconnectedStatus,
        notes: _notes,
        attended: _attended,
        dataSource: widget.dataSource,
        permissionGranted: widget.permissionGranted,
        retrievedAttempt: widget.retrievedAttempt,
      );

      debugPrint("[COMPLETION] Result: $result");

      if (mounted) {
        if (result['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("✅ Call logged successfully"),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
          Navigator.pop(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("❌ Failed to log call: ${result['message']}"),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("[COMPLETION] Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("❌ Error: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  String _formatDuration(Duration duration) {
    int seconds = duration.inSeconds;
    int minutes = seconds ~/ 60;
    int remainingSeconds = seconds % 60;

    if (minutes == 0) {
      return "$remainingSeconds seconds";
    } else if (remainingSeconds == 0) {
      return "$minutes minutes";
    } else {
      return "$minutes:${remainingSeconds.toString().padLeft(2, '0')} minutes";
    }
  }
}
