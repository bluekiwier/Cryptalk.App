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
  final String? senderNickname;
  final String? senderAvatar;
  final MessageType type;
  final DateTime? createdAt;
  final bool isRead;
  final String? quoteId;
  final MessageStatus status;
  final int seqId;

  const Message({
    required this.id,
    required this.content,
    required this.createdAt,
    this.senderId = '',
    this.senderNickname,
    this.senderAvatar,
    this.type = MessageType.text,
    this.isRead = false,
    this.quoteId,
    this.status = MessageStatus.normal,
    this.seqId = 0,
  });
}

/// 消息类型枚举
enum MessageType {
  text, // 文本消息
  image, // 图片消息
  audio, // 语音消息
  video, // 视频消息
  file, // 文件消息
  location, // 位置消息
  contact, // 联系人消息
  hongBao, // 红包消息
  system, // 系统消息
  broadcast, // 广播消息
  groupNotify, // 群通知消息
}
