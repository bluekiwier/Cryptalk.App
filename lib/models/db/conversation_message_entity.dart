/// 消息实体（sqflite）
class ConversationMessageEntity {
  static const String tableName = 'conversation_message';

  static const String id = 'id';
  static const String conversationId = 'conversation_id';
  static const String conversationType = 'conversation_type';
  static const String seqId = 'seq_id';
  static const String senderId = 'sender_id';
  static const String senderNickname = 'sender_nickname';
  static const String senderAvatar = 'sender_avatar';
  static const String quoteId = 'quote_id';
  static const String content = 'content';

  /// 消息类型：0=文字,1=图片,2=语音,3=视频,4=文件,5=位置,6=名片,7=红包,8=系统通知,9=广播,10=群通知消息
  static const String type = 'type';

  /// 消息状态：0=正常,1=撤回,2=删除
  static const String status = 'status';
  static const String createdAt = 'created_at';
  static const String isRead = 'is_read';
}
