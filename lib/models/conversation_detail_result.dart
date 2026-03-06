class ConversationDetailResult {
  final int id;
  final int type;
  final int chatUserId;
  final String title;
  final String avatar;
  final int lastSenderId;
  final int lastMessageId;
  final DateTime? lastMessageAt;
  final String? lastMessagePreview;
  final int unreadCount;
  final bool isPinned;
  final bool isMuted;

  const ConversationDetailResult({
    required this.id,
    required this.type,
    required this.chatUserId,
    required this.title,
    required this.avatar,
    required this.lastSenderId,
    required this.lastMessageId,
    this.lastMessageAt,
    this.lastMessagePreview,
    required this.unreadCount,
    required this.isPinned,
    required this.isMuted,
  });

  factory ConversationDetailResult.fromJson(Map<String, dynamic> json) {
    return ConversationDetailResult(
      id: json['id'] as int? ?? 0,
      type: json['type'] as int? ?? 1,
      chatUserId: json['chatUserId'] as int? ?? 0,
      title: json['title']?.toString() ?? '',
      avatar: json['avatar']?.toString() ?? '',
      lastSenderId: json['lastSenderId'] as int? ?? 0,
      lastMessageId: json['lastMessageId'] as int? ?? 0,
      lastMessageAt: json['lastMessageAt'] != null ? DateTime.tryParse(json['lastMessageAt'].toString()) : null,
      lastMessagePreview: json['lastMessagePreview']?.toString(),
      unreadCount: (json['unreadCount'] is int)
          ? json['unreadCount']
          : int.tryParse(json['unreadCount']?.toString() ?? '0') ?? 0,
      isPinned: json['isPinned'] == true || json['isPinned'] == 1,
      isMuted: json['isMuted'] == true || json['isMuted'] == 1,
    );
  }
}
