class SendMessageResult {
  final String? messageId;
  final String? message;
  final bool? success;

  const SendMessageResult({this.messageId, this.message, this.success});

  bool get isSuccess => success == true;
}
