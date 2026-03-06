import 'dart:async';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';
import '../config/api_config.dart';

class HttpService {
  static final HttpService _instance = HttpService._internal();
  factory HttpService() => _instance;
  HttpService._internal();

  final Logger _logger = Logger();

  /// 创建基础 Dio 实例（不包含认证相关配置）
  Future<Dio> _getBaseDio({Map<String, dynamic>? extraHeaders}) async {
    final dio = Dio();

    dio.options.baseUrl = ApiConfig.baseUrl;
    dio.options.connectTimeout = const Duration(milliseconds: ApiConfig.timeout);
    dio.options.receiveTimeout = const Duration(milliseconds: ApiConfig.timeout);
    dio.options.sendTimeout = const Duration(milliseconds: ApiConfig.timeout);

    final headers = {'Content-Type': 'application/json', 'Accept': 'application/json', ...?extraHeaders};
    dio.options.headers.addAll(headers);

    // 添加通用日志拦截器
    dio.interceptors.add(
      LogInterceptor(
        request: true,
        // requestHeader: true,
        // requestBody: true,
        // responseHeader: true,
        // responseBody: true,
        error: true,
      ),
    );

    return dio;
  }

  /// 获取配置了基础参数的 Dio 实例
  /// 其他 Service 可通过此方法获取基础 Dio 实例
  Future<Dio> getDio({Map<String, dynamic>? extraHeaders}) async {
    return _getBaseDio(extraHeaders: extraHeaders);
  }

  /// 获取带 Authorization 的 Dio 实例（内部复用方法）
  Future<Dio?> getAuthedDio() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString('accessToken');
    if (accessToken == null || accessToken.isEmpty) {
      _logger.w('未登录，无法执行该操作');
      return null;
    }
    return await getDio(extraHeaders: {'Authorization': 'Bearer $accessToken'});
  }
}
