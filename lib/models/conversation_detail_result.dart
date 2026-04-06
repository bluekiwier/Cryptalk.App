class ConversationDetailResult {
  /// 会话ID
  final String id;

  /// 会话类型（1: 单聊，2: 群聊）
  final int type;

  /// 聊天用户ID
  final String chatUserId;

  /// 标题
  final String title;

  /// 头像
  final String avatar;

  /// 最后一条消息序列ID
  final int lastSeqId;

  /// 最后一条消息发送者ID
  final String lastSenderId;

  /// 最后一条消息ID
  final String lastMessageId;

  /// 最后一条消息时间
  final DateTime? lastMessageAt;

  /// 最后一条消息内容预览
  final String? lastMessagePreview;

  /// 群公告
  final String? announcement;

  /// 是否全员禁言:0=否,1=是
  final bool isAllMuted;

  /// 未读消息数量
  final int unreadCount;

  /// 是否置顶
  final bool isPinned;

  /// 是否免打扰
  final bool isMuted;

  const ConversationDetailResult({
    required this.id,
    required this.type,
    required this.chatUserId,
    required this.title,
    required this.avatar,
    required this.lastSeqId,
    required this.lastSenderId,
    required this.lastMessageId,
    this.lastMessageAt,
    this.lastMessagePreview,
    this.announcement,
    this.isAllMuted = false,
    required this.unreadCount,
    required this.isPinned,
    required this.isMuted,
  });

  factory ConversationDetailResult.fromJson(Map<String, dynamic> json) {
    return ConversationDetailResult(
      id: json['id'].toString(),
      type: json['type'] as int? ?? 1,
      chatUserId: json['chatUserId'].toString(),
      title: json['title']?.toString() ?? '',
      avatar: json['avatar']?.toString() ?? '',
      lastSeqId: int.tryParse(json['lastSeqId']?.toString() ?? '0') ?? 0,
      lastSenderId: json['lastSenderId'].toString(),
      lastMessageId: json['lastMessageId'].toString(),
      lastMessageAt: json['lastMessageAt'] != null ? DateTime.tryParse(json['lastMessageAt'].toString()) : null,
      lastMessagePreview: json['lastMessagePreview']?.toString(),
      announcement: json['announcement']?.toString(),
      unreadCount: int.tryParse(json['unreadCount']?.toString() ?? '0') ?? 0,
      isPinned: json['isPinned'] == true || json['isPinned'] == 1,
      isMuted: json['isMuted'] == true || json['isMuted'] == 1,
      isAllMuted: json['isAllMuted'] == true || json['isAllMuted'] == 1,
    );
  }
}
