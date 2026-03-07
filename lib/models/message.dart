/// 消息状态枚举
enum MessageStatus {
  normal, // 正常
  recalled, // 撤回
  deleted, // 删除
}

/// 消息模型
class Message {
  final String id;
  final String content;
  final String senderId;
  final MessageType type;
  final DateTime createdAt;
  final bool isRead;
  final String? quoteId;
  final MessageStatus status;

  const Message({
    required this.id,
    required this.content,
    this.senderId = '',
    this.type = MessageType.text,
    required this.createdAt,
    this.isRead = false,
    this.quoteId,
    this.status = MessageStatus.normal,
  });
}

/// 消息类型枚举
enum MessageType {
  text, // 文本消息
  image, // 图片消息
  voice, // 语音消息
  video, // 视频消息
  file, // 文件消息
  system, // 系统消息
}
