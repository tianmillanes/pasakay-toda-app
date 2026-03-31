import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../screens/chat_screen.dart';
import '../utils/app_theme.dart';

class ChatButton extends StatefulWidget {
  final String contextId;
  final String collectionPath; // 'rides' or 'pasabuy_requests'
  final String otherUserName;
  final String otherUserId;
  final bool mini;

  const ChatButton({
    Key? key,
    required this.contextId,
    required this.collectionPath,
    required this.otherUserName,
    required this.otherUserId,
    this.mini = false,
  }) : super(key: key);

  @override
  _ChatButtonState createState() => _ChatButtonState();
}

class _ChatButtonState extends State<ChatButton> {
  late Stream<int> _unreadCountStream;
  final ChatService _chatService = ChatService();
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _initializeStream();
  }

  @override
  void didUpdateWidget(ChatButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contextId != widget.contextId || 
        oldWidget.collectionPath != widget.collectionPath ||
        oldWidget.otherUserId != widget.otherUserId) {
      _initializeStream();
    }
  }

  void _initializeStream() {
    final authService = Provider.of<AuthService>(context, listen: false);
    _currentUserId = authService.currentUser?.uid;

    if (_currentUserId != null) {
      _unreadCountStream = _chatService.getUnreadCountStream(
        collectionPath: widget.collectionPath,
        docId: widget.contextId,
        currentUserId: _currentUserId!,
      );
    } else {
      _unreadCountStream = Stream.value(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUserId == null) return const SizedBox.shrink();

    return StreamBuilder<int>(
      stream: _unreadCountStream,
      builder: (context, snapshot) {
        final unreadCount = snapshot.data ?? 0;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            FloatingActionButton(
              heroTag: 'chat_fab_${widget.contextId}', // Unique hero tag
              mini: widget.mini,
              elevation: widget.mini ? 2 : 6, // Reduce elevation for mini buttons
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ChatScreen(
                      contextId: widget.contextId,
                      collectionPath: widget.collectionPath,
                      otherUserName: widget.otherUserName,
                      otherUserId: widget.otherUserId,
                    ),
                  ),
                );
              },
              backgroundColor: Colors.white,
              child: const Icon(Icons.chat_bubble_outline, color: AppTheme.primaryGreen),
            ),
            if (unreadCount > 0)
              Positioned(
                right: widget.mini ? -2 : -2,
                top: widget.mini ? -2 : -2,
                child: Container(
                  padding: EdgeInsets.all(widget.mini ? 3 : 6),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  constraints: BoxConstraints(
                    minWidth: widget.mini ? 18 : 22,
                    minHeight: widget.mini ? 18 : 22,
                  ),
                  child: Text(
                    unreadCount > 9 ? '9+' : unreadCount.toString(),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: widget.mini ? 10 : 12,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
