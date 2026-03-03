import 'dart:async';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import 'account_service.dart';

/// 聊天服务 - 负责 WebSocket 的连接、消息收发与重连机制
class ChatService extends ChangeNotifier {
  static final ChatService _instance = ChatService._internal();
  factory ChatService() => _instance;
  ChatService._internal();

  final _logger = Logger();
  WebSocketChannel? _channel;
  bool _isConnected = false;
  bool _isConnecting = false;
  Timer? _heartbeatTimer;

  bool get isConnected => _isConnected;
  // 添加手动断开标志
  bool _isManuallyDisconnected = false;

  /// 检查并重新连接 WebSocket（用于 APP 重新打开时）
  Future<void> checkAndReconnect() async {
    if (!_isConnected) {
      _logger.i('APP 重新打开，检查并重新连接 WebSocket');
      await connect();
    } else {
      _logger.i('WebSocket 连接正常');
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
    // TODO: 解析接收到的消息，可以是 JSON 格式，更新状态或通知 UI
    _logger.i('收到 WebSocket 消息: $message');
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
    _logger.i('断线重连: 3秒后尝试重新获取地址并连接 WebSocket...');
    Future.delayed(const Duration(seconds: 3), () async {
      if (!_isConnected) {
        await _fetchWsServerAndConnect();
      }
    });
  }

  /// 获取新的 WebSocket 服务地址并连接
  Future<void> _fetchWsServerAndConnect() async {
    try {
      final dio = await AccountService().getDio();
      final response = await dio.post(
        '${ApiConfig.baseUrl}/api/chat/create-server-url',
      );
      final responseData = response.data;

      if (responseData != null && responseData['success'] == true) {
        final serverUrl = responseData['data']?.toString();
        if (serverUrl != null && serverUrl.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('wsServer', serverUrl);
          await connect();
        }
      } else {
        _logger.e('获取 WebSocket 地址失败: ${responseData?['message']}');
      }
    } catch (e) {
      _logger.e('获取 WebSocket 地址异常: $e');
    }
  }

  /// 发送私聊消息（通过 HTTP API）
  /// [conversationId] 会话 ID
  /// [senderId] 发送者 ID
  /// [receiverId] 接收者 ID
  /// [message] 消息内容
  Future<bool> sendPrivateMessage({
    required dynamic conversationId,
    required dynamic senderId,
    required dynamic receiverId,
    required String message,
  }) async {
    try {
      final dio = await AccountService().getDio();
      final response = await dio.post(
        '${ApiConfig.baseUrl}/api/chat/send-private-message',
        data: {
          'conversationId':
              (conversationId != null && conversationId.toString().isNotEmpty)
              ? int.tryParse(conversationId.toString()) ?? 0
              : 0,
          'senderId': senderId is String
              ? int.tryParse(senderId) ?? senderId
              : senderId,
          'receiverId': receiverId is String
              ? int.tryParse(receiverId) ?? receiverId
              : receiverId,
          'message': message,
        },
      );

      final responseData = response.data;
      if (responseData != null && responseData['success'] == true) {
        _logger.d('发送私聊消息成功');
        return true;
      } else {
        _logger.e('发送私聊消息失败: ${responseData?['message']}');
        return false;
      }
    } catch (e) {
      _logger.e('发送私聊消息异常: $e');
      return false;
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
        _logger.d('发送心跳消息: ping');
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
