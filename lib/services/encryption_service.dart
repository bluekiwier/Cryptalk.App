import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:pointycastle/asymmetric/api.dart' show RSAPublicKey, RSAPrivateKey;
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';
import 'package:cryptography/cryptography.dart';
import '../config/api_config.dart';

class EncryptionService {
  static final EncryptionService _instance = EncryptionService._internal();
  factory EncryptionService() => _instance;
  EncryptionService._internal();

  final Logger _logger = Logger();
  final algorithm = AesGcm.with256bits();

  String? _publicKeyString;
  String? _keyVersion;

  /// AES-256-GCM 加密数据
  Future<Map<String, String>> aesGcmEncrypt(dynamic data, SecretKey key) async {
    final nonce = algorithm.newNonce(); // 12 bytes

    final secretBox = await algorithm.encrypt(utf8.encode(jsonEncode(data)), secretKey: key, nonce: nonce);

    return {
      'nonce': base64Encode(nonce),
      'data': base64Encode(secretBox.cipherText),
      'tag': base64Encode(secretBox.mac.bytes),
    };
  }

  /// AES-256-GCM 解密数据
  Future<dynamic> aesGcmDecrypt(Map<String, String> encryptedData, SecretKey key) async {
    final nonce = base64Decode(encryptedData['nonce']!);
    final cipherText = base64Decode(encryptedData['data']!);
    final tag = base64Decode(encryptedData['tag']!);

    final secretBox = SecretBox(cipherText, nonce: nonce, mac: Mac(tag));
    final decrypted = await algorithm.decrypt(secretBox, secretKey: key);

    return jsonDecode(utf8.decode(decrypted));
  }

  /// 同步获取公钥
  Future<void> syncPublicKey({bool forceRefresh = false}) async {
    final prefs = await SharedPreferences.getInstance();
    if (!forceRefresh) {
      final cachedKey = prefs.getString('rsa_public_key');
      final cachedVersion = prefs.getString('rsa_key_version');

      if (cachedKey != null && cachedVersion != null) {
        _publicKeyString = cachedKey;
        _keyVersion = cachedVersion;
        return;
      }
    }

    try {
      final dio = Dio(BaseOptions(baseUrl: ApiConfig.baseUrl));
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final response = await dio.get('/api/account/public-key?t=$timestamp');
      if (response.statusCode == 200 && response.data['success'] == true) {
        final data = response.data['data'];
        _publicKeyString = data['key'];
        _keyVersion = data['version'];

        await prefs.setString('rsa_public_key', _publicKeyString!);
        await prefs.setString('rsa_key_version', _keyVersion!);
      } else {
        _logger.e('获取公钥失败: ${response.data}');
      }
    } catch (e) {
      _logger.e('请求公钥异常: $e');
    }
  }

  /// 使用 RSA-OAEP 公钥加密 AES Key
  Future<String> encryptAesKeyWithRSA(List<int> aesKeyBytes) async {
    if (_publicKeyString == null) {
      await syncPublicKey();
    }

    if (_publicKeyString == null) {
      throw Exception('无法获取RSA公钥');
    }

    String pubKeyData = _publicKeyString!;
    final buffer = StringBuffer();
    for (int i = 0; i < pubKeyData.length; i += 64) {
      buffer.writeln(pubKeyData.substring(i, i + 64 > pubKeyData.length ? pubKeyData.length : i + 64));
    }

    final parser = encrypt.RSAKeyParser();
    RSAPublicKey? publicKey;

    try {
      String publicPem = '-----BEGIN PUBLIC KEY-----\n${buffer.toString()}-----END PUBLIC KEY-----';
      publicKey = parser.parse(publicPem) as RSAPublicKey;
    } catch (e1) {
      try {
        String privatePem = '-----BEGIN PRIVATE KEY-----\n${buffer.toString()}-----END PRIVATE KEY-----';
        final privKey = parser.parse(privatePem) as RSAPrivateKey;
        // 兼容可能服务端错误下发了私钥的情况，安全地从中提取出公钥参数
        publicKey = RSAPublicKey(privKey.modulus!, privKey.publicExponent!);
      } catch (e2) {
        throw Exception('无法解析RSA密钥: $e2');
      }
    }

    final encrypter = encrypt.Encrypter(
      encrypt.RSA(publicKey: publicKey, encoding: encrypt.RSAEncoding.OAEP, digest: encrypt.RSADigest.SHA256),
    );

    final encrypted = encrypter.encryptBytes(aesKeyBytes);
    return encrypted.base64;
  }

  /// 使用 AES 加密数据
  String encryptData(dynamic data, encrypt.Key aesKey, encrypt.IV aesIv) {
    final encrypter = encrypt.Encrypter(encrypt.AES(aesKey, mode: encrypt.AESMode.cbc, padding: 'PKCS7'));
    final stringData = jsonEncode(data);
    final encrypted = encrypter.encrypt(stringData, iv: aesIv);
    return encrypted.base64;
  }

  /// 使用 AES 解密数据
  dynamic decryptData(String encryptedBase64, encrypt.Key aesKey, encrypt.IV aesIv) {
    final encrypter = encrypt.Encrypter(encrypt.AES(aesKey, mode: encrypt.AESMode.cbc, padding: 'PKCS7'));
    final decrypted = encrypter.decrypt64(encryptedBase64, iv: aesIv);
    return jsonDecode(decrypted);
  }

  String? get keyVersion => _keyVersion;
}

/// 数据加密请求拦截器
class EncryptInterceptor extends Interceptor {
  final Logger _logger = Logger();

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final obfuscate = options.extra['obfuscate'] == true; // 是否需要加密混淆
    final isObfuscated = options.extra['_isObfuscated'] == true; // 是否已经混淆

    if (!obfuscate || isObfuscated) {
      return handler.next(options);
    }

    final method = options.method.toUpperCase();
    if (method == 'POST' || method == 'PUT' || method == 'DELETE') {
      try {
        final encryptionService = EncryptionService();
        await encryptionService.syncPublicKey();

        // 1. 生成 AES key (256-bit)
        final aesKeyBytes = encrypt.Key.fromSecureRandom(32).bytes;
        final aesKey = SecretKey(aesKeyBytes);

        // 2. 原始数据
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final nonce = const Uuid().v4();

        // _logger.d("随机数: $nonce");

        options.extra['originalData'] ??= options.data; // 备份原始请求数据以便在遇到406时重发
        final actualData = options.extra['originalData'];
        final payload = {'data': actualData ?? {}, 'timestamp': timestamp, 'nonce': nonce};

        // 3. AES-GCM 加密
        final encrypted = await encryptionService.aesGcmEncrypt(payload, aesKey);

        // 4. RSA-OAEP 加密 AES key
        final encryptedKey = await encryptionService.encryptAesKeyWithRSA(aesKeyBytes);

        // 5. 替换请求体
        options.data = {
          'data': encrypted['data'],
          'key': encryptedKey,
          'nonce': encrypted['nonce'],
          'tag': encrypted['tag'],
          'version': encryptionService.keyVersion ?? '',
        };

        options.extra['_isObfuscated'] = true;
        options.extra['aesContext'] = {'key': aesKey};

        _logger.d(
          "🔒 请求加密完成: \n"
          "URL: ${options.uri}\n"
          "加密前: $actualData\n"
          "加密后: ${options.data}",
        );
      } catch (e) {
        EncryptionService()._logger.e("请求加密失败: $e");
        // 根据业务需求，加密失败可以直接继续或抛出异常
      }
    }

    return handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) async {
    if (response.data is Map && (response.statusCode == 406 || response.data['code'] == 406)) {
      final retryRes = await _retryRequest(response.requestOptions);
      if (retryRes != null) return handler.resolve(retryRes);
    }

    if (response.statusCode == 200 && response.data is Map && response.data['payload'] != null) {
      try {
        final aesContext = response.requestOptions.extra['aesContext'];
        if (aesContext != null) {
          final aesKey = aesContext['key'];

          // 新版 AES-GCM
          final payloadMap = Map<String, String>.from(response.data['payload']);
          final decryptedData = await EncryptionService().aesGcmDecrypt(payloadMap, aesKey);

          response.data = decryptedData;

          EncryptionService()._logger.d(
            "🔓 响应解密完成: \n"
            "URL: ${response.requestOptions.uri}\n"
            "解密后: ${response.data}",
          );
        }
      } catch (e) {
        EncryptionService()._logger.e("响应解密失败: $e");
      }
    }
    return handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 406 || (err.response?.data is Map && err.response?.data['code'] == 406)) {
      final retryRes = await _retryRequest(err.requestOptions);
      if (retryRes != null) return handler.resolve(retryRes);
    }
    return handler.next(err);
  }

  /// 公钥版本可能不匹配 (406)，触发重新获取公钥并重试请求
  Future<Response?> _retryRequest(RequestOptions requestOptions) async {
    try {
      await EncryptionService().syncPublicKey(forceRefresh: true);

      final retryDio = Dio(
        BaseOptions(
          baseUrl: requestOptions.baseUrl,
          connectTimeout: requestOptions.connectTimeout,
          receiveTimeout: requestOptions.receiveTimeout,
          sendTimeout: requestOptions.sendTimeout,
        ),
      );

      // 添加加密拦截器以执行二次加密
      retryDio.interceptors.add(EncryptInterceptor());

      // 构建清除了已被加密标记的新选项，使请求被重新加密
      final extraMap = Map<String, dynamic>.from(requestOptions.extra);
      extraMap.remove('_isObfuscated');

      final options = Options(method: requestOptions.method, headers: requestOptions.headers, extra: extraMap);

      final originalData = extraMap['originalData'] ?? requestOptions.data;

      return await retryDio.request(
        requestOptions.path,
        data: originalData,
        queryParameters: requestOptions.queryParameters,
        options: options,
      );
    } catch (e) {
      EncryptionService()._logger.e("重试加密请求失败: $e");
      return null;
    }
  }
}
