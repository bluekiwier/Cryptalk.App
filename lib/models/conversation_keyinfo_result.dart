class ConversationKeyInfoResult {
  final String id;
  final String secretKey;
  final String secretVersion;

  const ConversationKeyInfoResult({required this.id, required this.secretKey, required this.secretVersion});

  factory ConversationKeyInfoResult.fromJson(Map<String, dynamic> json) {
    return ConversationKeyInfoResult(
      id: json['id'],
      secretKey: json['secretKey'],
      secretVersion: json['secretVersion'],
    );
  }
}
