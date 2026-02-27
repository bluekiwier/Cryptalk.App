/// API 地址配置
class ApiConfig {
  /// 主域名或基础地址，修改此项可影响全局 API 请求目标
  /// 如果在 Android 模拟器测试本地服务，请使用 'http://10.0.2.2:5000'
  /// 如果在真机、Web、桌面端测试本地服务，使用 'http://localhost:5000' 或局域网 IP
  static const String baseUrl = 'http://10.0.2.2:60904';

  /// 全局请求超时时间 (毫秒)，当前为 20 秒
  static const int timeout = 20000;
}
