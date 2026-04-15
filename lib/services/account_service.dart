import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../models/user.dart';
import '../config/api_config.dart';
import '../utils/device_util.dart';
import '../utils/logger_util.dart';
import 'chat_service.dart';
import 'database_service.dart';
import 'encryption_service.dart';
import 'notification_service.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

/// 认证服务 - 管理用户登录/注册状态
class AccountService extends ChangeNotifier {
  static final AccountService _instance = AccountService._internal();
  factory AccountService() => _instance;
  AccountService._internal();

  final _logger = Log.logger;
  Timer? _refreshTimer;

  String? _cachedAppVersion;
  String? _cachedUserAgent;
  String? _cachedAcceptLanguage;

  /// 获取仅仅配置了基础参数和 Header 的基础 Dio 实例（无拦截器）
  Future<Dio> _getBaseDio({Map<String, dynamic>? extraHeaders}) async {
    if (_cachedAppVersion == null || _cachedUserAgent == null) {
      final packageInfo = await PackageInfo.fromPlatform();
      _cachedAppVersion = packageInfo.version;
      _cachedUserAgent = await DeviceUtil.getUserAgent(_cachedAppVersion!);
    }
    _cachedAcceptLanguage ??= DeviceUtil.getAcceptLanguage();

    final headers = <String, dynamic>{'App-Version': _cachedAppVersion, 'Accept-Language': _cachedAcceptLanguage};
    if (!kIsWeb) {
      headers['User-Agent'] = _cachedUserAgent;
    }
    if (extraHeaders != null) {
      headers.addAll(extraHeaders);
    }
    return Dio(
      BaseOptions(
        baseUrl: ApiConfig.baseUrl,
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

    // 从本地存储读取token并添加到headers
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString('accessToken');
    if (accessToken != null && accessToken.isNotEmpty) {
      dio.options.headers['Authorization'] = 'Bearer $accessToken';
    }

    // 添加通用日志拦截器
    dio.interceptors.add(
      LogInterceptor(
        request: true,
        requestHeader: true,
        requestBody: true,
        // responseHeader: true,
        responseBody: true,
        error: true,
        logPrint: Log.dioPrint,
      ),
    );

    // 添加数据加密拦截器
    dio.interceptors.add(EncryptInterceptor());

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

  /// 初始化：从本地存储恢复用户信息
  Future<void> initialize() async {
    _logger.d('开始初始化 AccountService...');
    await _loadUserFromLocal();
    _logger.d('AccountService 初始化完成，currentUser: $_currentUser');

    // 如果已登录，则注册推送 Token 并连接 WebSocket
    if (isLoggedIn) {
      NotificationService().registerPushToken();
      // 当 App 被杀进程后重新打开（冷启动），或者从后台切到前台（热启动），
      // 都会触发这个初始化过程，从而自动重连 WebSocket
      ChatService().checkAndReconnect();
    }
  }

  /// 保存用户信息到本地
  Future<void> _saveUserToLocal(User user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userId', user.id);
    await prefs.setString('userAccount', user.account);
    await prefs.setString('userNickname', user.nickname);
    await prefs.setString('userAvatar', user.avatar);
    if (user.email != null) {
      await prefs.setString('userEmail', user.email!);
    }
    if (user.mobile != null) {
      await prefs.setString('userMobile', user.mobile!);
    }
    if (user.signature != null) {
      await prefs.setString('userSignature', user.signature!);
    }
    await prefs.setBool('userOnline', user.online);
    if (user.secretKey != null) {
      await prefs.setString('userSecretKey', user.secretKey!);
    }
  }

  /// 从本地存储加载用户信息
  Future<void> _loadUserFromLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('userId');
    _logger.d('从本地读取 userId: $userId');

    if (userId == null || userId.isEmpty) {
      _logger.d('本地没有用户信息');
      return;
    }

    _currentUser = User(
      id: userId,
      account: prefs.getString('userAccount') ?? '',
      nickname: prefs.getString('userNickname') ?? '用户',
      avatar: prefs.getString('userAvatar') ?? '',
      email: prefs.getString('userEmail') ?? '',
      mobile: prefs.getString('userMobile') ?? '',
      signature: prefs.getString('userSignature') ?? '',
      online: prefs.getBool('userOnline') ?? false,
      secretKey: prefs.getString('userSecretKey') ?? '',
    );
    // _logger.d('加载用户信息成功: $_currentUser');

    // 初始化用户独立数据库
    await DatabaseService().initForUser(_currentUser!.id);
    // _logger.d('用户数据库初始化完成');

    notifyListeners();
  }

  /// 更新当前用户信息
  void updateCurrentUser(User user) {
    _currentUser = user;
    _saveUserToLocal(user); // 确保内部也保存到本地
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
      final prefs = await SharedPreferences.getInstance();
      final companyId = prefs.getString('companyId');
      final deviceId = await DeviceUtil.getDeviceId();
      final dio = await getDio(extraHeaders: {'Dev-Id': deviceId});

      final requestData = {'account': account, 'password': password};
      if (companyId != null && companyId.isNotEmpty) {
        requestData['companyId'] = companyId;
      }

      // 请求接口
      final response = await dio.post(
        '/api/account/sign-in',
        data: requestData,
        options: Options(extra: {'obfuscate': true}),
      );

      final responseData = response.data;
      // _logger.d('登录返回数据: $responseData');
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

        // WebSocket 服务器地址
        String? wsServer = data['server']?.toString();
        if (wsServer != null && wsServer.isNotEmpty) {
          // 协议修正
          if (wsServer.startsWith('http://')) {
            wsServer = wsServer.replaceFirst('http://', 'ws://');
          } else if (wsServer.startsWith('https://')) {
            wsServer = wsServer.replaceFirst('https://', 'wss://');
          }
          await prefs.setString('wsServer', wsServer);
        }

        _currentUser = User(
          id: data['user']['id']?.toString() ?? '',
          account: data['user']['account'] ?? 'user',
          nickname: data['user']['nickname'] ?? '用户',
          avatar: data['user']['avatar']?.toString() ?? '',
          email: data['user']['email']?.toString() ?? '',
          mobile: data['user']['mobile']?.toString() ?? '',
          signature: data['user']['signature']?.toString() ?? '',
          online: true,
          secretKey: data['user']['secretKey']?.toString() ?? '',
        );

        // 保存用户信息到本地
        await _saveUserToLocal(_currentUser!);

        // 初始化用户独立数据库
        await DatabaseService().initForUser(_currentUser!.id);

        // 连接 WebSocket
        await ChatService().checkAndReconnect();

        // 获取过期时间并开启定时刷新
        if (data['jwt']['expiresTicks'] != null) {
          int expiresTicks = data['jwt']['expiresTicks'] is int
              ? data['jwt']['expiresTicks']
              : int.tryParse(data['jwt']['expiresTicks'].toString()) ?? 0;
          if (expiresTicks > 0) {
            _scheduleTokenRefresh(expiresTicks);
          }
        }

        // 成功登录后请求推送权限并注册 Token
        NotificationService().registerPushToken();

        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _errorMessage = responseData?['message'] ?? '登录失败'.tr();
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } on DioException catch (e) {
      if (e.response != null && e.response?.data != null && e.response?.data is Map) {
        _errorMessage = e.response?.data['message'] ?? '登录失败'.tr();
      } else {
        _errorMessage = '网络错误：无法连接到服务器'.tr();
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
      final prefs = await SharedPreferences.getInstance();
      final companyId = prefs.getString('companyId');
      final dio = await getDio();

      // 生成用户密钥32字节 = 256位（AES-256），并转换为 Base64 字符串
      final userKey = encrypt.Key.fromSecureRandom(32).base64;
      final requestData = {'account': phone, 'password': password, 'nickname': name, 'key': userKey};
      if (invitationCode != null && invitationCode.isNotEmpty) {
        requestData['inviteCode'] = invitationCode;
      }
      if (companyId != null && companyId.isNotEmpty) {
        requestData['companyId'] = companyId;
      }

      final response = await dio.post(
        '/api/account/sign-up',
        data: requestData,
        options: Options(extra: {'obfuscate': true}),
      );

      final responseData = response.data;
      if (responseData != null && responseData['success'] == true) {
        // 注册成功，自动调用登录完成状态变更
        _isLoading = false;
        final loggedIn = await loginWithPhone(phone, password);
        if (loggedIn) {
          // 注册并登录成功后注册推送 Token
          NotificationService().registerPushToken();
        }
        return loggedIn;
      } else {
        _errorMessage = responseData?['message'] ?? '注册失败'.tr();
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } on DioException catch (e) {
      if (e.response != null && e.response?.data != null && e.response?.data is Map) {
        _errorMessage = e.response?.data['message'] ?? '注册失败'.tr();
      } else {
        _errorMessage = '网络错误：无法连接到服务器'.tr();
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

    // _logger.d('将在 $timeoutMs 毫秒后自动刷新 accessToken');
    _refreshTimer = Timer(Duration(milliseconds: timeoutMs), () {
      refreshToken();
    });
  }

  /// 使用 Refresh Token 换取新的 Access Token
  Future<bool> refreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final currentRefreshToken = prefs.getString('refreshToken');
      if (currentRefreshToken == null || currentRefreshToken.isEmpty) {
        _logger.e('未找到 refreshToken，无法刷新');
        return false;
      }

      final dio = await getDio();

      _logger.i('开始刷新refreshToken');
      final companyId = prefs.getString('companyId');
      final response = await dio.post(
        '/api/account/refresh-token',
        data: {'refreshToken': currentRefreshToken, 'companyId': companyId},
        options: Options(extra: {'obfuscate': true}),
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

        _logger.d('AccessToken 刷新成功');

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
        // await signOut();

        // await clearLocalData();
        return false;
      }
    } on DioException catch (e) {
      // 网络异常处理：区分不同类型的网络错误
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        _logger.w('刷新令牌超时（网络不稳定）: $e');
        // 网络超时不清理数据，让用户重试
        return false;
      } else if (e.type == DioExceptionType.connectionError) {
        _logger.w('刷新令牌连接错误（网络不可用）: $e');
        // 连接错误不清理数据，等待网络恢复
        return false;
      } else {
        _logger.e('刷新令牌网络异常: $e');
        // 其他网络异常也不清理数据
        return false;
      }
    } catch (e) {
      _logger.e('刷新令牌未知异常: $e');
      // 未知异常也不清理数据，保持用户登录状态
      return false;
    }
  }

  /// 退出登录
  Future<void> signOut() async {
    _refreshTimer?.cancel();
    final prefs = await SharedPreferences.getInstance();
    try {
      final accessToken = prefs.getString('accessToken');

      if (accessToken != null && accessToken.isNotEmpty) {
        final deviceId = await DeviceUtil.getDeviceId();
        final dio = await getDio(extraHeaders: {'Authorization': 'Bearer $accessToken', 'Dev-Id': deviceId});

        // 调用退出登录接口
        final response = await dio.post('/api/account/sign-out');

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
      // 清除本地存储的 Token 和用户信息
      await clearLocalData();
      // 回收状态通知
      notifyListeners();
    }
  }

  /// 清除本地数据
  Future<void> clearLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('accessToken');
    await prefs.remove('refreshToken');
    await prefs.remove('wsServer');
    await prefs.remove('userId');
    await prefs.remove('userAccount');
    await prefs.remove('userNickname');
    await prefs.remove('userAvatar');
    await prefs.remove('userEmail');
    await prefs.remove('userMobile');
    await prefs.remove('userSignature');
    await prefs.remove('userOnline');
    await prefs.remove('userSecretKey');

    // 清理用户数据库
    await DatabaseService().clearForCurrentUser();

    // 断开 WebSocket
    ChatService().disconnect();

    _currentUser = null;
    _errorMessage = null;
  }

  /// 清除错误信息
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// 发送重置密码验证码邮件
  Future<({bool success, String message})> sendEmailCode(String account) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final companyId = prefs.getString('companyId');
      final dio = await getDio();
      final response = await dio.post(
        '/api/account/send-email-code',
        data: {'companyId': companyId, 'account': account},
        options: Options(extra: {'obfuscate': true}),
      );
      final responseData = response.data;
      final message = responseData?['message']?.toString() ?? '操作完成'.tr();
      if (responseData != null && responseData['success'] == true) {
        return (success: true, message: message);
      } else {
        return (success: false, message: message);
      }
    } catch (e) {
      return (success: false, message: '网络错误，请稍后重试'.tr());
    }
  }

  /// 重置密码
  Future<({bool success, String message})> resetPassword(String account, String code, String password) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final companyId = prefs.getString('companyId');
      final dio = await getDio();
      final response = await dio.post(
        '/api/account/reset-password',
        data: {'companyId': companyId, 'account': account, 'code': code, 'newPassword': password},
        options: Options(extra: {'obfuscate': true}),
      );
      final responseData = response.data;
      final message = responseData?['message']?.toString() ?? '操作完成'.tr();
      if (responseData != null && responseData['success'] == true) {
        return (success: true, message: message);
      } else {
        return (success: false, message: message);
      }
    } catch (e) {
      return (success: false, message: '网络错误，请稍后重试'.tr());
    }
  }
}
