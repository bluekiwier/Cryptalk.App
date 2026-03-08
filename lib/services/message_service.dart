import 'dart:async';
import 'package:logger/logger.dart';
import 'account_service.dart';

class MessageService {
  static final MessageService _instance = MessageService._internal();
  factory MessageService() => _instance;
  MessageService._internal();

  final Logger _logger = Logger();

  /// 撤回消息
  Future<bool> recallMessage(String messageId) async {
    try {
      // 调用后端撤回API
      final dio = await AccountService().getDio();
      final response = await dio.delete('/api/message/recall', data: {'id': messageId});
      return response.statusCode == 200;
    } catch (e) {
      _logger.e('撤回消息失败: $e');
      return false;
    }
  }

  /// 删除消息
  Future<bool> deleteMessage(String messageId) async {
    try {
      // 调用后端删除API
      final dio = await AccountService().getDio();
      final response = await dio.delete('/api/message/delete', data: {'id': messageId});
      return response.statusCode == 200;
    } catch (e) {
      _logger.e('删除消息失败: $e');
      return false;
    }
  }
}
