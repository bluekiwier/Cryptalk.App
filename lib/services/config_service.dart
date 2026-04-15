import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'account_service.dart';
import '../models/config_result.dart';
import '../config/api_config.dart';

class ConfigService {
  static final ConfigService _instance = ConfigService._internal();
  factory ConfigService() => _instance;
  ConfigService._internal();
  final accountService = AccountService();

  /// 获取配置信息
  Future<ConfigResult?> fetchSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final companyId = prefs.getString('companyId');
      final requestData = {'companyId': companyId};
      final dio = Dio(BaseOptions(baseUrl: ApiConfig.baseUrl));
      final response = await dio.post('/api/config/settings', data: requestData);
      final responseData = response.data;
      if (responseData != null && responseData['success'] == true) {
        final data = responseData['data'] as Map<String, dynamic>;
        final result = ConfigResult.fromJson(data);
        return result;
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  /// 获取协议或隐私链接（带缓存机制）
  /// [type] 可选 'privacy' 或 'agreement'
  Future<String?> getUrlWithCache(String type) async {
    final prefs = await SharedPreferences.getInstance();
    final String urlKey = '${type}_url';
    final String timeKey = '${type}_last_fetch';

    final cachedUrl = prefs.getString(urlKey);
    final lastFetch = prefs.getInt(timeKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    // 如果缓存存在且未超过 1 小时（1 * 60 * 60 * 1000 毫秒）
    if (cachedUrl != null && (now - lastFetch) < 1 * 60 * 60 * 1000) {
      return cachedUrl;
    }

    // 否则请求接口并更新缓存
    final settings = await fetchSettings();
    if (settings != null) {
      await prefs.setString('privacy_url', settings.privacyUrl);
      await prefs.setInt('privacy_last_fetch', now);
      await prefs.setString('agreement_url', settings.agreementUrl);
      await prefs.setInt('agreement_last_fetch', now);

      return type == 'privacy' ? settings.privacyUrl : settings.agreementUrl;
    }

    return cachedUrl; // 如果请求失败但有旧缓存，返回旧缓存
  }
}
