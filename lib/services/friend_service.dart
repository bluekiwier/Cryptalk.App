import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:easy_localization/easy_localization.dart';
import '../models/friend_request.dart';
import '../services/account_service.dart';

/// 好友服务 - 管理好友相关业务
class FriendService {
  static final FriendService _instance = FriendService._internal();
  factory FriendService() => _instance;
  FriendService._internal();

  final _logger = Logger();
  final accountService = AccountService();

  /// 获取待处理的好友申请列表
  /// 调用 GET /api/friend/requests 接口
  /// 返回 [FriendRequest] 列表，失败时返回空列表
  Future<List<FriendRequest>> getRequests() async {
    try {
      // 复用 AccountService 的 Dio 实例
      final dio = await accountService.getDio();
      // if (dio == null) return [];

      final response = await dio.get('/api/friend/requests?status=0');

      final responseData = response.data;
      if (responseData != null && responseData['success'] == true) {
        final List<dynamic> dataList = responseData['data'] ?? [];
        final requests = dataList.map((item) => FriendRequest.fromJson(item)).toList();
        // _logger.d('获取到 ${requests.length} 条好友申请');
        return requests;
      } else {
        _logger.e('获取好友申请列表失败: ${responseData?['message']}');
        return [];
      }
    } on DioException catch (e) {
      if (e.response != null && e.response?.data != null && e.response?.data is Map) {
        _logger.e('获取好友申请列表失败: ${e.response?.data['message']}');
      } else {
        _logger.e('网络错误：无法获取好友申请列表');
      }
      return [];
    } catch (e) {
      _logger.e('获取好友申请列表异常: $e');
      return [];
    }
  }

  /// 接受好友申请
  Future<({bool success, String message})> agreeFriendRequest(String requestId) async {
    try {
      final dio = await accountService.getDio();
      final response = await dio.post(
        '/api/friend/requests/agree',
        data: {'id': requestId},
        options: Options(extra: {'obfuscate': true}),
      );
      final responseData = response.data;
      final msg = responseData?['message']?.toString() ?? '操作完成'.tr();
      if (responseData != null && responseData['success'] == true) {
        // _logger.d('接受好友申请成功');
        return (success: true, message: msg);
      } else {
        _logger.e('接受好友申请失败: $msg');
        return (success: false, message: msg);
      }
    } catch (e) {
      _logger.e('接受好友申请异常: $e');
      return (success: false, message: '网络错误，请稍后重试'.tr());
    }
  }

  /// 拒绝好友申请
  Future<({bool success, String message})> disagreeFriendRequest(String requestId) async {
    try {
      final dio = await accountService.getDio();
      final response = await dio.post(
        '/api/friend/requests/disagree',
        data: {'id': requestId},
        options: Options(extra: {'obfuscate': true}),
      );
      final responseData = response.data;
      final msg = responseData?['message']?.toString() ?? '操作完成'.tr();
      if (responseData != null && responseData['success'] == true) {
        // _logger.d('拒绝好友申请成功');
        return (success: true, message: msg);
      } else {
        _logger.e('拒绝好友申请失败: $msg');
        return (success: false, message: msg);
      }
    } catch (e) {
      _logger.e('拒绝好友申请异常: $e');
      return (success: false, message: '网络错误，请稍后重试'.tr());
    }
  }

  /// 拉黑用户
  Future<({bool success, String message})> blockFriendRequest(String userId) async {
    try {
      final dio = await accountService.getDio();
      final response = await dio.post(
        '/api/friend/blacklist-add',
        data: {'id': userId},
        options: Options(extra: {'obfuscate': true}),
      );
      final responseData = response.data;
      final msg = responseData?['message']?.toString() ?? '操作完成'.tr();
      if (responseData != null && responseData['success'] == true) {
        // _logger.d('拉黑用户成功');
        return (success: true, message: msg);
      } else {
        _logger.e('拉黑用户失败: $msg');
        return (success: false, message: msg);
      }
    } catch (e) {
      _logger.e('拉黑用户异常: $e');
      return (success: false, message: '网络错误，请稍后重试'.tr());
    }
  }

  /// 移除黑名单
  Future<({bool success, String message})> removeBlock(String userId) async {
    try {
      final dio = await accountService.getDio();
      final response = await dio.delete(
        '/api/friend/blacklist-remove',
        data: {'id': userId},
        options: Options(extra: {'obfuscate': true}),
      );
      final responseData = response.data;
      final msg = responseData?['message']?.toString() ?? '操作完成'.tr();
      if (responseData != null && responseData['success'] == true) {
        // _logger.d('移除黑名单成功');
        return (success: true, message: msg);
      } else {
        _logger.e('移除黑名单失败: $msg');
        return (success: false, message: msg);
      }
    } catch (e) {
      _logger.e('移除黑名单异常: $e');
      return (success: false, message: '网络错误，请稍后重试'.tr());
    }
  }

  /// 删除好友
  Future<({bool success, String message})> deleteFriend(String userId) async {
    try {
      final dio = await accountService.getDio();
      final response = await dio.delete(
        '/api/friend/delete',
        data: {
          'ids': [userId],
        },
        options: Options(extra: {'obfuscate': true}),
      );

      final responseData = response.data;
      final msg = responseData?['message']?.toString() ?? '操作完成'.tr();
      if (responseData != null && responseData['success'] == true) {
        // _logger.d('删除好友成功');
        return (success: true, message: msg);
      } else {
        _logger.e('删除好友失败: $msg');
        return (success: false, message: msg);
      }
    } catch (e) {
      _logger.e('删除好友异常: $e');
      return (success: false, message: '网络错误，请稍后重试'.tr());
    }
  }

  /// 获取好友申请数量
  Future<int> getRequestsCount() async {
    try {
      final dio = await accountService.getDio();
      final response = await dio.get('/api/friend/requests/count');
      final responseData = response.data;
      if (responseData != null && responseData['success'] == true) {
        final count = responseData['data'];
        // _logger.d('好友申请数量: $count');
        return count is int ? count : int.tryParse(count.toString()) ?? 0;
      }
      return 0;
    } catch (e) {
      _logger.e('获取好友申请数量异常: $e');
      return 0;
    }
  }

  /// 添加好友
  /// [account] 可以是 ID / 账号 / 手机号
  Future<({bool success, String message})> addFriend(String account) async {
    try {
      final dio = await accountService.getDio();
      final response = await dio.post(
        '/api/friend/add',
        data: {'account': account},
        options: Options(extra: {'obfuscate': true}),
      );
      final responseData = response.data;
      final msg = responseData?['message']?.toString() ?? '操作完成'.tr();
      if (responseData != null && responseData['success'] == true) {
        // _logger.d('添加好友成功: $msg');
        return (success: true, message: msg);
      } else {
        _logger.e('添加好友失败: $msg');
        return (success: false, message: msg);
      }
    } catch (e) {
      _logger.e('添加好友异常: $e');
      return (success: false, message: '网络错误，请稍后重试'.tr());
    }
  }

  /// 获取好友列表
  Future<List<Map<String, dynamic>>> getFriendList() async {
    try {
      final dio = await accountService.getDio();
      final response = await dio.get('/api/friend/list');
      final responseData = response.data;
      if (responseData != null && responseData['success'] == true) {
        final List<dynamic> dataList = responseData['data'] ?? [];
        // _logger.d('获取到 ${dataList.length} 位好友');
        return dataList.cast<Map<String, dynamic>>();
      } else {
        _logger.e('获取好友列表失败: ${responseData?['message']}');
        return [];
      }
    } catch (e) {
      _logger.e('获取好友列表异常: $e');
      return [];
    }
  }
}
