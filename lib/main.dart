import 'package:flutter/material.dart';
import 'app.dart';
import 'services/account_service.dart';

/// 应用入口
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化 AccountService，从本地恢复用户信息
  await AccountService().initialize();

  runApp(const CryptalkApp());
}
