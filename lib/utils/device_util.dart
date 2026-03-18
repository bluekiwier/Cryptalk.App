import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

class DeviceUtil {
  static const _key = "device_id";
  static const _storage = FlutterSecureStorage();
  static const _uuid = Uuid();

  /// 获取设备ID（持久化存储）
  static Future<String> getDeviceId() async {
    String? deviceId = await _storage.read(key: _key);
    if (deviceId == null) {
      deviceId = _uuid.v4();
      await _storage.write(key: _key, value: deviceId);
    }
    return deviceId;
  }
}
