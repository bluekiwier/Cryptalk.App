import 'user.dart';
import 'message.dart';

/// 会话模型（单聊或群聊）
class Conversation {
  final String id;
  final String title;
  final String avatar;
  final bool isGroup;
  final Message? lastMessage;
  final int unreadCount;
  final bool isPinned;
  final bool isMuted;
  final List<User> members;

  const Conversation({
    required this.id,
    required this.title,
    required this.avatar,
    this.isGroup = false,
    this.lastMessage,
    this.unreadCount = 0,
    this.isPinned = false,
    this.isMuted = false,
    this.members = const [],
  });
}
