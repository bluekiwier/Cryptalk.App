import 'dart:async';
import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'account_service.dart';

class MessageService {
  static final MessageService _instance = MessageService._internal();
  factory MessageService() => _instance;
  MessageService._internal();

  final Logger _logger = Logger();

  /// 撤回消息
  Future<bool> recall(String messageId) async {
    try {
      // 调用后端撤回API
      final dio = await AccountService().getDio();
      final response = await dio.delete(
        '/api/message/recall',
        data: {'id': messageId},
        options: Options(extra: {'obfuscate': true}),
      );
      return response.statusCode == 200;
    } catch (e) {
      _logger.e('撤回消息失败: $e');
      return false;
    }
  }

  /// 删除消息
  Future<bool> delete(String messageId) async {
    try {
      // 调用后端删除API
      final dio = await AccountService().getDio();
      final response = await dio.delete(
        '/api/message/delete',
        data: {'id': messageId},
        options: Options(extra: {'obfuscate': true}),
      );
      return response.statusCode == 200;
    } catch (e) {
      _logger.e('删除消息失败: $e');
      return false;
    }
  }

  /// 更新已读序号
  Future<bool> markAsRead(String messageId) async {
    try {
      // 调用后端删除API
      final dio = await AccountService().getDio();
      final response = await dio.post('/api/message/mark-as-read', data: {'id': messageId});
      return response.data != null && response.data['success'] == true;
    } catch (e) {
      _logger.e('标记已读失败: $e');
      return false;
    }
  }
}
