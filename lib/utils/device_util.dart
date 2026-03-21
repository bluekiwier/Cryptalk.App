import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:logger/logger.dart';

class DeviceUtil {
  static const _key = "device_id";
  static const _storage = FlutterSecureStorage();
  static const _uuid = Uuid();
  static final _logger = Logger();

  /// 获取设备ID（持久化存储）
  static Future<String> getDeviceId() async {
    String? deviceId = await _storage.read(key: _key);
    if (deviceId == null) {
      deviceId = _uuid.v4();
      await _storage.write(key: _key, value: deviceId);
    }
    return deviceId;
  }

  /// 获取设备语言设置
  static String getAcceptLanguage() {
    try {
      final locale = PlatformDispatcher.instance.locale;
      return '${locale.languageCode}-${locale.countryCode}';
    } catch (e) {
      _logger.e('获取设备语言失败: $e');
      return 'zh-CN'; // 默认中文
    }
  }

  /// 获取包含设备信息的 User-Agent
  static Future<String> getUserAgent(String appVersion) async {
    final deviceInfo = DeviceInfoPlugin();
    String systemInfo = 'Unknown System';

    try {
      if (kIsWeb) {
        final webInfo = await deviceInfo.webBrowserInfo;
        systemInfo = 'Web; ${webInfo.browserName.name}; ${webInfo.userAgent ?? "Unknown"}';
      } else if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        systemInfo = 'Android ${androidInfo.version.release}; ${androidInfo.brand}; ${androidInfo.model}';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        systemInfo = 'iOS ${iosInfo.systemVersion}; Apple; ${iosInfo.utsname.machine}';
      } else if (Platform.isWindows) {
        final windowsInfo = await deviceInfo.windowsInfo;
        systemInfo =
            'Windows NT ${windowsInfo.majorVersion}.${windowsInfo.minorVersion}.${windowsInfo.buildNumber}; Microsoft; PC';
      } else if (Platform.isMacOS) {
        final macInfo = await deviceInfo.macOsInfo;
        systemInfo = 'macOS ${macInfo.majorVersion}.${macInfo.minorVersion}; Apple; Mac';
      } else if (Platform.isLinux) {
        final linuxInfo = await deviceInfo.linuxInfo;
        systemInfo = 'Linux ${linuxInfo.versionId}; ${linuxInfo.id}; PC';
      }
    } catch (e) {
      _logger.e('获取设备信息失败: $e');
    }

    return 'Cryptalk/$appVersion ($systemInfo)';
  }
}
