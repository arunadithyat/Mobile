import 'package:flutter/material.dart';

/// A single chat message (bot or user).
class ChatMessage {
  final String text;
  final bool isBot;
  final List<ChatOption>? options;
  final String? navigateTo; // screen route to navigate

  ChatMessage({
    required this.text,
    this.isBot = true,
    this.options,
    this.navigateTo,
  });
}

/// A tappable option button in the chat.
class ChatOption {
  final String label;
  final String icon;
  final String responseKey; // key to look up the bot's response

  ChatOption({
    required this.label,
    required this.icon,
    required this.responseKey,
  });
}

/// Predefined bot responses and navigation flows.
class ChatTemplates {
  static final Map<String, ChatMessage> responses = {
    'welcome': ChatMessage(
      text: "Hi! I'm your SalesGenie assistant. How can I help you today?",
      options: [
        ChatOption(label: "How to make calls", icon: "📞", responseKey: "how_to_call"),
        ChatOption(label: "How to use call queue", icon: "📋", responseKey: "how_to_queue"),
        ChatOption(label: "Taking a break", icon: "⏸️", responseKey: "how_to_break"),
        ChatOption(label: "Send message to lead", icon: "💬", responseKey: "how_to_message"),
        ChatOption(label: "View call history", icon: "📊", responseKey: "how_to_history"),
        ChatOption(label: "App features", icon: "⭐", responseKey: "features"),
      ],
    ),

    'how_to_call': ChatMessage(
      text: "Making calls is easy!\n\n"
          "1. From the Call Queue tab, tap the green phone icon next to any customer name to call them directly.\n\n"
          "2. Or tap the 'Process' button to call the first person in the queue.\n\n"
          "3. When an FCM notification arrives, the app will auto-dial the first call for you.",
      options: [
        ChatOption(label: "Go to Call Queue", icon: "📋", responseKey: "nav_queue"),
        ChatOption(label: "What happens after a call?", icon: "📝", responseKey: "after_call"),
        ChatOption(label: "Back to menu", icon: "🏠", responseKey: "welcome"),
      ],
    ),

    'how_to_queue': ChatMessage(
      text: "The Call Queue shows all your pending calls from the backend.\n\n"
          "• Calls are grouped by category — Hot Leads, Followup Leads, etc.\n\n"
          "• Swipe down to refresh the queue from the server.\n\n"
          "• Each call has a phone icon (call) and message icon (SMS/WhatsApp).\n\n"
          "• When you cancel a call, it moves to the end of the queue — not removed.",
      options: [
        ChatOption(label: "How to make calls", icon: "📞", responseKey: "how_to_call"),
        ChatOption(label: "How to send messages", icon: "💬", responseKey: "how_to_message"),
        ChatOption(label: "Back to menu", icon: "🏠", responseKey: "welcome"),
      ],
    ),

    'how_to_break': ChatMessage(
      text: "Need a break? Here's how:\n\n"
          "1. Tap the red 'Pause' button on the top banner.\n\n"
          "2. Select a reason — Break, Lunch, or Meeting.\n\n"
          "3. The banner will show 'On Break' / 'On Lunch' / 'On Meeting'.\n\n"
          "4. No auto-calls will happen while paused.\n\n"
          "5. Tap 'Resume' when you're ready to continue.",
      options: [
        ChatOption(label: "Go back to calls", icon: "📞", responseKey: "how_to_call"),
        ChatOption(label: "Back to menu", icon: "🏠", responseKey: "welcome"),
      ],
    ),

    'how_to_message': ChatMessage(
      text: "You can send SMS or WhatsApp messages to any queued customer!\n\n"
          "1. Tap the message icon (blue) next to any customer in the queue.\n\n"
          "2. Choose from ready-made templates — Missed you, Follow up, Order update, Thank you.\n\n"
          "3. The message is auto-filled with the customer's name.\n\n"
          "4. Tap the SMS icon to send via text, or WhatsApp icon to send via WhatsApp.",
      options: [
        ChatOption(label: "Go to Call Queue", icon: "📋", responseKey: "nav_queue"),
        ChatOption(label: "Back to menu", icon: "🏠", responseKey: "welcome"),
      ],
    ),

    'how_to_history': ChatMessage(
      text: "The History tab tracks all your calls!\n\n"
          "• Connected — calls where the customer answered (green)\n"
          "• Not Answered — calls that rang but weren't picked up (red)\n"
          "• Customer Called Back — incoming calls from queued customers (blue)\n"
          "• Missed Call — calls you missed from customers (orange)\n\n"
          "Pull down to refresh. The app also tracks incoming calls from customers in your queue automatically.",
      navigateTo: 'history',
      options: [
        ChatOption(label: "Go to History", icon: "📊", responseKey: "nav_history"),
        ChatOption(label: "Back to menu", icon: "🏠", responseKey: "welcome"),
      ],
    ),

    'after_call': ChatMessage(
      text: "After every call, a Post Call Update dialog appears:\n\n"
          "• Call Duration — captured automatically from the device.\n\n"
          "• Call Status — Connected, Not Answered, etc.\n\n"
          "• Customer Attended — checkbox.\n\n"
          "• Notes — add any notes about the conversation.\n\n"
          "Tap Submit to save the update to the backend. The call is then removed from your queue.",
      options: [
        ChatOption(label: "How to make calls", icon: "📞", responseKey: "how_to_call"),
        ChatOption(label: "Back to menu", icon: "🏠", responseKey: "welcome"),
      ],
    ),

    'features': ChatMessage(
      text: "Here's what SalesGenie can do:\n\n"
          "📞 Auto-dial leads from FCM notifications\n"
          "📋 Call queue with categories (Hot, Followup, B2B)\n"
          "⏸️ Pause with reasons (Break, Lunch, Meeting)\n"
          "📊 Call history with status tracking\n"
          "💬 SMS & WhatsApp templates\n"
          "📱 Incoming call detection from queued customers\n"
          "🔒 Smart call detection — won't interrupt active calls\n"
          "📈 KPI dashboard with live counts",
      options: [
        ChatOption(label: "How to make calls", icon: "📞", responseKey: "how_to_call"),
        ChatOption(label: "How to use queue", icon: "📋", responseKey: "how_to_queue"),
        ChatOption(label: "Back to menu", icon: "🏠", responseKey: "welcome"),
      ],
    ),

    'nav_queue': ChatMessage(
      text: "Taking you to the Call Queue...",
      navigateTo: 'queue',
    ),

    'nav_history': ChatMessage(
      text: "Taking you to Call History...",
      navigateTo: 'history',
    ),
  };
}

class ChatbotScreen extends StatefulWidget {
  final Function(String)? onNavigate;

  const ChatbotScreen({super.key, this.onNavigate});

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> {
  final List<ChatMessage> _messages = [];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _addBotMessage('welcome');
  }

  void _addBotMessage(String key) {
    final template = ChatTemplates.responses[key];
    if (template == null) return;

    setState(() {
      _messages.add(template);
    });

    // Auto-scroll to bottom
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });

    // Handle navigation
    if (template.navigateTo != null) {
      Future.delayed(const Duration(milliseconds: 800), () {
        widget.onNavigate?.call(template.navigateTo!);
      });
    }
  }

  void _onOptionTapped(ChatOption option) {
    // Add user's selection as a message
    setState(() {
      _messages.add(ChatMessage(
        text: option.label,
        isBot: false,
      ));
    });

    // Add bot response after a short delay
    Future.delayed(const Duration(milliseconds: 400), () {
      _addBotMessage(option.responseKey);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: Color(0xFF1A73E8),
              child: Text("SG", style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
            SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("SalesGenie Assistant", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                Text("Always here to help", style: TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ],
        ),
        elevation: 1,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                return _buildMessage(msg);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(ChatMessage msg) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment:
            msg.isBot ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        children: [
          // Message bubble
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.82,
            ),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: msg.isBot
                  ? Colors.grey.shade100
                  : const Color(0xFF1A73E8),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(msg.isBot ? 4 : 16),
                bottomRight: Radius.circular(msg.isBot ? 16 : 4),
              ),
            ),
            child: Text(
              msg.text,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: msg.isBot ? Colors.black87 : Colors.white,
              ),
            ),
          ),

          // Option buttons
          if (msg.options != null && msg.options!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: msg.options!.map((option) {
                  return InkWell(
                    onTap: () => _onOptionTapped(option),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: const Color(0xFF1A73E8).withValues(alpha: 0.4),
                        ),
                        borderRadius: BorderRadius.circular(20),
                        color: const Color(0xFF1A73E8).withValues(alpha: 0.05),
                      ),
                      child: Text(
                        "${option.icon}  ${option.label}",
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF1A73E8),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}
