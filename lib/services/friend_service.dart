import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import '../config/api_config.dart';
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
        _logger.d('获取到 ${requests.length} 条好友申请');
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
  /// 调用 POST /api/friend/requests/agree
  /// [requestId] 为 Requests 接口返回的申请记录 ID
  Future<({bool success, String message})> agreeFriendRequest(String requestId) async {
    try {
      final dio = await accountService.getDio();
      // if (dio == null) return (success: false, message: '未登录');

      _logger.d('接受好友申请: id=$requestId');

      final response = await dio.post('/api/friend/requests/agree', data: {'id': requestId});

      final responseData = response.data;
      final msg = responseData?['message']?.toString() ?? '操作完成';
      if (responseData != null && responseData['success'] == true) {
        _logger.d('接受好友申请成功');
        return (success: true, message: msg);
      } else {
        _logger.e('接受好友申请失败: $msg');
        return (success: false, message: msg);
      }
    } catch (e) {
      _logger.e('接受好友申请异常: $e');
      return (success: false, message: '网络错误，请稍后重试');
    }
  }

  /// 拒绝好友申请
  /// 调用 POST /api/friend/requests/disagree
  Future<({bool success, String message})> disagreeFriendRequest(String requestId) async {
    try {
      final dio = await accountService.getDio();
      // if (dio == null) return (success: false, message: '未登录');

      _logger.d('拒绝好友申请: id=$requestId');

      final response = await dio.post('/api/friend/requests/disagree', data: {'id': requestId});

      final responseData = response.data;
      final msg = responseData?['message']?.toString() ?? '操作完成';
      if (responseData != null && responseData['success'] == true) {
        _logger.d('拒绝好友申请成功');
        return (success: true, message: msg);
      } else {
        _logger.e('拒绝好友申请失败: $msg');
        return (success: false, message: msg);
      }
    } catch (e) {
      _logger.e('拒绝好友申请异常: $e');
      return (success: false, message: '网络错误，请稍后重试');
    }
  }

  /// 拉黑用户
  /// 调用 POST /api/friend/block
  Future<({bool success, String message})> blockFriendRequest(String userId) async {
    try {
      final dio = await accountService.getDio();
      // if (dio == null) return (success: false, message: '未登录');

      _logger.d('拉黑用户: id=$userId');

      final response = await dio.post('/api/friend/blacklist-add', data: {'id': userId});

      final responseData = response.data;
      final msg = responseData?['message']?.toString() ?? '操作完成';
      if (responseData != null && responseData['success'] == true) {
        _logger.d('拉黑用户成功');
        return (success: true, message: msg);
      } else {
        _logger.e('拉黑用户失败: $msg');
        return (success: false, message: msg);
      }
    } catch (e) {
      _logger.e('拉黑用户异常: $e');
      return (success: false, message: '网络错误，请稍后重试');
    }
  }

  /// 移除黑名单
  /// 调用 DELETE /api/friend/block-remove
  Future<({bool success, String message})> removeBlock(String userId) async {
    try {
      final dio = await accountService.getDio();
      // if (dio == null) return (success: false, message: '未登录');

      _logger.d('移除黑名单: id=$userId');

      final response = await dio.delete('/api/friend/blacklist-remove', data: {'id': userId});

      final responseData = response.data;
      final msg = responseData?['message']?.toString() ?? '操作完成';
      if (responseData != null && responseData['success'] == true) {
        _logger.d('移除黑名单成功');
        return (success: true, message: msg);
      } else {
        _logger.e('移除黑名单失败: $msg');
        return (success: false, message: msg);
      }
    } catch (e) {
      _logger.e('移除黑名单异常: $e');
      return (success: false, message: '网络错误，请稍后重试');
    }
  }

  /// 删除好友
  /// 调用 DELETE /api/friend/delete
  Future<({bool success, String message})> deleteFriend(String userId) async {
    try {
      final dio = await accountService.getDio();
      // if (dio == null) return (success: false, message: '未登录');

      _logger.d('删除好友: ids=[$userId]');

      final response = await dio.delete(
        '/api/friend/delete',
        data: {
          'ids': [userId],
        },
      );

      final responseData = response.data;
      final msg = responseData?['message']?.toString() ?? '操作完成';
      if (responseData != null && responseData['success'] == true) {
        _logger.d('删除好友成功');
        return (success: true, message: msg);
      } else {
        _logger.e('删除好友失败: $msg');
        return (success: false, message: msg);
      }
    } catch (e) {
      _logger.e('删除好友异常: $e');
      return (success: false, message: '网络错误，请稍后重试');
    }
  }

  /// 获取好友申请数量
  /// 调用 GET /api/friend/requests/count
  Future<int> getRequestsCount() async {
    try {
      final dio = await accountService.getDio();
      // if (dio == null) return 0;

      final response = await dio.get('/api/friend/requests/count');

      final responseData = response.data;
      if (responseData != null && responseData['success'] == true) {
        final count = responseData['data'];
        _logger.d('好友申请数量: $count');
        return count is int ? count : int.tryParse(count.toString()) ?? 0;
      }
      return 0;
    } catch (e) {
      _logger.e('获取好友申请数量异常: $e');
      return 0;
    }
  }

  /// 添加好友
  /// 调用 POST /api/friend/add
  /// [account] 可以是 ID / 账号 / 手机号
  Future<({bool success, String message})> addFriend(String account) async {
    try {
      final dio = await accountService.getDio();
      // if (dio == null) return (success: false, message: '未登录');

      _logger.d('添加好友: account=$account');

      final response = await dio.post('/api/friend/add', data: {'account': account});

      final responseData = response.data;
      final msg = responseData?['message']?.toString() ?? '操作完成';
      if (responseData != null && responseData['success'] == true) {
        _logger.d('添加好友成功: $msg');
        return (success: true, message: msg);
      } else {
        _logger.e('添加好友失败: $msg');
        return (success: false, message: msg);
      }
    } catch (e) {
      _logger.e('添加好友异常: $e');
      return (success: false, message: '网络错误，请稍后重试');
    }
  }

  /// 获取好友列表
  /// 调用 GET /api/friend/list
  Future<List<Map<String, dynamic>>> getFriendList() async {
    try {
      final dio = await accountService.getDio();
      // if (dio == null) return [];

      _logger.d('请求好友列表: /api/friend/list');

      final response = await dio.get('/api/friend/list');

      final responseData = response.data;
      if (responseData != null && responseData['success'] == true) {
        final List<dynamic> dataList = responseData['data'] ?? [];
        _logger.d('获取到 ${dataList.length} 位好友');
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
