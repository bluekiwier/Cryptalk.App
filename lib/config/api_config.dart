import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

/// API 地址配置
class ApiConfig {
  static String? _cachedBaseUrl;
  static final String _localUrl = 'http://192.168.2.99:60901';

  /// 主域名或基础地址，修改此项可影响全局 API 请求目标
  /// 根据不同平台自动选择合适的本地服务地址
  /// - Android 模拟器：使用 'http://10.0.2.2:60901'
  /// - 真机、Web、桌面端：使用 'http://localhost:60901'
  static String get baseUrl {
    if (_cachedBaseUrl != null) {
      return _cachedBaseUrl!;
    }

    if (kIsWeb || !Platform.isAndroid) {
      _cachedBaseUrl = _localUrl;
      return _cachedBaseUrl!;
    }

    return 'http://10.0.2.2:60901';
  }

  /// 初始化 API 配置，会检测是否是真机并缓存 baseUrl
  static Future<void> initialize() async {
    if (kIsWeb || !Platform.isAndroid) {
      _cachedBaseUrl = _localUrl;
      return;
    }

    final isEmulator = await _isAndroidEmulator();
    if (isEmulator) {
      _cachedBaseUrl = 'http://10.0.2.2:60901';
    } else {
      _cachedBaseUrl = _localUrl;
    }
    debugPrint('ApiConfig 已初始化: baseUrl=$_cachedBaseUrl, isEmulator=$isEmulator');
  }

  /// 判断是否是 Android 模拟器
  static Future<bool> _isAndroidEmulator() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      return !androidInfo.isPhysicalDevice;
    } catch (e) {
      debugPrint('检测设备类型失败: $e');
      return false;
    }
  }

  /// 全局请求超时时间 (毫秒)，当前为 20 秒
  static const int timeout = 20000;
}
