/// 用户模型
class User {
  final String id;
  final String account;
  final String nickname;
  final String avatar;
  final String? mobile;
  final String? email;
  final String? signature;
  final bool isOnline;
  final DateTime? lastSeen;

  const User({
    required this.id,
    required this.account,
    required this.nickname,
    required this.avatar,
    this.mobile,
    this.email,
    this.signature,
    this.isOnline = false,
    this.lastSeen,
  });

  /// 从 JSON 数据构造
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id']?.toString() ?? '',
      account: json['account']?.toString() ?? '',
      nickname: json['alias']?.toString().isNotEmpty == true
          ? json['alias'].toString()
          : (json['nickname']?.toString() ?? '未知'),
      avatar: json['avatar']?.toString() ?? '',
      mobile: json['mobile']?.toString(),
      email: json['email']?.toString(),
      signature: json['signature']?.toString(),
      isOnline: json['isOnline'] == 1 || json['isOnline'] == true,
    );
  }
}
