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
      time: DateTime.parse(json['time'] ?? ''),
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

  // 发送者ID
  final String senderId;

  // 引用会话消息ID
  final String quoteId;

  // 加密后的消息内容（二进制）
  final String content;

  // 消息类型：0=文字,1=图片,2=语音,3=视频,4=文件,5=表情,6=位置,7=名片,8=红包,9=系统通知,10=撤回
  final int type;

  // 消息状态：0=正常,1=撤回,2=删除
  final int status;

  // 发送时间
  final String createdAt;

  ConversationMessagePayload({
    required this.id,
    required this.conversationId,
    required this.conversationType,
    required this.senderId,
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
      senderId: json['senderId'] ?? '',
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
    // _logger.i('处理聊天消息: conversationId=${message.conversationId}');
    // 存内存（用于聊天详情页读取）
    // 避免重复添加相同消息
    final isDuplicate = _receivedMessages.any((msg) => msg.payload.id == message.payload.id);
    if (!isDuplicate) {
      _receivedMessages.add(message);
      // 按时间升序排列，确保新消息在正确的位置
      _receivedMessages.sort((a, b) => a.time.compareTo(b.time));
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
        'quote_id': int.tryParse(payload.quoteId) ?? 0,
        'content': payload.content,
        'type': payload.type,
        'status': payload.status,
        'created_at': createdAt,
      });

      // 2. 更新会话缓存（unread_count + 1，最新消息）
      await ConversationService().onNewMessage(
        conversationId: convId,
        senderId: senderId,
        messageId: msgId,
        messageAt: createdAt,
        messagePreview: payload.content,
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
    // 解析消息ID和会话ID，如果解析失败则直接返回
    final msgId = int.tryParse(message.messageId) ?? 0;
    final convId = int.tryParse(message.conversationId) ?? 0;

    if (msgId == 0 || convId == 0) return;

    // 异步执行数据库操作，避免阻塞主线程
    Future(() async {
      final dbService = DatabaseService();
      final db = await dbService.database;

      // 1. 将本地数据库消息表 messages 中的对应消息的 status 设置为已删除(2)
      await db.update(
        ConversationMessageEntity.tableName,
        {ConversationMessageEntity.status: 2},
        where: '${ConversationMessageEntity.id} = ?',
        whereArgs: [msgId],
      );

      // 2. 查询会话表，获取当前会话信息
      final conversationResult = await db.query(
        ConversationEntity.tableName,
        where: '${ConversationEntity.id} = ?',
        whereArgs: [convId],
      );

      // 如果会话存在
      if (conversationResult.isNotEmpty) {
        final conversation = conversationResult.first;
        final lastMessageId = conversation[ConversationEntity.lastMessageId] as int?;

        // 判断删除的消息是否为会话的最后一条消息
        if (lastMessageId == msgId) {
          // 查询该会话中未删除的最新一条消息
          final latestMessages = await db.query(
            ConversationMessageEntity.tableName,
            where: '${ConversationMessageEntity.conversationId} = ? AND ${ConversationMessageEntity.status} != 2',
            whereArgs: [convId],
            orderBy: '${ConversationMessageEntity.id} DESC',
            limit: 1,
          );

          // 如果还有未删除的消息，则更新会话的最后一条消息信息
          if (latestMessages.isNotEmpty) {
            final latestMessage = latestMessages.first;
            final newLastMessageId = latestMessage[ConversationMessageEntity.id] as int;
            final newLastMessageAt = latestMessage[ConversationMessageEntity.createdAt] as String;
            final newLastMessagePreview = _truncate(
              latestMessage[ConversationMessageEntity.content] as String? ?? '',
              50,
            );
            final newLastSenderId = latestMessage[ConversationMessageEntity.senderId] as int;

            await db.update(
              ConversationEntity.tableName,
              {
                ConversationEntity.lastMessageId: newLastMessageId,
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
    // 处理群组通知
    notifyListeners();
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
  /// [senderId] 发送者 ID
  /// [receiverId] 接收者 ID
  /// [message] 消息内容
  /// [quoteId] 引用的消息 ID
  Future<String> sendPrivateMessage({
    required dynamic conversationId,
    required dynamic senderId,
    required dynamic receiverId,
    required String message,
    String? quoteId,
  }) async {
    try {
      final dio = await AccountService().getDio();

      final data = <String, dynamic>{
        'conversationId': conversationId.toString(),
        'senderId': senderId is String ? int.tryParse(senderId) ?? senderId : senderId,
        'receiverId': receiverId is String ? int.tryParse(receiverId) ?? receiverId : receiverId,
        'message': message,
      };

      if (quoteId != null) {
        data['quoteId'] = int.tryParse(quoteId) ?? quoteId;
      }

      final response = await dio.post('/api/chat/send-private-message', data: data);

      final responseData = response.data;
      // _logger.d('发送私聊消息响应: $responseData');
      if (responseData != null && responseData['success'] == true) {
        // _logger.d('发送私聊消息成功');
        return responseData["data"];
      } else {
        _logger.e('发送私聊消息失败: ${responseData?['message']}');
        return "";
      }
    } catch (e) {
      _logger.e('发送私聊消息异常: $e');
      return "";
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
