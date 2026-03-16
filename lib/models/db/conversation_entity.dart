/// 会话实体（sqflite）
class ConversationEntity {
  static const String tableName = 'conversation';

  static const String id = 'id';
  static const String type = 'type';
  static const String chatUserId = 'chat_user_id';
  static const String title = 'title';
  static const String avatar = 'avatar';
  static const String lastSeqId = 'last_seq_id';
  static const String lastSenderId = 'last_sender_id';
  static const String lastMessageId = 'last_message_id';
  static const String lastMessageAt = 'last_message_at';
  static const String lastMessagePreview = 'last_message_preview';
  static const String unreadCount = 'unread_count';
  static const String isPinned = 'is_pinned';
  static const String isMuted = 'is_muted';
  static const String updatedAt = 'updated_at';
}
