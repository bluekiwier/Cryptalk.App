/// 消息实体（sqflite）
class ConversationMessageEntity {
  static const String tableName = 'messages';

  static const String id = 'id';
  static const String conversationId = 'conversation_id';
  static const String conversationType = 'conversation_type';
  static const String senderId = 'sender_id';
  static const String senderNickname = 'sender_nickname';
  static const String senderAvatar = 'sender_avatar';
  static const String quoteId = 'quote_id';
  static const String content = 'content';
  static const String type = 'type';
  static const String status = 'status';
  static const String createdAt = 'created_at';
}
