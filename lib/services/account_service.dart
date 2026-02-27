import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../config/api_config.dart';
import 'package:logger/logger.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';

/// 认证服务 - 管理用户登录/注册状态
class AccountService extends ChangeNotifier {
  static final AccountService _instance = AccountService._internal();
  factory AccountService() => _instance;
  AccountService._internal();

  final _logger = Logger();
  Timer? _refreshTimer;

  String? _cachedAppVersion;
  String? _cachedUserAgent;

  /// 获取包含设备信息的 User-Agent
  Future<String> _getUserAgent(String appVersion) async {
    final deviceInfo = DeviceInfoPlugin();
    String systemInfo = 'Unknown System';

    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        systemInfo =
            'Android ${androidInfo.version.release}; ${androidInfo.brand}; ${androidInfo.model}';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        systemInfo =
            'iOS ${iosInfo.systemVersion}; Apple; ${iosInfo.utsname.machine}';
      } else if (Platform.isWindows) {
        final windowsInfo = await deviceInfo.windowsInfo;
        systemInfo =
            'Windows ${windowsInfo.majorVersion}.${windowsInfo.minorVersion}.${windowsInfo.buildNumber}; Microsoft; PC';
      } else if (Platform.isMacOS) {
        final macInfo = await deviceInfo.macOsInfo;
        systemInfo =
            'macOS ${macInfo.majorVersion}.${macInfo.minorVersion}; Apple; Mac';
      } else if (Platform.isLinux) {
        final linuxInfo = await deviceInfo.linuxInfo;
        systemInfo = 'Linux ${linuxInfo.versionId}; ${linuxInfo.id}; PC';
      }
    } catch (e) {
      _logger.e('获取设备信息失败: $e');
    }

    return 'Cryptalk/$appVersion ($systemInfo)';
  }

  /// 获取仅仅配置了基础参数和 Header 的基础 Dio 实例（无拦截器）
  Future<Dio> _getBaseDio({Map<String, dynamic>? extraHeaders}) async {
    if (_cachedAppVersion == null || _cachedUserAgent == null) {
      final packageInfo = await PackageInfo.fromPlatform();
      _cachedAppVersion = packageInfo.version;
      _cachedUserAgent = await _getUserAgent(_cachedAppVersion!);
    }

    final headers = <String, dynamic>{
      'App-Version': _cachedAppVersion,
      'User-Agent': _cachedUserAgent,
    };
    if (extraHeaders != null) {
      headers.addAll(extraHeaders);
    }
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(milliseconds: ApiConfig.timeout),
        receiveTimeout: const Duration(milliseconds: ApiConfig.timeout),
        sendTimeout: const Duration(milliseconds: ApiConfig.timeout),
        headers: headers,
      ),
    );
  }

  bool _isRefreshingToken = false;
  Completer<bool>? _refreshTokenCompleter;

  /// 带有并发保护的无感刷新调用队列
  Future<bool> _safeRefreshToken() async {
    if (_isRefreshingToken && _refreshTokenCompleter != null) {
      return await _refreshTokenCompleter!.future;
    }
    _isRefreshingToken = true;
    _refreshTokenCompleter = Completer<bool>();

    final success = await refreshToken();

    _isRefreshingToken = false;
    _refreshTokenCompleter!.complete(success);
    return success;
  }

  /// 获取配置了基础参数和完整拦截器的 Dio 实例
  /// 其他 Service 可通过此方法获取带有 token 刷新拦截器的 Dio 实例
  Future<Dio> getDio({Map<String, dynamic>? extraHeaders}) async {
    final dio = await _getBaseDio(extraHeaders: extraHeaders);

    dio.interceptors.add(
      InterceptorsWrapper(
        onError: (DioException e, ErrorInterceptorHandler handler) async {
          // 如果是 401 报错，并且不是请求刷新令牌或登录接口，此时尝试发起刷新拿新的 accessToken
          if (e.response?.statusCode == 401 &&
              !e.requestOptions.path.contains('/api/account/refresh-token') &&
              !e.requestOptions.path.contains('/api/account/sign-in')) {
            _logger.w('收到 401，尝试通过 _safeRefreshToken 无感刷新 accessToken');

            final success = await _safeRefreshToken();
            if (success) {
              try {
                final prefs = await SharedPreferences.getInstance();
                final newAccessToken = prefs.getString('accessToken');

                final options = e.requestOptions;
                options.headers['Authorization'] = 'Bearer $newAccessToken';

                // 使用 _getBaseDio 克隆请求，防止再次走到拦截器里引发死循环
                final retryDio = await _getBaseDio();
                final response = await retryDio.fetch(options);
                return handler.resolve(response);
              } catch (retryError) {
                return handler.next(e);
              }
            } else {
              _logger.e('无感刷新失败，需要重新登录并清理本地缓存');
            }
          }
          return handler.next(e);
        },
      ),
    );
    return dio;
  }

  /// 当前登录用户
  User? _currentUser;
  User? get currentUser => _currentUser;

  /// 更新当前用户信息
  void updateCurrentUser(User user) {
    _currentUser = user;
    notifyListeners();
  }

  /// 是否已登录
  bool get isLoggedIn => _currentUser != null;

  /// 是否正在加载
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  /// 错误信息
  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  /// 账号密码登录
  Future<bool> loginWithPhone(String account, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final dio = await getDio();
      // 请求接口
      final response = await dio.post(
        '${ApiConfig.baseUrl}/api/account/sign-in',
        data: {'account': account, 'password': password},
      );

      final responseData = response.data;
      _logger.d('登录返回数据: $responseData');
      if (responseData != null && responseData['success'] == true) {
        final data = responseData['data'];

        // 保存 accessToken 等鉴权信息
        final prefs = await SharedPreferences.getInstance();
        if (data['jwt']['accessToken'] != null) {
          await prefs.setString('accessToken', data['jwt']['accessToken']);
        }
        if (data['jwt']['refreshToken'] != null) {
          await prefs.setString('refreshToken', data['jwt']['refreshToken']);
        }

        _currentUser = User(
          id: data['user']['id']?.toString() ?? '',
          account: data['user']['account'] ?? 'user',
          nickname: data['user']['nickname'] ?? '用户',
          avatar: data['user']['avatar']?.toString() ?? '',
          email: data['user']['email']?.toString() ?? '',
          mobile: data['user']['mobile']?.toString() ?? '',
          signature: data['user']['signature']?.toString() ?? '',
          isOnline: true,
        );

        // 获取过期时间并开启定时刷新
        if (data['jwt']['expiresTicks'] != null) {
          int expiresTicks = data['jwt']['expiresTicks'] is int
              ? data['jwt']['expiresTicks']
              : int.tryParse(data['jwt']['expiresTicks'].toString()) ?? 0;
          if (expiresTicks > 0) {
            _scheduleTokenRefresh(expiresTicks);
          }
        }

        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _errorMessage = responseData?['message'] ?? '登录失败';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } on DioException catch (e) {
      if (e.response != null &&
          e.response?.data != null &&
          e.response?.data is Map) {
        _errorMessage = e.response?.data['message'] ?? '登录失败';
      } else {
        _errorMessage = '网络错误：无法连接到服务器';
      }
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = '登录异常：$e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// 注册新用户
  Future<bool> register({
    required String phone,
    required String password,
    required String name,
    String? invitationCode,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final dio = await getDio();
      final requestData = {
        'account': phone,
        'password': password,
        'nickname': name,
      };
      if (invitationCode != null && invitationCode.isNotEmpty) {
        requestData['inviteCode'] = invitationCode;
      }

      final response = await dio.post(
        '${ApiConfig.baseUrl}/api/account/sign-up',
        data: requestData,
      );

      final responseData = response.data;
      if (responseData != null && responseData['success'] == true) {
        // 注册成功，自动调用登录完成状态变更
        _isLoading = false;
        // 注意：loginWithPhone内部会处理_isLoading和notifyListeners
        return await loginWithPhone(phone, password);
      } else {
        _errorMessage = responseData?['message'] ?? '注册失败';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } on DioException catch (e) {
      if (e.response != null &&
          e.response?.data != null &&
          e.response?.data is Map) {
        _errorMessage = e.response?.data['message'] ?? '注册失败';
      } else {
        _errorMessage = '网络错误：无法连接到服务器';
      }
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = '注册异常：$e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// 开启刷新令牌定时器
  void _scheduleTokenRefresh(int expiresTicks) {
    _refreshTimer?.cancel();
    // 提前 30 秒（30000毫秒）刷新
    int timeoutMs = expiresTicks - 30000;
    if (timeoutMs <= 0) timeoutMs = expiresTicks ~/ 2; // 如果有效期太短，在剩余一半时间时刷新

    _logger.d('将在 $timeoutMs 毫秒后自动刷新 accessToken');
    _refreshTimer = Timer(Duration(milliseconds: timeoutMs), () {
      refreshToken();
    });
  }

  /// 使用 Refresh Token 换取新的 Access Token
  Future<bool> refreshToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentRefreshToken = prefs.getString('refreshToken');
      if (currentRefreshToken == null || currentRefreshToken.isEmpty) {
        _logger.e('未找到 refreshToken，无法刷新');
        return false;
      }

      final accessToken = prefs.getString('accessToken');

      final dio = await _getBaseDio(
        extraHeaders: {'Authorization': 'Bearer $accessToken'},
      );

      _logger.i('开始刷新refreshToken');
      final response = await dio.post(
        '${ApiConfig.baseUrl}/api/account/refresh-token',
        data: {'refreshToken': currentRefreshToken},
      );

      final responseData = response.data;
      if (responseData != null && responseData['success'] == true) {
        final data = responseData['data'];

        if (data['accessToken'] != null) {
          await prefs.setString('accessToken', data['accessToken']);
        }
        if (data['refreshToken'] != null) {
          await prefs.setString('refreshToken', data['refreshToken']);
        }

        _logger.d('accessToken 刷新成功');

        if (data['expiresTicks'] != null) {
          int expiresTicks = data['expiresTicks'] is int
              ? data['expiresTicks']
              : int.tryParse(data['expiresTicks'].toString()) ?? 0;
          if (expiresTicks > 0) {
            _scheduleTokenRefresh(expiresTicks);
          }
        }
        return true;
      } else {
        _logger.e('刷新令牌失败: ${responseData?['message']}');
        // 刷新失败可考虑强制退出
        await logout();
        return false;
      }
    } catch (e) {
      _logger.e('刷新令牌异常: $e');
      return false;
    }
  }

  /// 退出登录
  Future<void> logout() async {
    _refreshTimer?.cancel();
    final prefs = await SharedPreferences.getInstance();
    try {
      final accessToken = prefs.getString('accessToken');

      if (accessToken != null && accessToken.isNotEmpty) {
        final dio = await getDio(
          extraHeaders: {'Authorization': 'Bearer $accessToken'},
        );

        final url = '${ApiConfig.baseUrl}/api/account/sign-out';
        _logger.d('''
--- 退出登录请求 ---
URL: $url
Headers: ${dio.options.headers}
Data: {} (无请求体)''');

        // 调用退出登录接口
        final response = await dio.post(url);

        final responseData = response.data;
        if (responseData != null && responseData['success'] == true) {
          _logger.d('退出登录成功');
        } else {
          _logger.e('退出登录失败: ${responseData?['message']}');
        }
      }
    } catch (e) {
      // 无论后端是否成功返回，均往下走清理本地数据
      _logger.e('退出登录接口调用失败：$e');
    } finally {
      // 清除本地存储的 Token
      await prefs.remove('accessToken');
      await prefs.remove('refreshToken');

      _currentUser = null;
      _errorMessage = null;
      // 回收状态通知
      notifyListeners();
    }
  }

  /// 清除错误信息
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
