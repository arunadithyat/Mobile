import 'package:flutter/material.dart';
import 'package:lead_calling/models/call_queue.dart';

class CallQueueScreen extends StatefulWidget {
  final CallQueue callQueue;
  final Function(int oldIndex, int newIndex) onReorder;

  const CallQueueScreen({
    super.key,
    required this.callQueue,
    required this.onReorder,
  });

  @override
  State<CallQueueScreen> createState() => _CallQueueScreenState();
}

class _CallQueueScreenState extends State<CallQueueScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Call Queue"),
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
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            "All calls have been processed!",
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
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

        return Card(
          key: ValueKey('${callItem.docname}_${callItem.mobileNo}'),
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: ListTile(
            leading: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
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
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  callItem.mobileNo,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Queued: ${callItem.formattedTime}",
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.call, color: Colors.green),
              onPressed: () {
                Navigator.pop(context, index);
              },
              tooltip: "Call Now",
            ),
          ),
        );
      },
    );
  }
}
