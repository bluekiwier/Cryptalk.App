/// 好友申请模型
/// 用于表示待处理的好友申请数据
class FriendRequest {
  /// 申请记录 ID
  final String id;

  /// 申请人账号
  final String account;

  /// 申请人昵称
  final String nickname;

  /// 申请人头像
  final String avatar;

  /// 好友备注名（可选）
  final String? alias;

  const FriendRequest({
    required this.id,
    required this.account,
    required this.nickname,
    required this.avatar,
    this.alias,
  });

  /// 从 JSON 数据构造
  factory FriendRequest.fromJson(Map<String, dynamic> json) {
    return FriendRequest(
      id: json['id']?.toString() ?? '',
      account: json['account']?.toString() ?? '',
      nickname: json['nickname']?.toString() ?? '',
      avatar: json['avatar']?.toString() ?? '',
      alias: json['alias']?.toString(),
    );
  }
}
