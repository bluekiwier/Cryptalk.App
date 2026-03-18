import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logger/logger.dart';
import '../app.dart';
import 'conversation_service.dart';
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

    // Android 13+ 权限请求
    if (Platform.isAndroid) {
      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
          _notificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidImplementation != null) {
        await androidImplementation.requestNotificationsPermission();
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
