import 'dart:async';
import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'account_service.dart';

class UploadUrlResult {
  final String? fileUrl;
  final String? uploadUrl;
  final String? key;

  const UploadUrlResult({this.fileUrl, this.uploadUrl, this.key});

  bool get isSuccess => fileUrl != null && uploadUrl != null;
}

class FileService {
  static final FileService _instance = FileService._internal();
  factory FileService() => _instance;
  FileService._internal();

  final Logger _logger = Logger();

  Future<UploadUrlResult?> createUploadUrl(String contentType, String fileName, int fileSize, String fileType) async {
    try {
      final dio = await AccountService().getDio();
      final response = await dio.post(
        '/api/file/create-upload-url',
        data: {'contentType': contentType, 'fileName': fileName, 'fileSize': fileSize, 'fileType': fileType},
      );
      final data = response.data;
      _logger.d('获取预签名URL: $data');
      if (data != null && data['success'] == true) {
        final result = data['data'];
        return UploadUrlResult(
          fileUrl: result['fileUrl']?.toString(),
          uploadUrl: result['uploadUrl']?.toString(),
          key: result['key']?.toString(),
        );
      }
      _logger.e('获取预签名URL失败: ${data?['message']}');
      return null;
    } catch (e) {
      _logger.e('获取预签名URL异常: $e');
      return null;
    }
  }

  Future<bool> uploadToR2(
    String uploadUrl,
    List<int> fileBytes,
    String contentType, {
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    int maxRetries = 3;
    int retryDelay = 2000;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        if (cancelToken?.isCancelled ?? false) {
          _logger.d('上传已取消');
          return false;
        }
        _logger.d(
          '开始上传到R2 (尝试 $attempt/$maxRetries), URL: $uploadUrl, 大小: ${fileBytes.length}, ContentType: $contentType',
        );
        final dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(minutes: 2),
            receiveTimeout: const Duration(minutes: 5),
            sendTimeout: const Duration(minutes: 5),
          ),
        );

        _logger.d('开始发送PUT请求...');
        final response = await dio.put(
          uploadUrl,
          data: fileBytes,
          cancelToken: cancelToken,
          options: Options(
            headers: {'Content-Type': contentType, 'Content-Length': fileBytes.length},
            validateStatus: (status) => true,
          ),
          onSendProgress: (sent, total) {
            // _logger.d('上传进度: $sent/$total');
            onProgress?.call(sent, total);
          },
        );
        // _logger.d('上传到R2响应: ${response.statusCode}, body: ${response.data}');
        if (response.statusCode == 200 || response.statusCode == 201) {
          _logger.d('上传到R2成功');
          return true;
        }
        _logger.e('上传到R2失败: ${response.statusCode}');
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel) {
          _logger.d('上传被用户取消');
          return false;
        }
        _logger.e('上传到R2失败 (尝试 $attempt/$maxRetries): $e');

        if (attempt < maxRetries) {
          _logger.d('等待 ${retryDelay}ms 后重试...');
          await Future.delayed(Duration(milliseconds: retryDelay));
          retryDelay *= 2;
        }
      } catch (e) {
        _logger.e('上传到R2失败 (尝试 $attempt/$maxRetries): $e');

        if (attempt < maxRetries) {
          _logger.d('等待 ${retryDelay}ms 后重试...');
          await Future.delayed(Duration(milliseconds: retryDelay));
          retryDelay *= 2;
        }
      }
    }

    _logger.e('所有重试都失败了');
    return false;
  }
}
