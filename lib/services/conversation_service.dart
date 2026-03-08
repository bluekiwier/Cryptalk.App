import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:dio/dio.dart';
import 'database_service.dart';
import 'account_service.dart';
import '../models/conversation.dart';
import '../models/conversation_detail_result.dart';
import '../models/conversation_list_input_dto.dart';
import '../models/conversation_list_result.dart';
import '../models/message.dart';

/// 会话服务（ChangeNotifier）
/// 策略：本地 DB 优先呈现，后台异步同步网络数据
class ConversationService extends ChangeNotifier {
  static final ConversationService _instance = ConversationService._internal();
  factory ConversationService() => _instance;
  ConversationService._internal();

  final _logger = Logger();
  final _db = DatabaseService();

  // 内存中的会话列表（排序后）
  List<Conversation> _conversations = [];
  List<Conversation> get conversations => List.unmodifiable(_conversations);

  // 是否有更多（网络分页）
  bool _hasMore = false;
  bool get hasMore => _hasMore;

  // 下一页游标
  ConversationListInputDto? _nextCursor;

  /// 冷启动初始化：先加载本地缓存，再后台同步网络
  Future<void> initialize() async {
    await _loadFromLocal();
    // 后台非阻塞同步网络
    _syncFromNetwork();
  }

  /// 从本地 DB 加载第一页会话
  Future<void> _loadFromLocal({int limit = 20}) async {
    try {
      final rows = await _db.queryConversations(limit: limit, offset: 0);
      final list = rows.map(_rowToConversation).toList();
      _conversations = list;
      notifyListeners();
      _logger.d('本地 DB 加载会话 ${list.length} 条');
    } catch (e) {
      _logger.e('本地加载会话失败: $e');
    }
  }

  /// 后台从网络同步会话列表（首页，不阻塞 UI）
  Future<void> _syncFromNetwork() async {
    try {
      final result = await _fetchConversationsFromNetwork();
      if (result == null) return;
      // 写入本地 DB
      final rows = result.list.map(_detailResultToRow).toList();
      await _db.upsertConversations(rows);
      // 刷新内存列表
      await _loadFromLocal();
      _hasMore = result.hasMore;
      _nextCursor = result.nextCursor;
      notifyListeners();
      _logger.d('网络同步会话 ${result.list.length} 条，hasMore=$_hasMore');
    } catch (e) {
      _logger.e('网络同步会话失败: $e');
    }
  }

  // ─────────────────────────────────────────────
  // 刷新（下拉刷新）
  // ─────────────────────────────────────────────

  /// 下拉刷新：重新从网络拉取第一页
  Future<void> refresh() async {
    _hasMore = false;
    _nextCursor = null;
    await _syncFromNetwork();
  }

  /// 通知会话列表更新（用于本地修改后刷新 UI）
  Future<void> notifyConversationListChanged() async {
    await _loadFromLocal();
    notifyListeners();
  }

  // ─────────────────────────────────────────────
  // 加载更多（上拉分页）
  // ─────────────────────────────────────────────

  bool _isLoadingMore = false;
  bool get isLoadingMore => _isLoadingMore;

  /// 加载更多（网络分页，追加到末尾）
  Future<void> loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    _isLoadingMore = true;
    notifyListeners();
    try {
      final result = await _fetchConversationsFromNetwork(cursor: _nextCursor);
      if (result != null) {
        final rows = result.list.map(_detailResultToRow).toList();
        await _db.upsertConversations(rows);
        // 追加到内存列表（去重）
        final newItems = result.list.map(_detailResultToConversation).toList();
        final existingIds = _conversations.map((c) => c.id).toSet();
        final uniqueNewItems = newItems.where((c) => !existingIds.contains(c.id)).toList();
        _conversations = [..._conversations, ...uniqueNewItems];
        _hasMore = result.hasMore;
        _nextCursor = result.nextCursor;
        _logger.d('加载更多 ${newItems.length} 条，hasMore=$_hasMore');
      }
    } catch (e) {
      _logger.e('加载更多失败: $e');
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  // ─────────────────────────────────────────────
  // WebSocket 新消息到达时更新本地 DB 并刷新 UI
  // ─────────────────────────────────────────────

  /// 收到新消息时调用（由 ChatService 触发）
  /// 自动更新 DB 中的会话信息并刷新内存列表
  Future<void> onNewMessage({
    required int conversationId,
    required int senderId,
    required int messageId,
    required String messageAt,
    required String messagePreview,
    required int messageType,
    bool isInChatPage = false,
  }) async {
    // 若本地不存在该会话，先从网络拉取会话详情写入 DB
    final exists = await _db.conversationExists(conversationId);
    if (!exists) {
      await _fetchAndCacheConversationDetail(conversationId);
    }

    // 更新 DB（unread_count + 1，最新消息信息）
    if (isInChatPage) {
      // 如果当前用户在该会话聊天页面，则不需要更新未读数
      await _db.updateConversationFromMessage(
        conversationId: conversationId,
        senderId: senderId,
        messageId: messageId,
        messageAt: messageAt,
        messagePreview: messagePreview,
        messageType: messageType,
        updateUnreadCount: false,
      );
    } else {
      await _db.updateConversationFromMessage(
        conversationId: conversationId,
        senderId: senderId,
        messageId: messageId,
        messageAt: messageAt,
        messagePreview: messagePreview,
        messageType: messageType,
      );
    }

    // 局部更新内存列表（不重新全量查 DB，性能好）
    final idx = _conversations.indexWhere((c) => c.id == conversationId.toString());
    if (idx >= 0) {
      final old = _conversations[idx];
      final updated = Conversation(
        id: old.id,
        chatUserId: old.chatUserId,
        title: old.title,
        avatar: old.avatar,
        isGroup: old.isGroup,
        isPinned: old.isPinned,
        isMuted: old.isMuted,
        unreadCount: isInChatPage ? old.unreadCount : old.unreadCount + 1,
        lastMessage: Message(
          id: messageId.toString(),
          content: messagePreview,
          senderId: senderId.toString(),
          type: _mapMessageType(messageType),
          createdAt: DateTime.tryParse(messageAt) ?? DateTime.now(),
          isRead: isInChatPage ? true : false,
        ),
      );
      _conversations[idx] = updated;
      // 将该会话移至顶部（非置顶会话按时间排序）
      _sortConversations();
      notifyListeners();
    } else {
      // 不在内存列表中，重新从 DB 加载
      await _loadFromLocal();
    }
  }

  /// 进入聊天页时清零未读数
  Future<void> clearUnread(String conversationId) async {
    final convId = int.tryParse(conversationId);
    if (convId == null) return;
    await _db.clearUnreadCount(convId);

    final idx = _conversations.indexWhere((c) => c.id == conversationId);
    if (idx >= 0) {
      final old = _conversations[idx];
      _conversations[idx] = Conversation(
        id: old.id,
        chatUserId: old.chatUserId,
        title: old.title,
        avatar: old.avatar,
        isGroup: old.isGroup,
        isPinned: old.isPinned,
        isMuted: old.isMuted,
        unreadCount: 0,
        lastMessage: old.lastMessage,
      );
      notifyListeners();
    }
  }

  // ─────────────────────────────────────────────
  // 私有：分页获取会话列表
  // ─────────────────────────────────────────────

  Future<ConversationListResult?> _fetchConversationsFromNetwork({ConversationListInputDto? cursor}) async {
    try {
      final dio = await AccountService().getDio();

      final response = await dio.post(
        '/api/conversation/list',
        data: (cursor ?? const ConversationListInputDto()).toJson(),
      );
      final responseData = response.data;
      if (responseData != null && responseData['success'] == true) {
        final data = responseData['data'];
        if (data != null) return ConversationListResult.fromJson(data);
      }
    } catch (e) {
      _logger.e('请求会话列表失败: $e');
    }
    return null;
  }

  /// 拉取单个会话详情并缓存到本地
  Future<void> _fetchAndCacheConversationDetail(int conversationId) async {
    try {
      final dio = await AccountService().getDio();

      final response = await dio.get('/api/conversation/$conversationId');
      final responseData = response.data;
      if (responseData != null && responseData['success'] == true) {
        final data = responseData['data'];
        if (data != null) {
          final detail = ConversationDetailResult.fromJson(data);
          await _db.insertConversationIfAbsent(_detailResultToRow(detail));
          _logger.d('缓存会话详情: $conversationId');
        }
      }
    } catch (e) {
      _logger.e('获取会话详情失败: $e');
    }
  }

  // ─────────────────────────────────────────────
  // 旧接口兼容（供 conversation_service.dart 过渡期使用）
  // ─────────────────────────────────────────────

  /// 获取会话的聊天消息列表（网络）
  Future<Map<String, dynamic>?> getMessages(dynamic conversationId, {int messageId = 0, int pageSize = 20}) async {
    try {
      final dio = await AccountService().getDio();

      final response = await dio.post(
        '/api/conversation/messages',
        data: {
          'conversationId': conversationId is String ? int.tryParse(conversationId) ?? 0 : (conversationId ?? 0),
          'messageId': messageId,
          'pageSize': pageSize,
        },
      );
      return response.data;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout) {
        _logger.e('获取消息列表超时: $e');
        return {'success': false, 'error': 'connection_timeout', 'message': '网络连接超时，请检查网络后重试'};
      } else {
        _logger.e('获取消息列表失败: $e');
        return null;
      }
    } catch (e) {
      _logger.e('获取消息列表异常: $e');
      return null;
    }
  }

  /// 获取聊天设置信息
  Future<Map<String, dynamic>?> getChatSettings(String conversationId) async {
    try {
      final dio = await AccountService().getDio();
      final response = await dio.get('/api/conversation/setting/$conversationId');
      return response.data;
    } on DioException catch (e) {
      _logger.e('获取聊天设置失败: $e');
      return null;
    } catch (e) {
      _logger.e('获取聊天设置异常: $e');
      return null;
    }
  }

  /// 置顶聊天
  Future<Map<String, dynamic>?> pinTopConversation(String conversationId, int type) async {
    try {
      final dio = await AccountService().getDio();
      final response = await dio.post(
        '/api/conversation/pin-top',
        data: {'conversationId': int.tryParse(conversationId) ?? 0, 'type': type},
      );
      return response.data;
    } on DioException catch (e) {
      _logger.e('置顶聊天失败: $e');
      return null;
    } catch (e) {
      _logger.e('置顶聊天异常: $e');
      return null;
    }
  }

  /// 设置消息免打扰
  Future<Map<String, dynamic>?> muteConversation(String conversationId, int type) async {
    try {
      final dio = await AccountService().getDio();
      final response = await dio.post(
        '/api/conversation/mute',
        data: {'conversationId': int.tryParse(conversationId) ?? 0, 'type': type},
      );
      return response.data;
    } on DioException catch (e) {
      _logger.e('设置消息免打扰失败: $e');
      return null;
    } catch (e) {
      _logger.e('设置消息免打扰异常: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────
  // 私有：转换工具
  // ─────────────────────────────────────────────

  /// DB Row → Conversation
  Conversation _rowToConversation(Map<String, dynamic> row) {
    return Conversation(
      id: row['id'].toString(),
      chatUserId: row['chat_user_id'].toString(),
      title: row['title'] as String? ?? '',
      avatar: row['avatar'] as String? ?? '',
      isGroup: (row['type'] as int? ?? 1) == 2,
      isPinned: (row['is_pinned'] as int? ?? 0) == 1,
      isMuted: (row['is_muted'] as int? ?? 0) == 1,
      unreadCount: row['unread_count'] as int? ?? 0,
      lastMessage: row['last_message_id'] != null
          ? Message(
              id: row['last_message_id'].toString(),
              content: row['last_message_preview'] as String? ?? '',
              senderId: row['last_sender_id'].toString(),
              type: MessageType.text,
              createdAt: row['last_message_at'] != null
                  ? DateTime.tryParse(row['last_message_at'].toString()) ?? DateTime.now()
                  : DateTime.now(),
              isRead: true,
            )
          : null,
    );
  }

  /// ConversationDetailResult → DB Row
  Map<String, dynamic> _detailResultToRow(ConversationDetailResult dto) {
    return {
      'id': dto.id,
      'type': dto.type,
      'chat_user_id': dto.chatUserId,
      'title': dto.title,
      'avatar': dto.avatar,
      'last_sender_id': dto.lastSenderId,
      'last_message_id': dto.lastMessageId,
      'last_message_at': dto.lastMessageAt?.toIso8601String(),
      'last_message_preview': dto.lastMessagePreview,
      'unread_count': dto.unreadCount,
      'is_pinned': dto.isPinned ? 1 : 0,
      'is_muted': dto.isMuted ? 1 : 0,
    };
  }

  /// ConversationDetailResult → Conversation（仅用于追加时）
  Conversation _detailResultToConversation(ConversationDetailResult dto) {
    return Conversation(
      id: dto.id.toString(),
      chatUserId: dto.chatUserId.toString(),
      title: dto.title,
      avatar: dto.avatar,
      isGroup: dto.type == 2,
      isPinned: dto.isPinned,
      isMuted: dto.isMuted,
      unreadCount: dto.unreadCount,
      lastMessage: Message(
        id: dto.lastMessageId.toString(),
        content: dto.lastMessagePreview ?? '',
        senderId: dto.lastSenderId.toString(),
        type: MessageType.text,
        createdAt: dto.lastMessageAt ?? DateTime.now(),
        isRead: true,
      ),
    );
  }

  /// 排序：置顶优先，再按最新消息时间降序
  void _sortConversations() {
    _conversations.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      final ta = a.lastMessage?.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final tb = b.lastMessage?.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return tb.compareTo(ta);
    });
  }

  /// 消息类型映射
  MessageType _mapMessageType(int type) {
    switch (type) {
      case 1:
        return MessageType.image;
      case 2:
        return MessageType.voice;
      case 3:
        return MessageType.video;
      case 4:
        return MessageType.file;
      case 9:
        return MessageType.system;
      default:
        return MessageType.text;
    }
  }
}
