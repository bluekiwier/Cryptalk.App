/// 消息模型
class Message {
  final String id;
  final String senderId;
  final String content;
  final MessageType type;
  final DateTime timestamp;
  final bool isRead;

  const Message({
    required this.id,
    required this.senderId,
    required this.content,
    this.type = MessageType.text,
    required this.timestamp,
    this.isRead = false,
  });
}

/// 消息类型枚举
enum MessageType {
  text,    // 文本消息
  image,   // 图片消息
  voice,   // 语音消息
  video,   // 视频消息
  file,    // 文件消息
  system,  // 系统消息
}
