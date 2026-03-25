import 'package:logger/logger.dart';
import 'package:dio/dio.dart';
import '../models/user.dart';
import 'account_service.dart';

/// 用户服务 - 管理用户信息相关业务
class UserService {
  static final UserService _instance = UserService._internal();
  factory UserService() => _instance;
  UserService._internal();

  final _logger = Logger();
  final accountService = AccountService();

  /// 获取当前用户的个人资料
  Future<User?> getMe() async {
    try {
      final dio = await accountService.getDio();
      final response = await dio.get('/api/user/me');

      final responseData = response.data;
      if (responseData != null && responseData['success'] == true) {
        // _logger.d('获取个人资料成功');
        final data = responseData['data'] as Map<String, dynamic>;
        return User.fromJson(data);
      } else {
        _logger.e('获取个人资料失败: ${responseData?['message']}');
        return null;
      }
    } catch (e) {
      _logger.e('获取个人资料异常: $e');
      return null;
    }
  }

  /// 获取用户详情
  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      final dio = await accountService.getDio();
      final response = await dio.get('/api/user/profile/$userId');
      final responseData = response.data;
      if (responseData != null && responseData['success'] == true) {
        // _logger.d('获取用户详情成功');
        return responseData['data'] as Map<String, dynamic>?;
      } else {
        _logger.e('获取用户详情失败: ${responseData?['message']}');
        return null;
      }
    } catch (e) {
      _logger.e('获取用户详情异常: $e');
      return null;
    }
  }

  /// 修改用户信息
  Future<({bool success, String message})> changeInfo({
    String? nickname,
    String? mobile,
    String? email,
    String? signature,
  }) async {
    try {
      final dio = await accountService.getDio();

      final Map<String, dynamic> data = {};
      if (nickname != null) data['Nickname'] = nickname;
      if (mobile != null) data['Mobile'] = mobile;
      if (email != null) data['Email'] = email;
      if (signature != null) data['Signature'] = signature;

      // _logger.d('请求修改用户信息: $data');

      final response = await dio.post(
        '/api/user/change-info',
        data: data,
        options: Options(extra: {'obfuscate': true}),
      );

      final responseData = response.data;
      final msg = responseData?['message']?.toString() ?? '提交完成';

      if (responseData != null && responseData['success'] == true) {
        // _logger.d('修改用户信息成功');
        return (success: true, message: msg);
      } else {
        _logger.e('修改用户信息失败: $msg');
        return (success: false, message: msg);
      }
    } catch (e) {
      _logger.e('修改用户信息异常: $e');
      return (success: false, message: '网络错误，请稍后重试');
    }
  }

  /// 修改密码
  Future<({bool success, String message})> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    try {
      final dio = await accountService.getDio();
      final response = await dio.post(
        '/api/user/change-password',
        data: {'oldpassword': oldPassword, 'newpassword': newPassword},
        options: Options(extra: {'obfuscate': true}),
      );

      final responseData = response.data;
      final msg = responseData?['message']?.toString() ?? '操作完成';
      if (responseData != null && responseData['success'] == true) {
        // _logger.d('修改密码成功');
        return (success: true, message: msg);
      } else {
        _logger.e('修改密码失败: $msg');
        return (success: false, message: msg);
      }
    } catch (e) {
      _logger.e('修改密码异常: $e');
      return (success: false, message: '网络错误，请稍后重试');
    }
  }

  /// 搜索用户
  Future<List<Map<String, dynamic>>?> searchUser(String keyword) async {
    try {
      final dio = await accountService.getDio();

      // _logger.d('搜索用户 keyword: $keyword');

      final response = await dio.post(
        '/api/user/search',
        data: {'keyword': keyword},
        options: Options(extra: {'obfuscate': true}),
      );

      final responseData = response.data;
      if (responseData != null && responseData['success'] == true) {
        // _logger.d('搜索用户成功');
        return (responseData['data'] as List<dynamic>?)?.cast<Map<String, dynamic>>();
      } else {
        _logger.e('搜索用户失败: ${responseData?['message']}');
        return null;
      }
    } catch (e) {
      _logger.e('搜索用户异常: $e');
      return null;
    }
  }

  /// 修改当前用户头像
  Future<bool> changeAvatar(String avatarUrl) async {
    try {
      final dio = await accountService.getDio();
      final response = await dio.post(
        '/api/user/change-avatar',
        data: {'avatar': avatarUrl},
        options: Options(extra: {'obfuscate': true}),
      );
      final data = response.data;
      if (data != null && data['success'] == true) {
        // _logger.d('修改头像成功');
        // 同步更新 AccountService 中的用户信息
        final currentUser = accountService.currentUser;
        if (currentUser != null) {
          final updatedUser = currentUser.copyWith(avatar: avatarUrl);
          accountService.updateCurrentUser(updatedUser);
        }
        return true;
      } else {
        _logger.e('修改头像失败: ${data?['message']}');
        return false;
      }
    } catch (e) {
      _logger.e('修改头像异常: $e');
      return false;
    }
  }

  /// 设备注册
  Future<bool> deviceRegister({
    required String deviceId,
    String deviceName = 'Unknown Device',
    required String pushToken,
    required String platform,
    String pushProvider = 'fcm',
  }) async {
    try {
      final dio = await accountService.getDio();
      final response = await dio.post(
        '/api/user/device-register',
        data: {
          'deviceId': deviceId,
          'deviceName': deviceName,
          'pushToken': pushToken,
          'platform': platform,
          'pushProvider': pushProvider,
        },
        options: Options(extra: {'obfuscate': true}),
      );
      final data = response.data;
      if (data != null && data['success'] == true) {
        _logger.d('设备注册成功');
        return true;
      } else {
        _logger.e('设备注册失败: ${data?['message']}');
        return false;
      }
    } catch (e) {
      _logger.e('设备注册异常: $e');
      return false;
    }
  }
}
