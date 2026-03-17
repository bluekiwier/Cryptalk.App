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
  final bool onlineStatus;
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
    this.onlineStatus = false,
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
      onlineStatus: json['onlineStatus'] == 1 || json['onlineStatus'] == true,
    );
  }
}
