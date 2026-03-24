import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logger/logger.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../app.dart';
import 'conversation_service.dart';
import 'user_service.dart';
import '../utils/device_util.dart';
import '../pages/chat/chat_detail_page.dart';

/// 通知服务 - 负责本地通知的初始化与展示
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  final _logger = Logger();

  /// 初始化通知设置
  Future<void> initialize() async {
    // 1. 初始化本地通知
    await _initLocalNotifications();

    // 2. 初始化 FCM
    await _initFirebaseMessaging();
  }

  /// 初始化本地通知
  Future<void> _initLocalNotifications() async {
    // Android 配置
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS/macOS 配置
    const DarwinInitializationSettings initializationSettingsDarwin = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    // Linux 配置
    const LinuxInitializationSettings initializationSettingsLinux = LinuxInitializationSettings(
      defaultActionName: 'Open notification',
    );

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
      macOS: initializationSettingsDarwin,
      linux: initializationSettingsLinux,
    );

    await _notificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        final conversationId = response.payload;
        if (conversationId != null && conversationId.isNotEmpty) {
          _logger.i('通知点击响应: $conversationId, 尝试跳转聊天页');
          final conversation = await ConversationService().getConversationById(conversationId);
          if (conversation != null) {
            CryptalkApp.navigatorKey.currentState?.push(
              MaterialPageRoute(builder: (context) => ChatDetailPage(conversation: conversation)),
            );
          }
        }
      },
    );

    // Android 13+ 本地通知权限请求（可选，FCM 也会请求）
    if (Platform.isAndroid) {
      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
          _notificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidImplementation != null) {
        await androidImplementation.requestNotificationsPermission();
      }
    }
  }

  /// 初始化 Firebase Cloud Messaging
  Future<void> _initFirebaseMessaging() async {
    if (Platform.isWindows || Platform.isLinux) {
      _logger.d('当前平台不支持 FCM');
      return;
    }

    try {
      // 3. 请求推送权限（iOS/Android 13+）
      NotificationSettings settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        _logger.d('用户授予了推送权限');
      } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
        _logger.d('用户授予了临时推送权限');
      } else {
        _logger.w('用户拒绝或未授予推送权限');
      }

      // 前台消息处理
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        _logger.d('收到 FCM 前台消息: ${message.messageId}');
        _handleForegroundMessage(message);
      });

      // 当 App 从后台被点击时触发
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        _logger.d('用户点击了 FCM 通知，进入 App');
        _handleNotificationClick(message.data);
      });

      // 检查是否有由于点击通知而启动 App 的初始消息
      RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        _logger.d('App 通过点击 FCM 通知启动');
        _handleNotificationClick(initialMessage.data);
      }
    } catch (e) {
      _logger.e('初始化 FCM 异常: $e');
    }
  }

  /// 注册推送 Token 到后端
  Future<void> registerPushToken() async {
    if (Platform.isWindows || Platform.isLinux) return;

    try {
      // 4. 获取 FCM Token
      String? token = await FirebaseMessaging.instance.getToken();
      if (token == null) {
        _logger.e('获取 FCM Token 失败');
        return;
      }
      _logger.i('获取到 FCM Token: $token');

      // 5. 获取设备 ID 并上传到后端
      final deviceId = await DeviceUtil.getDeviceId();
      final platform = Platform.isIOS ? 'ios' : 'android';

      await UserService().deviceRegister(
        deviceId: deviceId,
        pushToken: token,
        platform: platform,
        pushProvider: 'fcm',
      );
    } catch (e) {
      _logger.e('注册推送 Token 异常: $e');
    }
  }

  /// 处理前台收到的 FCM 消息（转换为本地通知展示）
  void _handleForegroundMessage(RemoteMessage message) {
    RemoteNotification? notification = message.notification;
    // AndroidNotification? android = message.notification?.android;

    if (notification != null) {
      showChatNotification(
        id: message.hashCode,
        title: notification.title ?? '收到新消息',
        body: notification.body ?? '',
        payload: message.data['conversationId'], // 假设后端在 data 中传了 conversationId
      );
    }
  }

  /// 处理通知点击跳转逻辑
  Future<void> _handleNotificationClick(Map<String, dynamic> data) async {
    final conversationId = data['conversationId'];
    if (conversationId != null && conversationId.isNotEmpty) {
      final conversation = await ConversationService().getConversationById(conversationId);
      if (conversation != null) {
        CryptalkApp.navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (context) => ChatDetailPage(conversation: conversation)),
        );
      }
    }
  }

  /// 显示聊天消息通知
  Future<void> showChatNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    // Android 通知详情配置
    const AndroidNotificationDetails androidNotificationDetails = AndroidNotificationDetails(
      'chat_messages', // 渠道 ID
      '聊天消息', // 渠道名称
      channelDescription: '显示接收到的聊天消息',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      // 这里的配置决定了通知是否显示为横幅
      fullScreenIntent: false,
      visibility: NotificationVisibility.public,
    );

    // iOS 通知详情配置
    const DarwinNotificationDetails darwinNotificationDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidNotificationDetails,
      iOS: darwinNotificationDetails,
      macOS: darwinNotificationDetails,
    );

    try {
      // 确保 ID 在 32 位有符号整数范围内 (Android 限制为 jint)
      // 使用 0x7FFFFFFF 掩码确保它是非负的 31 位整数，这是最安全的做法
      final safeId = id & 0x7FFFFFFF;

      await _notificationsPlugin.show(
        id: safeId,
        title: title,
        body: body,
        notificationDetails: notificationDetails,
        payload: payload,
      );
    } catch (e) {
      _logger.e('发送通知失败: $e');
    }
  }

  /// 取消所有通知
  Future<void> cancelAll() async {
    await _notificationsPlugin.cancelAll();
  }

  /// 取消指定 ID 的通知
  Future<void> cancel(int id) async {
    await _notificationsPlugin.cancel(id: id);
  }
}
