import 'package:cryptalk/models/message.dart';
import 'package:flutter/material.dart';
import '../../config/api_config.dart';
import '../../services/account_service.dart';
import '../../models/conversation.dart';

/// 会话服务 - 获取会话列表等
class ConversationService {
  static final ConversationService _instance = ConversationService._internal();
  factory ConversationService() => _instance;
  ConversationService._internal();

  /// 获取所有会话列表
  Future<List<Conversation>> getConversations() async {
    try {
      final dio = await AccountService().getDio();
      final response = await dio.get(
        '${ApiConfig.baseUrl}/api/conversation/list',
      );

      final responseData = response.data;
      if (responseData != null && responseData['success'] == true) {
        final List<dynamic> data = responseData['data'] ?? [];
        return data.map((json) {
          return Conversation(
            id: json['id']?.toString() ?? '',
            chatUserId: json['chatUserId']?.toString() ?? '',
            title: json['title']?.toString() ?? '',
            avatar: json['avatar']?.toString() ?? '',
            isGroup: json['type'] == 2,
            unreadCount: (json['unreadCount'] is int)
                ? json['unreadCount']
                : int.tryParse(json['unreadCount']?.toString() ?? '0') ?? 0,
            isPinned: json['isPinned'] == 1 || json['isPinned'] == true,
            isMuted: json['isMute'] == 1 || json['isMute'] == true,
            lastMessage: Message(
              id: json['lastMessageId']?.toString() ?? '',
              content: json['lastMessagePreview']?.toString() ?? '',
              senderId: json['lastSenderId']?.toString() ?? '',
              type: MessageType.text,
              timestamp: json['lastMessageAt'] != null
                  ? DateTime.tryParse(json['lastMessageAt'].toString()) ??
                        DateTime.now()
                  : DateTime.now(),
              isRead: true,
            ),
          );
        }).toList();
      }
    } catch (e) {
      debugPrint('获取会话列表异常: $e');
    }
    return [];
  }

  /// 获取会话的聊天消息列表
  /// [conversationId] 会话ID
  /// [messageId] 翻页用的最小消息ID，首次为0
  /// [pageSize] 每页数量
  Future<Map<String, dynamic>?> getMessages(
    dynamic conversationId, {
    int messageId = 0,
    int pageSize = 20,
  }) async {
    try {
      final dio = await AccountService().getDio();
      final response = await dio.post(
        '${ApiConfig.baseUrl}/api/conversation/messages',
        data: {
          'conversationId': conversationId is String
              ? int.tryParse(conversationId) ?? 0
              : (conversationId ?? 0),
          'messageId': messageId,
          'pageSize': pageSize,
        },
      );
      return response.data;
    } catch (e) {
      debugPrint('获取聊天消息列表异常: $e');
      return null;
    }
  }
}
