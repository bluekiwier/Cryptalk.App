class SendMessageResult {
  final String? messageId;
  final String? message;
  final bool? success;
  final Map<String, dynamic>? messageData; // 服务端返回的完整消息数据

  const SendMessageResult({this.messageId, this.message, this.success, this.messageData});

  bool get isSuccess => success == true;
}
