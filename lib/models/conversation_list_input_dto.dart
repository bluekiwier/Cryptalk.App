class ConversationListInputDto {
  final bool? isPinned;
  final DateTime? lastMessageAt;
  final int? id;
  final int pageSize;

  /// 每页默认加载条数
  static const int defaultPageSize = 10;

  const ConversationListInputDto({this.isPinned, this.lastMessageAt, this.id, this.pageSize = defaultPageSize});

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};
    if (isPinned != null) {
      data['isPinned'] = isPinned;
    }
    if (lastMessageAt != null) {
      data['lastMessageAt'] = lastMessageAt!.toIso8601String();
    }
    if (id != null) {
      data['id'] = id;
    }
    data['pageSize'] = pageSize;
    return data;
  }

  factory ConversationListInputDto.fromJson(Map<String, dynamic> json) {
    return ConversationListInputDto(
      isPinned: json['isPinned'] as bool?,
      lastMessageAt: json['lastMessageAt'] != null ? DateTime.tryParse(json['lastMessageAt'].toString()) : null,
      id: json['id'] as int?,
      // 强制使用客户端固定页面大小，忽略服务端 cursor 里记录的 pageSize
      pageSize: defaultPageSize,
    );
  }
}
