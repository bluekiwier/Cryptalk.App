import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'app.dart';
import 'services/account_service.dart';
import 'config/api_config.dart';
import 'services/notification_service.dart';

/// 应用入口
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 桌面平台初始化 sqflite_common_ffi 和窗口管理
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    // 配置窗口尺寸
    await windowManager.ensureInitialized();

    const windowOptions = WindowOptions(
      size: Size(400, 800),
      minimumSize: Size(400, 800),
      maximumSize: Size(400, 800),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
      title: '闲聊',
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  // 初始化 API 配置，检测真机/模拟器
  await ApiConfig.initialize();

  // 初始化 AccountService，从本地恢复用户信息
  await AccountService().initialize();

  // 为 FCM 注册后台消息处理器
  if (!Platform.isWindows && !Platform.isLinux) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    } catch (e) {
      debugPrint('Firebase 初始化失败: $e');
    }
  }
  
  // 初始化 NotificationService，用于展示 WebSocket 推送的消息
  // ignore: unused_local_variable
  final notificationService = NotificationService();
  await NotificationService().initialize();

  runApp(const CryptalkApp());
}

/// FCM 后台消息处理器
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // 如果此函数报错，请确保它是一个顶级函数（不在类内部）
  debugPrint("处理后台消息: ${message.messageId}");
  // 后台消息通常由系统直接展示通知给用户，
  // 如果后端发送的是 data 消息而非 notification 消息，则需要在这里手动展示本地通知
}
