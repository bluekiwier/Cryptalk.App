import 'dart:io';

/// API 地址配置
class ApiConfig {
  /// 主域名或基础地址，修改此项可影响全局 API 请求目标
  /// 根据不同平台自动选择合适的本地服务地址
  /// - Android 模拟器：使用 'http://10.0.2.2:60904'
  /// - 真机、Web、桌面端：使用 'http://localhost:60904'
  static String get baseUrl {
    if (Platform.isAndroid) {
      return 'http://10.0.2.2:60904';
    }
    return 'http://localhost:60904';
  }

  /// 全局请求超时时间 (毫秒)，当前为 20 秒
  static const int timeout = 20000;
}
