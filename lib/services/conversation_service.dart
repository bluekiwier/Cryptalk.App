import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:dio/dio.dart';
import 'database_service.dart';
import 'account_service.dart';
import '../models/conversation.dart';
import '../models/conversation_detail_result.dart';
import '../models/conversation_list_input_dto.dart';
import '../models/conversation_list_result.dart';
import '../models/conversation_keyinfo_result.dart';
import '../utils/time_util.dart';
import '../models/db/conversation_entity.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 会话服务（ChangeNotifier）
/// 策略：本地 DB 优先呈现，后台异步同步网络数据
class ConversationService extends ChangeNotifier {
  static final ConversationService _instance = ConversationService._internal();
  factory ConversationService() => _instance;
  ConversationService._internal();

  final _logger = Logger();
  final _db = DatabaseService();
  final _secureStorage = const FlutterSecureStorage();

  // 内存中的会话列表（排序后）
  List<Conversation> _conversations = [];
  List<Conversation> get conversations => List.unmodifiable(_conversations);

  // 搜索过滤的会话列表
  List<Conversation> _filteredConversations = [];
  List<Conversation> get filteredConversations => List.unmodifiable(_filteredConversations);

  // 是否正在搜索
  bool _isSearching = false;
  bool get isSearching => _isSearching;

  // 搜索关键词
  String _searchKeyword = '';
  String get searchKeyword => _searchKeyword;

  // 是否有更多（网络分页）
  bool _hasMore = false;
  bool get hasMore => _hasMore;

  // 下一页游标
  ConversationListInputDto? _nextCursor;

  /// 冷启动初始化：先加载本地缓存，再后台同步网络
  Future<void> initialize() async {
    await _loadFromLocal();
    // 后台非阻塞同步网络
    // _syncFromNetwork();
    // 后台非阻塞同步会话数据（增量更新）
    syncConversations();
  }

  /// 从本地 DB 加载第一页会话
  Future<void> _loadFromLocal({int limit = 20}) async {
    try {
      final rows = await _db.queryConversations(limit: limit, offset: 0);
      final list = rows.map(_rowToConversation).toList();
      _conversations = list;
      _updateFilteredConversations();
      notifyListeners();
      // _logger.d('本地 DB 加载会话 ${list.length} 条');
    } catch (e) {
      _logger.e('本地加载会话失败: $e');
    }
  }

  /// 后台从网络同步会话列表（首页，不阻塞 UI）
  Future<void> _syncFromNetwork() async {
    try {
      final result = await _fetchConversationList();
      if (result == null) return;
      // 写入本地 DB
      // 遍历 result.list 集合中的每一个元素，将其传递给 _detailResultToRow 函数进行处理，然后将处理后的所有结果收集到一个新的 List（列表）中，并赋值给 rows 变量。
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

  /// 同步会话数据（APP启动时调用）
  /// 读取本地last_sync_conversation_time，调用同步接口，更新本地数据库
  Future<void> syncConversations() async {
    try {
      final lastSyncTimeStr = await _db.getConfig('last_sync_conversation_time');
      final since = lastSyncTimeStr != null ? int.tryParse(lastSyncTimeStr) ?? 0 : 0;

      // _logger.d('开始同步会话数据 since=$since');

      final dio = await AccountService().getDio();
      final response = await dio.get('/api/conversation/sync', queryParameters: {'since': since});

      final responseData = response.data;
      if (responseData != null && responseData['success'] == true) {
        final data = responseData['data'];
        if (data != null) {
          final list = data['list'] as List<dynamic>?;
          if (list != null && list.isNotEmpty) {
            final conversations = list.map((item) => Map<String, dynamic>.from(item)).toList();
            // _logger.i('同步会话数据: $data');
            // await _db.batchUpdateConversations(conversations);
            await _db.upsertConversations(conversations);
            // _logger.d('同步会话数据成功，更新了 ${conversations.length} 条');
          }

          final serverTime = data['serverTime'];
          if (serverTime != null) {
            await _db.setConfig('last_sync_conversation_time', serverTime.toString());
            // _logger.d('已保存同步时间: $serverTime');
          }

          await _loadFromLocal();
        }
      } else {
        _logger.w('同步会话数据失败: ${responseData?['message']}');
      }
    } catch (e) {
      _logger.e('同步会话数据异常: $e');
    }
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
      final result = await _fetchConversationList(cursor: _nextCursor);
      if (result != null) {
        final rows = result.list.map(_detailResultToRow).toList();
        await _db.upsertConversations(rows);
        // 追加到内存列表（去重）
        final newItems = result.list.map(_detailResultToConversation).toList();
        final existingIds = _conversations.map((c) => c.id).toSet();
        final uniqueNewItems = newItems.where((c) => !existingIds.contains(c.id)).toList();
        _conversations = [..._conversations, ...uniqueNewItems];
        _updateFilteredConversations();
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
      await fetchAndCacheConversationDetail(conversationId.toString(), cacheToDb: true);
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
        lastSeqId: old.lastSeqId,
        lastSenderId: senderId.toString(),
        lastMessageId: messageId.toString(),
        lastMessageAt: TimeUtil.parseUtcTime(messageAt),
        lastMessagePreview: messagePreview,
      );
      _conversations[idx] = updated;
      // 将该会话移至顶部（非置顶会话按时间排序）
      _sortConversations();
      _updateFilteredConversations();
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
        lastSeqId: old.lastSeqId,
        lastSenderId: old.lastSenderId,
        lastMessageId: old.lastMessageId,
        lastMessageAt: old.lastMessageAt,
        lastMessagePreview: old.lastMessagePreview,
      );
      _updateFilteredConversations();
      notifyListeners();
    }
  }

  /// 获取单个会话对象（内存优先，DB 次之）
  Future<Conversation?> getConversationById(String id) async {
    // 1. 尝试从内存获取
    final idx = _conversations.indexWhere((c) => c.id == id);
    if (idx >= 0) return _conversations[idx];

    // 2. 尝试从 DB 获取
    final convId = int.tryParse(id);
    if (convId == null) return null;
    final row = await _db.getConversation(convId);
    if (row != null) {
      return _rowToConversation(row);
    }
    return null;
  }

  /// 获取群聊会话密钥信息
  Future<ConversationKeyInfoResult?> _fetchGroupConversationKeyInfo(String conversationId) async {
    try {
      final dio = await AccountService().getDio();

      final response = await dio.post(
        '/api/conversation/key-info',
        data: {'id': conversationId},
        options: Options(extra: {'obfuscate': true}),
      );
      final responseData = response.data;
      if (responseData != null && responseData['success'] == true) {
        final data = responseData['data'];
        if (data != null) return ConversationKeyInfoResult.fromJson(data);
      }
    } catch (e) {
      _logger.e('获取群聊会话密钥信息失败: $e');
    }
    return null;
  }

  /// 获取群聊密钥：先查本地，若无或版本不匹配，则请求网络并更新本地缓存
  Future<ConversationKeyInfoResult?> getGroupKeyWithVersionCheck(
    String conversationId, {
    String? requiredVersion,
  }) async {
    final storageKey = 'group_key_$conversationId';
    final storageVersionKey = 'group_key_version_$conversationId';

    // 检查本地缓存
    try {
      final key = await _secureStorage.read(key: storageKey);
      final versionStr = await _secureStorage.read(key: storageVersionKey);

      if (key != null && versionStr != null) {
        // 如果未指定需校验的版本，或版本一致，直接返回本地缓存
        if (requiredVersion == null || requiredVersion == versionStr) {
          return ConversationKeyInfoResult(id: conversationId, secretKey: key, secretVersion: versionStr);
        }
      }
    } catch (e) {
      _logger.e('读取本地群聊密钥异常: $e');
    }

    // 版本不匹配或无缓存，通过接口获取
    final result = await _fetchGroupConversationKeyInfo(conversationId);
    if (result != null) {
      try {
        await _secureStorage.write(key: storageKey, value: result.secretKey);
        await _secureStorage.write(key: storageVersionKey, value: result.secretVersion);
      } catch (e) {
        _logger.e('缓存本地群聊密钥异常: $e');
      }
    }
    return result;
  }

  // ─────────────────────────────────────────────
  // 私有：分页获取会话列表
  // ─────────────────────────────────────────────
  Future<ConversationListResult?> _fetchConversationList({ConversationListInputDto? cursor}) async {
    try {
      final dio = await AccountService().getDio();

      final response = await dio.post(
        '/api/conversation/list',
        data: (cursor ?? const ConversationListInputDto()).toJson(),
        options: Options(extra: {'obfuscate': true}),
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

  /// 拉取单个会话详情并缓存到本地，同时返回数据
  /// 用于：1. 收到新消息时本地不存在会话 2. 获取会话详情
  Future<ConversationDetailResult?> fetchAndCacheConversationDetail(
    String conversationId, {
    bool cacheToDb = true,
  }) async {
    final detail = await getConversationDetail(conversationId);
    if (detail != null && cacheToDb) {
      await _db.insertConversationIfAbsent(_detailResultToRow(detail));
      _logger.d('缓存会话详情: $conversationId');
    }
    return detail;
  }

  /// 获取会话详情
  /// 返回 ConversationDetailResult 对象
  Future<ConversationDetailResult?> getConversationDetail(String conversationId) async {
    try {
      final dio = await AccountService().getDio();
      final response = await dio.get('/api/conversation/$conversationId/detail');
      final responseData = response.data;
      if (responseData != null && responseData['success'] == true) {
        final data = responseData['data'];
        if (data != null) {
          return ConversationDetailResult.fromJson(data);
        }
      }
      return null;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout) {
        _logger.e('获取会话详情超时: $e');
      } else {
        _logger.e('获取会话详情失败: $e');
      }
      return null;
    } catch (e) {
      _logger.e('获取会话详情异常: $e');
      return null;
    }
  }

  /// 获取会话的聊天消息列表（网络）
  Future<Map<String, dynamic>?> getMessages(dynamic conversationId, {int messageId = 0, int pageSize = 20}) async {
    try {
      final dio = await AccountService().getDio();

      final response = await dio.post(
        '/api/conversation/$conversationId/messages',
        data: {'messageId': messageId, 'pageSize': pageSize},
        options: Options(extra: {'obfuscate': true}),
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

  /// 置顶聊天
  Future<Map<String, dynamic>?> pinTopConversation(String conversationId, int type) async {
    try {
      final dio = await AccountService().getDio();
      final response = await dio.post(
        '/api/conversation/$conversationId/pin-top',
        data: {'type': type},
        options: Options(extra: {'obfuscate': true}),
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
        '/api/conversation/$conversationId/mute',
        data: {'type': type},
        options: Options(extra: {'obfuscate': true}),
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

  /// 创建群组
  /// [userIds] 群成员用户ID列表（不包含当前用户）
  /// 返回创建的会话详情
  Future<ConversationDetailResult?> createGroup(List<String> userIds) async {
    try {
      final dio = await AccountService().getDio();

      final response = await dio.post(
        '/api/conversation/create-group',
        data: {'userIds': userIds},
        options: Options(extra: {'obfuscate': true}),
      );

      final responseData = response.data;
      _logger.d('创建群组响应: $responseData');

      if (responseData['success'] == true && responseData['data'] != null) {
        final data = responseData['data'] as Map<String, dynamic>;
        final conversationDetail = ConversationDetailResult.fromJson(data);

        final row = _conversationDetailToRow(conversationDetail);
        await DatabaseService().insertConversationIfAbsent(row);

        _logger.d('群组会话已写入本地数据库: ${conversationDetail.id}');
        return conversationDetail;
      } else {
        _logger.e('创建群组失败: ${responseData['message']}');
        return null;
      }
    } catch (e) {
      _logger.e('创建群组异常: $e');
      return null;
    }
  }

  Map<String, dynamic> _conversationDetailToRow(ConversationDetailResult dto) {
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

  /// 获取群成员列表
  Future<Map<String, dynamic>?> getGroupMembers(
    String conversationId, {
    int page = 1,
    int pageSize = 30,
    String keyword = '',
  }) async {
    try {
      final dio = await AccountService().getDio();
      final response = await dio.get(
        '/api/conversation/$conversationId/members',
        queryParameters: {'page': page, 'pageSize': pageSize, 'keyword': keyword},
      );
      return response.data;
    } on DioException catch (e) {
      _logger.e('获取群成员列表失败: $e');
      return null;
    } catch (e) {
      _logger.e('获取群成员列表异常: $e');
      return null;
    }
  }

  /// 获取群成员数量
  Future<int> getGroupMemberCount(String conversationId) async {
    try {
      final dio = await AccountService().getDio();
      final response = await dio.get('/api/conversation/$conversationId/members/count');
      final data = response.data;
      if (data != null && data['success'] == true) {
        return data['data'] as int? ?? 0;
      }
      return 0;
    } on DioException catch (e) {
      _logger.e('获取群成员数量失败: $e');
      return 0;
    } catch (e) {
      _logger.e('获取群成员数量异常: $e');
      return 0;
    }
  }

  /// 进入群聊室
  Future<bool> enterGroup(String conversationId) async {
    try {
      final dio = await AccountService().getDio();
      final response = await dio.post('/api/conversation/$conversationId/enter');
      final data = response.data;
      if (data != null && data['success'] == true) {
        _logger.d('进入群聊室成功');
        return true;
      }
      _logger.e('进入群聊室失败: ${data?['message']}');
      return false;
    } on DioException catch (e) {
      _logger.e('进入群聊室失败: $e');
      return false;
    } catch (e) {
      _logger.e('进入群聊室异常: $e');
      return false;
    }
  }

  /// 离开群聊室
  Future<bool> exitGroup(String conversationId) async {
    try {
      final dio = await AccountService().getDio();
      final response = await dio.post('/api/conversation/$conversationId/exit');
      final data = response.data;
      if (data != null && data['success'] == true) {
        _logger.d('离开群聊室成功');
        return true;
      }
      _logger.e('离开群聊室失败: ${data?['message']}');
      return false;
    } on DioException catch (e) {
      _logger.e('离开群聊室失败: $e');
      return false;
    } catch (e) {
      _logger.e('离开群聊室异常: $e');
      return false;
    }
  }

  /// 加入群聊
  Future<({bool success, String message})> joinGroup(String conversationId) async {
    try {
      final dio = await AccountService().getDio();
      final response = await dio.post('/api/conversation/$conversationId/join');
      final responseData = response.data;
      final message = responseData?['message']?.toString() ?? '操作完成';
      if (responseData != null && responseData['success'] == true) {
        return (success: true, message: message);
      } else {
        return (success: false, message: message);
      }
    } on DioException catch (e) {
      _logger.e('加入群聊失败: $e');
      return (success: false, message: '网络错误，请稍后重试');
    } catch (e) {
      _logger.e('加入群聊异常: $e');
      return (success: false, message: '未知错误');
    }
  }

  /// 退出群聊
  Future<({bool success, String message})> quitGroup(String conversationId) async {
    try {
      final dio = await AccountService().getDio();
      final response = await dio.delete('/api/conversation/$conversationId/quit');
      final responseData = response.data;
      final message = responseData?['message']?.toString() ?? '操作完成';
      if (responseData != null && responseData['success'] == true) {
        return (success: true, message: message);
      } else {
        return (success: false, message: message);
      }
    } on DioException catch (e) {
      _logger.e('退出群聊失败: $e');
      return (success: false, message: '网络错误，请稍后重试');
    } catch (e) {
      _logger.e('退出群聊异常: $e');
      return (success: false, message: '未知错误');
    }
  }

  /// 修改群头像
  Future<Map<String, dynamic>?> updateGroupAvatar(String conversationId, String avatar) async {
    try {
      final dio = await AccountService().getDio();
      final response = await dio.post(
        '/api/conversation/$conversationId/change-avatar',
        data: {'avatar': avatar},
        options: Options(extra: {'obfuscate': true}),
      );
      return response.data;
    } on DioException catch (e) {
      _logger.e('修改群头像失败: $e');
      return {'success': false, 'message': '网络错误', 'code': 200};
    } catch (e) {
      _logger.e('修改群头像异常: $e');
      return {'success': false, 'message': '未知错误', 'code': 200};
    }
  }

  /// 修改群名称
  Future<Map<String, dynamic>?> updateGroupName(String conversationId, String name) async {
    try {
      final dio = await AccountService().getDio();
      final response = await dio.post(
        '/api/conversation/$conversationId/change-title',
        data: {'title': name},
        options: Options(extra: {'obfuscate': true}),
      );
      return response.data;
    } on DioException catch (e) {
      _logger.e('修改群名称失败: $e');
      return {'success': false, 'message': '网络错误', 'code': 200};
    } catch (e) {
      _logger.e('修改群名称异常: $e');
      return {'success': false, 'message': '未知错误', 'code': 200};
    }
  }

  /// 修改群公告
  Future<Map<String, dynamic>?> updateGroupAnnouncement(String conversationId, String announcement) async {
    try {
      final dio = await AccountService().getDio();
      final response = await dio.post(
        '/api/conversation/$conversationId/change-announcement',
        data: {'content': announcement},
        options: Options(extra: {'obfuscate': true}),
      );
      return response.data;
    } on DioException catch (e) {
      _logger.e('修改群公告失败: $e');
      return {'success': false, 'message': '网络错误', 'code': 200};
    } catch (e) {
      _logger.e('修改群公告异常: $e');
      return {'success': false, 'message': '网络错误', 'code': 200};
    }
  }

  /// 更新本地会话的群名称（用于WebSocket事件）
  Future<void> updateConversationTitle(String conversationId, String title) async {
    final db = await _db.database;
    await db.update(
      ConversationEntity.tableName,
      {'title': title},
      where: 'id = ?',
      whereArgs: [int.tryParse(conversationId) ?? 0],
    );
    await notifyConversationListChanged();
  }

  /// 发送消息后更新会话信息（发送方专用）
  Future<void> updateConversationAfterSendMessage({
    required int conversationId,
    required int senderId,
    required int messageId,
    required String messageAt,
    required String messagePreview,
    required int messageType,
  }) async {
    // 更新 DB（不增加未读数）
    await _db.updateConversationFromMessage(
      conversationId: conversationId,
      senderId: senderId,
      messageId: messageId,
      messageAt: messageAt,
      messagePreview: messagePreview,
      messageType: messageType,
      updateUnreadCount: false,
    );
    // 通知会话列表刷新
    await notifyConversationListChanged();
  }

  /// 获取我的角色：1=群主，2=管理员，3=成员
  Future<Map<String, dynamic>?> getMyRole(String conversationId) async {
    try {
      final dio = await AccountService().getDio();
      final response = await dio.get('/api/conversation/$conversationId/my-role');
      return response.data;
    } catch (e) {
      _logger.e('获取我的角色失败: $e');
      return {'success': false, 'message': '网络错误', 'code': 200};
    }
  }

  /// 添加群管理员
  Future<Map<String, dynamic>?> addGroupAdmin(String conversationId, dynamic userId) async {
    try {
      final dio = await AccountService().getDio();
      final response = await dio.post(
        '/api/conversation/$conversationId/add-admin',
        data: {'userId': userId},
        options: Options(extra: {'obfuscate': true}),
      );
      return response.data;
    } catch (e) {
      _logger.e('添加群管理员失败: $e');
      return {'success': false, 'message': '网络错误', 'code': 200};
    }
  }

  /// 移除群管理员
  Future<Map<String, dynamic>?> removeGroupAdmin(String conversationId, dynamic userId) async {
    try {
      final dio = await AccountService().getDio();
      final response = await dio.post(
        '/api/conversation/$conversationId/remove-admin',
        data: {'userId': userId},
        options: Options(extra: {'obfuscate': true}),
      );
      return response.data;
    } catch (e) {
      _logger.e('移除群管理员失败: $e');
      return {'success': false, 'message': '网络错误', 'code': 200};
    }
  }

  /// 转让群主
  Future<Map<String, dynamic>?> transferGroupOwner(String conversationId, dynamic userId) async {
    try {
      final dio = await AccountService().getDio();
      final response = await dio.post(
        '/api/conversation/$conversationId/transfer-owner',
        data: {'userId': userId},
        options: Options(extra: {'obfuscate': true}),
      );
      return response.data;
    } catch (e) {
      _logger.e('转让群主失败: $e');
      return {'success': false, 'message': '网络错误', 'code': 200};
    }
  }

  /// 解散群聊
  Future<Map<String, dynamic>?> dissolveGroup(String conversationId) async {
    try {
      final dio = await AccountService().getDio();
      final response = await dio.delete('/api/conversation/$conversationId/dissolve');
      return response.data;
    } catch (e) {
      _logger.e('解散群聊失败: $e');
      return {'success': false, 'message': '网络错误', 'code': 200};
    }
  }

  /// 设置群内禁言
  Future<Map<String, dynamic>?> setGroupMute(String conversationId, dynamic userId, int duration) async {
    try {
      final dio = await AccountService().getDio();
      final response = await dio.post(
        '/api/conversation/$conversationId/set-mute',
        data: {'userId': userId, 'duration': duration},
      );
      return response.data;
    } catch (e) {
      _logger.e('设置群内禁言失败: $e');
      return {'success': false, 'message': '网络错误', 'code': 200};
    }
  }

  /// 取消群内禁言
  Future<Map<String, dynamic>?> cancelGroupMute(String conversationId, dynamic userId) async {
    try {
      final dio = await AccountService().getDio();
      final response = await dio.post(
        '/api/conversation/$conversationId/cancel-mute',
        data: {'userId': userId},
        options: Options(extra: {'obfuscate': true}),
      );
      return response.data;
    } catch (e) {
      _logger.e('取消群内禁言失败: $e');
      return {'success': false, 'message': '网络错误', 'code': 200};
    }
  }

  /// 踢出群成员
  Future<Map<String, dynamic>?> removeGroupMember(String conversationId, dynamic userId) async {
    try {
      final dio = await AccountService().getDio();
      final response = await dio.post(
        '/api/conversation/$conversationId/remove-member',
        data: {'userId': userId},
        options: Options(extra: {'obfuscate': true}),
      );
      return response.data;
    } catch (e) {
      _logger.e('踢出群成员失败: $e');
      return {'success': false, 'message': '网络错误', 'code': 200};
    }
  }

  /// 邀请成员加入群聊
  Future<Map<String, dynamic>?> addGroupMember(String conversationId, String account) async {
    try {
      final dio = await AccountService().getDio();
      final response = await dio.post(
        '/api/conversation/$conversationId/add-member',
        data: {'account': account},
        options: Options(extra: {'obfuscate': true}),
      );
      return response.data;
    } catch (e) {
      _logger.e('邀请成员失败: $e');
      return {'success': false, 'message': '网络错误', 'code': 200};
    }
  }

  /// 禁言成员
  Future<Map<String, dynamic>?> muteMember(String conversationId, dynamic userId, int minutes) async {
    try {
      final dio = await AccountService().getDio();
      final response = await dio.post(
        '/api/conversation/$conversationId/mute-member',
        data: {'userId': userId, 'minutes': minutes},
      );
      return response.data;
    } catch (e) {
      _logger.e('禁言成员失败: $e');
      return {'success': false, 'message': '网络错误', 'code': 200};
    }
  }

  /// 解除成员禁言
  Future<Map<String, dynamic>?> unmuteMember(String conversationId, dynamic userId) async {
    try {
      final dio = await AccountService().getDio();
      final response = await dio.post('/api/conversation/$conversationId/unmute-member', data: {'userId': userId});
      return response.data;
    } catch (e) {
      _logger.e('解除禁言失败: $e');
      return {'success': false, 'message': '网络错误', 'code': 200};
    }
  }

  /// 开启全体禁言
  Future<Map<String, dynamic>?> muteAll(String conversationId) async {
    try {
      final dio = await AccountService().getDio();
      final response = await dio.post('/api/conversation/$conversationId/mute-all');
      return response.data;
    } catch (e) {
      _logger.e('开启全体禁言失败: $e');
      return {'success': false, 'message': '网络错误', 'code': 200};
    }
  }

  /// 关闭全体禁言
  Future<Map<String, dynamic>?> unmuteAll(String conversationId) async {
    try {
      final dio = await AccountService().getDio();
      final response = await dio.post('/api/conversation/$conversationId/unmute-all');
      return response.data;
    } catch (e) {
      _logger.e('关闭全体禁言失败: $e');
      return {'success': false, 'message': '网络错误', 'code': 200};
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
      lastSeqId: row['last_seq_id']?.toString() ?? '',
      lastSenderId: row['last_sender_id'].toString(),
      lastMessageId: row['last_message_id'].toString(),
      lastMessageAt: TimeUtil.parseUtcTime(row['last_message_at']?.toString()),
      lastMessagePreview: row['last_message_preview'] as String? ?? '',
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
      'last_seq_id': dto.lastSeqId,
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
      lastSeqId: dto.lastSeqId,
      lastSenderId: dto.lastSenderId,
      lastMessageId: dto.lastMessageId,
      lastMessageAt: dto.lastMessageAt,
      lastMessagePreview: dto.lastMessagePreview ?? '',
    );
  }

  /// 排序：置顶优先，再按最新消息时间降序
  void _sortConversations() {
    _conversations.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      final ta = a.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final tb = b.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return tb.compareTo(ta);
    });
  }

  /// 同步搜索过滤列表
  void _updateFilteredConversations() {
    if (_isSearching && _searchKeyword.isNotEmpty) {
      final lowerKeyword = _searchKeyword.toLowerCase();
      _filteredConversations = _conversations.where((c) {
        return c.title.toLowerCase().contains(lowerKeyword) || c.chatUserId.contains(lowerKeyword);
      }).toList();
    } else {
      _filteredConversations = List.from(_conversations);
    }
  }

  /// 搜索会话
  /// [keyword] 搜索关键词
  void searchConversations(String keyword) {
    _searchKeyword = keyword;
    if (keyword.isEmpty) {
      _isSearching = false;
      _filteredConversations = _conversations;
    } else {
      _isSearching = true;
      final lowerKeyword = keyword.toLowerCase();
      _filteredConversations = _conversations.where((c) {
        return c.title.toLowerCase().contains(lowerKeyword) || c.chatUserId.contains(lowerKeyword);
      }).toList();
    }
    notifyListeners();
  }

  /// 清除搜索
  void clearSearch() {
    _searchKeyword = '';
    _isSearching = false;
    _filteredConversations = _conversations;
    notifyListeners();
  }
}
