import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import 'account_service.dart';
import 'database_service.dart';
import 'conversation_service.dart';
import '../models/db/conversation_entity.dart';
import '../models/db/conversation_message_entity.dart';
import '../models/send_message_result.dart';
import '../utils/time_util.dart';
import 'notification_service.dart';

/// 统一消息模型
class MessageResult {
  final String type;
  final String event;
  final int timestamp;
  final Map<String, dynamic>? data;
  final Map<String, dynamic>? extra;

  MessageResult({required this.type, required this.event, required this.timestamp, this.data, this.extra});

  factory MessageResult.fromJson(Map<String, dynamic> json) {
    return MessageResult(
      type: json['type'],
      event: json['event'],
      timestamp: json['timestamp'],
      data: json['data'],
      extra: json['extra'],
    );
  }
}

/// 聊天消息结构
class ChatMessageDto {
  // 会话ID
  final String conversationId;
  // 会话类型: 1=私聊,2=群聊,3=广播
  final int conversationType;
  // 发送者ID
  final String senderId;
  // 接收对象（用户ID或群ID）
  final String receiverId;
  // 服务器时间
  final DateTime time;
  // 实际消息体
  final ConversationMessagePayload payload;
  // 是否需要回执
  final bool isReceipt;

  ChatMessageDto({
    required this.conversationId,
    required this.conversationType,
    required this.senderId,
    required this.receiverId,
    required this.time,
    required this.payload,
    required this.isReceipt,
  });

  factory ChatMessageDto.fromJson(Map<String, dynamic> json) {
    return ChatMessageDto(
      conversationId: json['conversationId'] ?? '',
      conversationType: json['conversationType'] ?? 0,
      senderId: json['senderId'] ?? '',
      receiverId: json['receiverId'] ?? '',
      time: TimeUtil.parseUtcTime(json['time']?.toString()) ?? DateTime.now(),
      payload: ConversationMessagePayload.fromJson(json['payload'] ?? {}),
      isReceipt: json['isReceipt'] ?? false,
    );
  }
}

/// 实际消息体
class ConversationMessagePayload {
  // 消息ID
  final String id;

  // 会话ID
  final String conversationId;

  // 会话类型: 1-私聊,2-群聊
  final int conversationType;

  // 消息顺序号
  final String seqId;

  // 发送者ID
  final String senderId;

  // 发送者昵称
  final String? senderNickname;

  // 发送者头像
  final String? senderAvatar;

  // 引用会话消息ID
  final String quoteId;

  // 加密后的消息内容（二进制）
  final String content;

  // 消息类型：0=文字,1=图片,2=语音,3=视频,4=文件,5=位置,6=名片,7=红包,8=系统通知,9=广播,10=群通知消息
  final int type;

  // 消息状态：0=正常,1=撤回,2=删除
  final int status;

  // 发送时间
  final String createdAt;

  ConversationMessagePayload({
    required this.id,
    required this.conversationId,
    required this.conversationType,
    required this.seqId,
    required this.senderId,
    this.senderNickname,
    this.senderAvatar,
    required this.quoteId,
    required this.content,
    required this.type,
    required this.status,
    required this.createdAt,
  });

  factory ConversationMessagePayload.fromJson(Map<String, dynamic> json) {
    return ConversationMessagePayload(
      id: json['id'] ?? '',
      conversationId: json['conversationId'] ?? '',
      conversationType: json['conversationType'] ?? 0,
      seqId: json['seqId'] ?? '',
      senderId: json['senderId'] ?? '',
      senderNickname: json['senderNickname']?.toString(),
      senderAvatar: json['senderAvatar']?.toString(),
      quoteId: json['quoteId'] ?? '',
      content: json['content'] ?? '',
      type: json['type'] ?? 0,
      status: json['status'] ?? 0,
      createdAt: json['createdAt'] ?? '',
    );
  }
}

/// 删除消息Dto
class DeleteMessageDto {
  // 会话ID
  final String conversationId;
  // 删除消息ID
  final String messageId;

  DeleteMessageDto({required this.conversationId, required this.messageId});

  factory DeleteMessageDto.fromJson(Map<String, dynamic> json) {
    return DeleteMessageDto(conversationId: json['conversationId'] ?? '', messageId: json['messageId'] ?? '');
  }
}

/// 聊天服务 - 负责 WebSocket 的连接、消息收发与重连机制
class ChatService extends ChangeNotifier {
  static final ChatService _instance = ChatService._internal();
  factory ChatService() => _instance;
  ChatService._internal();

  final _logger = Logger();
  // final httpService = HttpService();
  WebSocketChannel? _channel;
  bool _isConnected = false;
  bool _isConnecting = false;
  Timer? _heartbeatTimer;
  // 获取当前连接状态
  bool get isConnected => _isConnected;
  // 添加手动断开标志
  bool _isManuallyDisconnected = false;
  // 重连尝试次数
  int _reconnectAttempts = 0;
  // 最大重连尝试次数
  static const int maxReconnectAttempts = 5;
  static const int baseReconnectDelay = 3; // 基础重连延迟（秒）

  // 存储接收到的消息
  final List<ChatMessageDto> _receivedMessages = [];

  // 当前打开的聊天会话ID
  String? _currentChatConversationId;

  /// 设置当前打开的聊天会话ID
  void setCurrentChatConversation(String? conversationId) {
    _currentChatConversationId = conversationId;
    _logger.d('当前聊天会话ID设置为: $conversationId');
  }

  /// 检查是否在指定会话的聊天页面
  bool isInChatPage(String conversationId) {
    return _currentChatConversationId == conversationId;
  }

  /// 检查并重新连接 WebSocket（用于 APP 重新打开时）
  Future<void> checkAndReconnect() async {
    if (!_isConnected) {
      _logger.i('APP 打开，检查并重新连接 WebSocket');
      await connect();
    }
  }

  /// 连接 WebSocket
  Future<void> connect() async {
    _isManuallyDisconnected = false;
    if (_isConnected || _isConnecting) return;
    _isConnecting = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final wsServer = prefs.getString('wsServer');

      if (wsServer == null || wsServer.isEmpty) {
        _logger.w('没有获取到 WebSocket 服务器地址');
        return;
      }

      // 直接使用地址，如果重连获取的新地址自带 token，则无需再次拼接
      final uri = Uri.parse(wsServer);

      _logger.i('正在连接 WebSocket: $uri');

      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready; // 等待连接就绪

      _isConnected = true;
      notifyListeners();
      _logger.i('WebSocket 已连接');
      _startHeartbeat();

      _channel!.stream.listen(
        (message) {
          _handleMessage(message);
        },
        onDone: () {
          _logger.w('WebSocket 连接已关闭');
          _isConnected = false;
          _stopHeartbeat();
          notifyListeners();
          // 只有非手动断开时才重连
          if (!_isManuallyDisconnected) {
            _reconnect();
          }
        },
        onError: (error) {
          _logger.e('WebSocket 错误: $error');
          _isConnected = false;
          _stopHeartbeat();
          notifyListeners();
        },
      );
    } catch (e) {
      _logger.e('WebSocket 连接失败: $e');
      _isConnected = false;
      _stopHeartbeat();
      notifyListeners();
      _reconnect();
    } finally {
      _isConnecting = false;
    }
  }

  /// 处理接收到的消息
  void _handleMessage(dynamic message) {
    // 处理非JSON消息（如心跳响应）
    if (message is String) {
      if (message == 'pong') {
        return;
      }

      _logger.i('收到 WebSocket 消息: $message');

      // 尝试解析JSON
      try {
        final Map<String, dynamic> jsonMessage = json.decode(message);
        final MessageResult messageResult = MessageResult.fromJson(jsonMessage);

        // 根据消息类型处理
        switch (messageResult.type) {
          case 'chat':
            handleChatEvent(messageResult);
            break;
          case 'group':
            _handleGroupEvent(messageResult);
            break;
          case 'user':
            _handleUserEvent(messageResult);
            break;
          case 'system':
            _handleSystemEvent(messageResult);
            break;
          default:
            _logger.w('未知消息类型: ${messageResult.type}');
        }
      } catch (e) {
        _logger.e('消息解析失败: $e');
      }
    } else {
      _logger.w('未知消息格式: $message');
    }
  }

  void handleChatEvent(MessageResult message) {
    switch (message.event) {
      case "message":
        final chat = ChatMessageDto.fromJson(message.data!);
        _handleChatMessage(chat);
        break;

      case "delete":
        final del = DeleteMessageDto.fromJson(message.data!);
        _handleDeleteMessage(del);
        break;

      // case "recall":
      //   final recall = RecallMessageDto.fromJson(message.data!);
      //   _handleRecallMessage(recall);
      //   break;

      // case "ack":
      //   handleAck(message.data!);
      //   break;
    }
  }

  /// 处理聊天消息：写 DB + 更新会话缓存 + 触发 UI 局部刷新
  void _handleChatMessage(ChatMessageDto message) {
    final content = message.payload.content;
    _logger.i(
      '收到聊天消息: conversationId=${message.conversationId}, type=${message.payload.type}, content=${content.length > 100 ? content.substring(0, 100) : content}...',
    );
    // 存内存（用于聊天详情页读取）
    // 避免重复添加相同消息
    final isDuplicate = _receivedMessages.any((msg) => msg.payload.id == message.payload.id);
    if (!isDuplicate) {
      _receivedMessages.add(message);
      // 按时间升序排列，确保新消息在正确的位置
      _receivedMessages.sort((a, b) => a.time.compareTo(b.time));

      // 如果当前不在该会话页面，且不是自己发送的消息，则显示通知
      final currentUserId = AccountService().currentUser?.id;
      if (!isInChatPage(message.conversationId) && message.senderId != currentUserId) {
        NotificationService().showChatNotification(
          id: message.payload.id.hashCode,
          title: message.payload.senderNickname ?? '新消息',
          body: _getMessagePreview(message.payload.content, message.payload.type),
          payload: message.conversationId,
        );
      }
    }

    final payload = message.payload;
    final convId = int.tryParse(message.conversationId) ?? 0;
    if (convId == 0) {
      _logger.w('conversationId 无效，跳过 DB 写入');
      notifyListeners();
      return;
    }

    final msgId = int.tryParse(payload.id) ?? 0;
    final senderId = int.tryParse(payload.senderId) ?? 0;
    final createdAt = payload.createdAt;

    // 异步写 DB，不阻塞消息处理
    Future(() async {
      // 1. 写消息表
      await DatabaseService().insertMessage({
        'id': msgId,
        'conversation_id': convId,
        'conversation_type': payload.conversationType,
        'sender_id': senderId,
        'sender_nickname': payload.senderNickname,
        'sender_avatar': payload.senderAvatar,
        'quote_id': int.tryParse(payload.quoteId) ?? 0,
        'content': payload.content,
        'type': payload.type,
        'status': payload.status,
        'seq_id': int.tryParse(payload.seqId) ?? 0,
        'created_at': createdAt,
      });

      String messagePreview = payload.content;
      if (payload.type == 1) {
        messagePreview = '[图片]';
      } else if (payload.type == 2) {
        messagePreview = '[语音]';
      } else if (payload.type == 3) {
        messagePreview = '[视频]';
      } else if (payload.type == 4) {
        messagePreview = '[文件]';
      } else if (payload.type == 5) {
        messagePreview = '[位置]';
      } else if (payload.type == 6) {
        messagePreview = '[名片]';
      } else if (payload.type == 7) {
        messagePreview = '[红包]';
      }
      // 2. 更新会话缓存（unread_count + 1，最新消息）
      await ConversationService().onNewMessage(
        conversationId: convId,
        senderId: senderId,
        messageId: msgId,
        messageAt: createdAt,
        messagePreview: messagePreview,
        messageType: payload.type,
        isInChatPage: isInChatPage(convId.toString()),
      );
    });

    notifyListeners();
  }

  /// 处理删除消息
  /// 1. 将本地数据库消息表 messages 中的对应消息的 status 设置为已删除(2)
  /// 2. 如果删除的消息是会话的最后一条消息，则更新会话表中的 last_message_id, last_message_at, last_message_preview, last_sender_id 为最新消息信息
  /// 3. 从内存中的消息列表移除对应消息，并通知 UI 更新
  void _handleDeleteMessage(DeleteMessageDto message) {
    _logger.i('收到删除消息: messageId=${message.messageId}, conversationId=${message.conversationId}');
    // 直接使用字符串 ID，不转换为 int，避免大数问题
    final msgIdStr = message.messageId;
    final convId = int.tryParse(message.conversationId) ?? 0;

    _logger.i('使用字符串 msgId=$msgIdStr, convId=$convId');

    if (msgIdStr.isEmpty || convId == 0) return;

    // 异步执行数据库操作，避免阻塞主线程
    Future(() async {
      final dbService = DatabaseService();
      final db = await dbService.database;

      // 先查询一下这条消息是否存在 - 使用字符串 ID 查询
      final existingMessages = await db.query(
        ConversationMessageEntity.tableName,
        where: '${ConversationMessageEntity.id} = ?',
        whereArgs: [msgIdStr],
      );
      _logger.i('查询到的消息数量: ${existingMessages.length}');
      if (existingMessages.isNotEmpty) {
        _logger.i('消息当前状态: ${existingMessages.first[ConversationMessageEntity.status]}');
        _logger.i('消息 ID 类型: ${existingMessages.first[ConversationMessageEntity.id].runtimeType}');
      }

      // 1. 将本地数据库消息表 messages 中的对应消息的 status 设置为已删除(2)
      final updateCount = await db.update(
        ConversationMessageEntity.tableName,
        {ConversationMessageEntity.status: 2},
        where: '${ConversationMessageEntity.id} = ?',
        whereArgs: [msgIdStr],
      );
      _logger.i('更新的行数: $updateCount');

      // 2. 查询会话表，获取当前会话信息
      final conversationResult = await db.query(
        ConversationEntity.tableName,
        where: '${ConversationEntity.id} = ?',
        whereArgs: [convId],
      );

      // 如果会话存在
      if (conversationResult.isNotEmpty) {
        final conversation = conversationResult.first;
        final lastMessageId = conversation[ConversationEntity.lastMessageId];

        // 判断删除的消息是否为会话的最后一条消息 - 需要处理字符串比较
        bool isLastMessage = false;
        if (lastMessageId != null) {
          if (lastMessageId is int) {
            // 尝试将 msgIdStr 解析为 int 进行比较
            final parsedMsgId = int.tryParse(msgIdStr);
            isLastMessage = parsedMsgId != null && parsedMsgId == lastMessageId;
          } else {
            // 直接字符串比较
            isLastMessage = lastMessageId.toString() == msgIdStr;
          }
        }

        _logger.i('是否是最后一条消息: $isLastMessage');

        if (isLastMessage) {
          // 查询该会话中未删除的最新一条消息
          final latestMessages = await db.query(
            ConversationMessageEntity.tableName,
            where: '${ConversationMessageEntity.conversationId} = ? AND ${ConversationMessageEntity.status} != 2',
            whereArgs: [convId],
            orderBy: '${ConversationMessageEntity.seqId} DESC, ${ConversationMessageEntity.createdAt} DESC',
            limit: 1,
          );

          // 如果还有未删除的消息，则更新会话的最后一条消息信息
          if (latestMessages.isNotEmpty) {
            final latestMessage = latestMessages.first;
            final newLastSeqId = latestMessage[ConversationMessageEntity.seqId] as int;
            final newLastMessageId = latestMessage[ConversationMessageEntity.id];
            final newLastMessageAt = latestMessage[ConversationMessageEntity.createdAt] as String;
            final newLastMessagePreview = _truncate(
              latestMessage[ConversationMessageEntity.content] as String? ?? '',
              50,
            );
            final newLastSenderId = latestMessage[ConversationMessageEntity.senderId] as int;

            // 处理 newLastMessageId，确保它是 int 类型
            final int? newLastMessageIdInt;
            if (newLastMessageId is int) {
              newLastMessageIdInt = newLastMessageId;
            } else {
              newLastMessageIdInt = int.tryParse(newLastMessageId.toString());
            }

            await db.update(
              ConversationEntity.tableName,
              {
                ConversationEntity.lastSeqId: newLastSeqId,
                ConversationEntity.lastMessageId: newLastMessageIdInt ?? 0,
                ConversationEntity.lastMessageAt: newLastMessageAt,
                ConversationEntity.lastMessagePreview: newLastMessagePreview,
                ConversationEntity.lastSenderId: newLastSenderId,
                ConversationEntity.updatedAt: DateTime.now().toUtc().toString(),
              },
              where: '${ConversationEntity.id} = ?',
              whereArgs: [convId],
            );
          } else {
            // 如果该会话所有消息都已删除，则将会话的最后一条消息信息置空
            await db.update(
              ConversationEntity.tableName,
              {
                ConversationEntity.lastSeqId: 0,
                ConversationEntity.lastMessageId: 0,
                ConversationEntity.lastMessageAt: '',
                ConversationEntity.lastMessagePreview: '',
                ConversationEntity.lastSenderId: 0,
                ConversationEntity.updatedAt: DateTime.now().toUtc().toString(),
              },
              where: '${ConversationEntity.id} = ?',
              whereArgs: [convId],
            );
          }
        }
      }

      // 3. 不从内存中的消息列表移除对应消息，只更新数据库中的状态
      // 这样引用该消息的其他消息（如引用消息）仍然可以通过 _messages 列表找到被引用的消息
      // 消息的实际内容会在 UI 刷新时从数据库读取（status=2 表示已删除）
      // 通知 UI 更新
      _logger.i('通知 UI 更新');
      notifyListeners();
    });
  }

  /// 截断字符串到指定长度，超过部分用省略号替代
  String _truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }

  /// 获取指定会话的消息（按时间升序排列）
  List<ChatMessageDto> getMessagesForConversation(String conversationId) {
    final messages = _receivedMessages.where((msg) => msg.conversationId == conversationId).toList();
    // 按时间升序排列，最新消息在最底部
    messages.sort((a, b) => a.time.compareTo(b.time));
    return List.unmodifiable(messages);
  }

  /// 清空消息列表
  void clearMessages() {
    _receivedMessages.clear();
  }

  /// 处理用户事件
  void _handleUserEvent(MessageResult message) {
    _logger.i('处理用户事件: ${message.data}');
    // 处理用户事件
    notifyListeners();
  }

  /// 处理系统消息
  void _handleSystemEvent(MessageResult message) {
    _logger.i('处理系统消息: ${message.data}');
    // 处理系统通知
    notifyListeners();
  }

  /// 处理群组消息
  void _handleGroupEvent(MessageResult message) {
    _logger.i('处理群组消息: ${message.data}');
    switch (message.event) {
      case "message":
        final chat = ChatMessageDto.fromJson(message.data!);
        _handleChatMessage(chat);
        break;
      case "delete":
        final del = DeleteMessageDto.fromJson(message.data!);
        _handleDeleteMessage(del);
        break;
      case "change_title":
        _handleChangeTitleEvent(message.data!);
        break;
      case "join":
        _handleJoinEvent(message.data!);
        break;
      case "quit":
        _handleQuitEvent(message.data!);
        break;
    }
  }

  /// 处理群名称变更事件
  void _handleChangeTitleEvent(Map<String, dynamic> data) async {
    final conversationId = data['conversationId']?.toString();
    final title = data['title']?.toString();
    if (conversationId != null && title != null) {
      _logger.i('收到群名称变更: conversationId=$conversationId, title=$title');
      await ConversationService().updateConversationTitle(conversationId, title);
      if (isInChatPage(conversationId)) {
        notifyListeners();
      }
    }
  }

  /// 处理加入群聊事件
  void _handleJoinEvent(Map<String, dynamic> data) async {
    final conversationId = data['conversationId']?.toString();
    final payload = data['payload'];
    if (conversationId != null && payload != null) {
      _logger.i('收到加入群聊事件: conversationId=$conversationId');
      await _handleGroupNotifyMessage(conversationId, payload);
      if (isInChatPage(conversationId)) {
        notifyListeners();
      }
    }
  }

  /// 处理退出群聊事件
  void _handleQuitEvent(Map<String, dynamic> data) async {
    final conversationId = data['conversationId']?.toString();
    final payload = data['payload'];
    if (conversationId != null && payload != null) {
      _logger.i('收到退出群聊事件: conversationId=$conversationId');
      await _handleGroupNotifyMessage(conversationId, payload);
      if (isInChatPage(conversationId)) {
        notifyListeners();
      }
    }
  }

  /// 处理群通知消息（加入/退出群等）
  Future<void> _handleGroupNotifyMessage(String conversationId, Map<String, dynamic> payload) async {
    final msgId = int.tryParse(payload['id']?.toString() ?? '') ?? 0;
    final senderId = int.tryParse(payload['senderId']?.toString() ?? '') ?? 0;
    final content = payload['content']?.toString() ?? '';
    final createdAtStr = payload['createdAt']?.toString() ?? DateTime.now().toUtc().toIso8601String();
    final convId = int.tryParse(conversationId) ?? 0;

    if (msgId == 0 || convId == 0) {
      _logger.w('群通知消息无效，跳过处理');
      return;
    }

    final notifyMessage = ChatMessageDto(
      conversationId: conversationId,
      conversationType: 2,
      senderId: senderId.toString(),
      receiverId: conversationId,
      time: TimeUtil.parseUtcTime(createdAtStr) ?? DateTime.now(),
      payload: ConversationMessagePayload(
        id: msgId.toString(),
        conversationId: conversationId,
        conversationType: 2,
        seqId: payload['seqId']?.toString() ?? '',
        senderId: senderId.toString(),
        senderNickname: payload['senderNickname']?.toString(),
        senderAvatar: payload['senderAvatar']?.toString(),
        quoteId: '0',
        content: content,
        type: int.tryParse(payload['type']?.toString() ?? '10') ?? 10,
        status: int.tryParse(payload['status']?.toString() ?? '0') ?? 0,
        createdAt: createdAtStr,
      ),
      isReceipt: false,
    );

    final isDuplicate = _receivedMessages.any((msg) => msg.payload.id == notifyMessage.payload.id);
    if (!isDuplicate) {
      _receivedMessages.add(notifyMessage);
      _receivedMessages.sort((a, b) => a.time.compareTo(b.time));

      // 显示群通知消息
      final currentUserId = AccountService().currentUser?.id;
      if (!isInChatPage(conversationId) && senderId.toString() != currentUserId) {
        NotificationService().showChatNotification(
          id: notifyMessage.payload.id.hashCode,
          title: '群通知',
          body: content,
          payload: conversationId,
        );
      }
    }

    Future(() async {
      await DatabaseService().insertMessage({
        'id': msgId,
        'conversation_id': convId,
        'conversation_type': 2,
        'sender_id': senderId,
        'sender_nickname': payload['senderNickname'] ?? '',
        'sender_avatar': payload['senderAvatar'] ?? '',
        'quote_id': 0,
        'content': content,
        'type': notifyMessage.payload.type,
        'status': notifyMessage.payload.status,
        'seq_id': int.tryParse(payload['seqId']?.toString() ?? '') ?? 0,
        'created_at': createdAtStr,
      });

      await ConversationService().onNewMessage(
        conversationId: convId,
        senderId: senderId,
        messageId: msgId,
        messageAt: createdAtStr,
        messagePreview: _getMessagePreview(content, notifyMessage.payload.type),
        messageType: notifyMessage.payload.type,
        isInChatPage: isInChatPage(conversationId),
      );
    });
  }

  String _getMessagePreview(String content, int type) {
    if (type == 1) {
      return '[图片]';
    } else if (type == 2) {
      return '[语音]';
    } else if (type == 3) {
      return '[视频]';
    } else if (type == 4) {
      return '[文件]';
    } else if (type == 5) {
      return '[位置]';
    } else if (type == 6) {
      return '[名片]';
    } else if (type == 7) {
      return '[红包]';
    }
    return content;
  }

  /// 发送消息
  void sendMessage(String message) {
    if (_channel != null && _isConnected) {
      _channel!.sink.add(message);
      _logger.d('发送 WebSocket 消息: $message');
    } else {
      _logger.w('WebSocket 未连接，无法发送消息');
    }
  }

  /// 断线重连
  void _reconnect() {
    if (_reconnectAttempts >= maxReconnectAttempts) {
      _logger.e('重连次数达到上限，停止重连');
      _reconnectAttempts = 0; // 重置尝试次数
      return;
    }

    _reconnectAttempts++;
    // 指数退避策略：3s, 6s, 12s, 24s...
    int delaySeconds = baseReconnectDelay * (1 << (_reconnectAttempts - 1));
    // 最大延迟限制为60秒
    if (delaySeconds > 60) delaySeconds = 60;
    _logger.i('断线重连: $delaySeconds秒后尝试重新获取地址并连接 WebSocket... (第$_reconnectAttempts次)');

    Future.delayed(Duration(seconds: delaySeconds), () async {
      if (!_isConnected) {
        await _fetchWsServerAndConnect();
      } else {
        _reconnectAttempts = 0; // 重连成功，重置计数
      }
    });
  }

  /// 获取新的 WebSocket 服务地址并连接
  Future<void> _fetchWsServerAndConnect() async {
    try {
      final currentUser = AccountService().currentUser;
      if (currentUser == null) {
        _logger.w('用户未登录，停止获取 WebSocket 地址');
        return;
      }

      final dio = await AccountService().getDio();
      final response = await dio.post('/api/chat/create-server-url');
      final responseData = response.data;

      if (responseData != null && responseData['success'] == true) {
        final serverUrl = responseData['data']?.toString();
        if (serverUrl != null && serverUrl.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('wsServer', serverUrl);
          await connect();
          _reconnectAttempts = 0; // 重连成功，重置计数
        }
      } else {
        _logger.e('获取 WebSocket 地址失败: ${responseData?['message']}');
        // 获取地址失败，继续重连
        _reconnect();
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        _logger.w('获取 WebSocket 地址收到 401，停止重连（token 已失效）');
        return;
      } else if (e.type == DioExceptionType.connectionTimeout) {
        _logger.e('获取 WebSocket 地址超时（可能是服务重启）: $e');
        // 超时继续重连
        _reconnect();
      } else {
        _logger.e('获取 WebSocket 地址异常: $e');
        // 其他异常也继续重连
        _reconnect();
      }
    } catch (e) {
      _logger.e('获取 WebSocket 地址异常: $e');
      // 通用异常也继续重连
      _reconnect();
    }
  }

  /// 发送私聊消息（通过 HTTP API）
  /// [conversationId] 会话 ID
  /// [receiverId] 接收者 ID
  /// [message] 消息内容
  /// [quoteId] 引用的消息 ID
  /// [type] 消息类型：0=文字,1=图片,2=语音,3=视频,4=文件,5=表情,6=位置,7=名片,8=红包,9=系统通知
  Future<SendMessageResult> sendPrivateMessage({
    required dynamic conversationId,
    required dynamic receiverId,
    required String message,
    String? quoteId,
    int type = 0,
  }) async {
    try {
      final dio = await AccountService().getDio();

      final data = <String, dynamic>{
        'conversationId': conversationId.toString(),
        'receiverId': receiverId.toString(),
        'message': message,
        'type': type,
      };

      if (quoteId != null) {
        data['quoteId'] = int.tryParse(quoteId) ?? quoteId;
      }

      final response = await dio.post('/api/chat/send-private-message', data: data);

      final responseData = response.data;
      if (responseData != null && responseData['success'] == true) {
        final messageData = responseData['data'];
        return SendMessageResult(success: true, messageId: messageData?['id']?.toString(), messageData: messageData);
      } else {
        _logger.e('发送私聊消息失败：${responseData?['message']}');
        return SendMessageResult(success: false, message: responseData?['message'] ?? '发送失败');
      }
    } catch (e) {
      _logger.e('发送私聊消息异常：$e');
      return SendMessageResult(success: false, message: '网络异常');
    }
  }

  /// 发送群聊消息（通过 HTTP API）
  /// [conversationId] 会话 ID
  /// [message] 消息内容
  /// [quoteId] 引用的消息 ID
  /// [type] 消息类型：0=文字,1=图片,2=语音,3=视频,4=文件,5=位置,6=名片,7=红包,8=系统通知,9=广播,10=群通知消息
  Future<SendMessageResult> sendGroupMessage({
    required dynamic conversationId,
    required String message,
    String? quoteId,
    int type = 0,
  }) async {
    try {
      final dio = await AccountService().getDio();

      final Map<String, dynamic> data = {'conversationId': conversationId.toString(), 'message': message, 'type': type};

      if (quoteId != null) {
        data['quoteId'] = int.tryParse(quoteId) ?? quoteId;
      }

      final response = await dio.post('/api/chat/send-group-message', data: data);

      final responseData = response.data;
      if (responseData != null && responseData['success'] == true) {
        final messageData = responseData['data'];
        return SendMessageResult(success: true, messageId: messageData?['id']?.toString(), messageData: messageData);
      } else {
        _logger.e('发送群聊消息失败: ${responseData?['message']}');
        return SendMessageResult(success: false, message: responseData?['message'] ?? '发送失败');
      }
    } catch (e) {
      _logger.e('发送群聊消息异常: $e');
      return SendMessageResult(success: false, message: '网络异常');
    }
  }

  /// 断开连接（例如登出时调用）
  void disconnect() {
    _isManuallyDisconnected = true;
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
    _stopHeartbeat();
    notifyListeners();
    _logger.i('手动断开 WebSocket');
  }

  /// 启动心跳机制
  void _startHeartbeat() {
    // 停止之前的心跳（如果存在）
    _stopHeartbeat();

    // 每30秒发送一次心跳
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _sendHeartbeat();
    });
    _logger.i('心跳机制已启动');
  }

  /// 停止心跳机制
  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// 发送心跳消息
  void _sendHeartbeat() {
    if (_channel != null && _isConnected) {
      try {
        // 发送一个简单的心跳消息
        _channel!.sink.add('ping');
        //_logger.d('发送心跳消息: ping');
      } catch (e) {
        _logger.e('发送心跳失败: $e');
        _isConnected = false;
        _stopHeartbeat();
        notifyListeners();
        _reconnect();
      }
    }
  }
}
