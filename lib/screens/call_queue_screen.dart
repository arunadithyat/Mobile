import 'package:flutter/material.dart';
import 'package:lead_calling/models/call_queue.dart';

class CallQueueScreen extends StatefulWidget {
  final CallQueue callQueue;
  final Function(int oldIndex, int newIndex) onReorder;
  final Function(int index)? onMarkCancelled;
  final Function(int index)? onRestorePending;

  const CallQueueScreen({
    super.key,
    required this.callQueue,
    required this.onReorder,
    this.onMarkCancelled,
    this.onRestorePending,
  });

  @override
  State<CallQueueScreen> createState() => _CallQueueScreenState();
}

class _CallQueueScreenState extends State<CallQueueScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Call Queue (${widget.callQueue.pendingCount} pending)",
        ),
        elevation: 0,
      ),
      body: widget.callQueue.isEmpty
          ? _buildEmptyState()
          : _buildQueueList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.done_all,
            size: 80,
            color: Colors.green.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 20),
          const Text(
            "No Calls in Queue",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Text(
            "All calls have been processed!",
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildQueueList() {
    return ReorderableListView.builder(
      itemCount: widget.callQueue.length,
      padding: const EdgeInsets.all(10),
      onReorder: widget.onReorder,
      itemBuilder: (context, index) {
        final callItem = widget.callQueue.get(index);
        if (callItem == null) return SizedBox.shrink(key: ValueKey(index));

        final isCancelled = callItem.isCancelled;

        return Card(
          key: ValueKey('${callItem.docname}_${callItem.mobileNo}'),
          margin: const EdgeInsets.symmetric(vertical: 8),
          color: isCancelled ? Colors.grey.shade100 : null,
          child: ListTile(
            leading: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: isCancelled
                    ? Colors.grey.withValues(alpha: 0.15)
                    : Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: isCancelled
                    ? Icon(Icons.cancel_outlined, color: Colors.grey[500], size: 24)
                    : Text(
                        "${index + 1}",
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
              ),
            ),
            title: Text(
              callItem.customerName,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isCancelled ? Colors.grey : null,
                decoration: isCancelled ? TextDecoration.lineThrough : null,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  callItem.mobileNo,
                  style: TextStyle(
                    fontSize: 14,
                    color: isCancelled ? Colors.grey[400] : Colors.grey,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      "Queued: ${callItem.formattedTime}",
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                    if (isCancelled) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          "Cancelled",
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.orange.shade800,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            trailing: isCancelled
                ? IconButton(
                    icon: const Icon(Icons.redo, color: Colors.orange),
                    tooltip: "Restore to queue",
                    onPressed: () {
                      setState(() {
                        widget.callQueue.restorePending(index);
                      });
                      widget.onRestorePending?.call(index);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("${callItem.customerName} restored to queue"),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                  )
                : IconButton(
                    icon: const Icon(Icons.call, color: Colors.green),
                    tooltip: "Call Now",
                    onPressed: () {
                      Navigator.pop(context, index);
                    },
                  ),
          ),
        );
      },
    );
  }
}
