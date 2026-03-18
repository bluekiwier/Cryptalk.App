import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';
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
  
  // 初始化 NotificationService，用于展示 WebSocket 推送的消息
  // ignore: unused_local_variable
  final notificationService = NotificationService();
  await NotificationService().initialize();

  runApp(const CryptalkApp());
}
