/// 群成员模型
class GroupMember {
  final String userId;
  final String account;
  final String nickname;
  final String avatar;
  final int role;

  const GroupMember({
    required this.userId,
    required this.account,
    required this.nickname,
    required this.avatar,
    required this.role,
  });

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    return GroupMember(
      userId: json['userId']?.toString() ?? '',
      account: json['account']?.toString() ?? '',
      nickname: json['nickname']?.toString() ?? '',
      avatar: json['avatar']?.toString() ?? '',
      role: json['role'] as int? ?? 0,
    );
  }

  bool get isOwner => role == 1;
  bool get isAdmin => role == 2;
  bool get isMember => role == 3;
}
