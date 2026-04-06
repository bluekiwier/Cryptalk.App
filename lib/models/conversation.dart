import 'user.dart';

/// 会话模型（单聊或群聊）
class Conversation {
  final String id;
  final String chatUserId;
  final String title;
  final String avatar;
  final bool isGroup;
  final int unreadCount;
  final bool isPinned;
  final bool isMuted;
  final List<User> members;
  final int lastSeqId;
  final String lastSenderId;
  final String lastMessageId;
  final DateTime? lastMessageAt;
  final String? lastMessagePreview;

  const Conversation({
    required this.id,
    required this.chatUserId,
    required this.title,
    required this.avatar,
    this.isGroup = false,
    this.unreadCount = 0,
    this.isPinned = false,
    this.isMuted = false,
    this.members = const [],
    this.lastSeqId = 0,
    this.lastSenderId = '',
    this.lastMessageId = '',
    this.lastMessageAt,
    this.lastMessagePreview = '',
  });
}
