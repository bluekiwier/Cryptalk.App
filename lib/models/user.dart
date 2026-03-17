/// 用户模型
class User {
  final String id;
  final String account;
  final String nickname;
  final String avatar;
  final String? mobile;
  final String? email;
  final String? signature;
  final String? inviteCode;
  final int? friendRequestCount; // 好友申请数量（可选）
  final int? messageUnreadCount; // 消息未读数量（可选）
  final bool online;
  final DateTime? lastSeen;

  const User({
    required this.id,
    required this.account,
    required this.nickname,
    required this.avatar,
    this.mobile,
    this.email,
    this.signature,
    this.inviteCode,
    this.friendRequestCount,
    this.messageUnreadCount,
    this.online = false,
    this.lastSeen,
  });

  /// 从 JSON 数据构造
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id']?.toString() ?? '',
      account: json['account']?.toString() ?? '',
      nickname: json['nickname']?.toString() ?? '未知',
      avatar: json['avatar']?.toString() ?? '',
      mobile: json['mobile']?.toString(),
      email: json['email']?.toString(),
      signature: json['signature']?.toString(),
      inviteCode: json['inviteCode']?.toString(),
      friendRequestCount: json['friendRequestCount'] is int ? json['friendRequestCount'] : null,
      messageUnreadCount: json['messageUnreadCount'] is int ? json['messageUnreadCount'] : null,
      online: json['online'] == 1 || json['online'] == true,
    );
  }

  /// 拷贝并修改部分属性
  User copyWith({
    String? id,
    String? account,
    String? nickname,
    String? avatar,
    String? mobile,
    String? email,
    String? signature,
    String? inviteCode,
    int? friendRequestCount,
    int? messageUnreadCount,
    bool? online,
    DateTime? lastSeen,
  }) {
    return User(
      id: id ?? this.id,
      account: account ?? this.account,
      nickname: nickname ?? this.nickname,
      avatar: avatar ?? this.avatar,
      mobile: mobile ?? this.mobile,
      email: email ?? this.email,
      signature: signature ?? this.signature,
      inviteCode: inviteCode ?? this.inviteCode,
      friendRequestCount: friendRequestCount ?? this.friendRequestCount,
      messageUnreadCount: messageUnreadCount ?? this.messageUnreadCount,
      online: online ?? this.online,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}
