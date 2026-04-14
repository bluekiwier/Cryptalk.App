import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/rendering.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/account_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/avatar_widget.dart';
import '../contacts/scanner_page.dart';
import '../../config/app_config.dart';

/// 我的二维码页面
class MyQrCodePage extends StatefulWidget {
  const MyQrCodePage({super.key});

  @override
  State<MyQrCodePage> createState() => _MyQrCodePageState();
}

class _MyQrCodePageState extends State<MyQrCodePage> {
  final GlobalKey _qrKey = GlobalKey();
  bool _isSaving = false;

  /// 截取二维码卡片并保存为临时文件
  Future<String?> _captureQrImage() async {
    try {
      final RenderRepaintBoundary? boundary = _qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('无法找到二维码区域'.tr());

      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('图片转换失败'.tr());

      final Uint8List pngBytes = byteData.buffer.asUint8List();
      final tempDir = await getTemporaryDirectory();
      final String filePath = '${tempDir.path}/cryptalk_qr_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File(filePath);
      await file.writeAsBytes(pngBytes);
      return filePath;
    } catch (e) {
      rethrow;
    }
  }

  /// 保存二维码到相册
  Future<void> _saveQrCode() async {
    if (_isSaving) return;

    setState(() => _isSaving = true);

    try {
      // 1. 获取权限
      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        await Gal.requestAccess();
      }

      // 2. 截屏
      final filePath = await _captureQrImage();
      if (filePath == null) throw Exception('截屏失败'.tr());

      // 3. 导出到相册
      await Gal.putImage(filePath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('二维码已保存到相册！'.tr()),
            backgroundColor: AppTheme.onlineColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${'保存失败:'.tr()} $e'),
            backgroundColor: AppTheme.badgeColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// 分享二维码图片
  Future<void> _shareQrCode() async {
    if (_isSaving) return;

    setState(() => _isSaving = true);

    try {
      // 1. 截屏
      final filePath = await _captureQrImage();
      if (filePath == null) throw Exception('截屏失败'.tr());

      // 2. 调用分享
      final user = AccountService().currentUser;
      final String text = '这是 {name} 的 {app} 二维码，快来加我为朋友吧！'.tr(
        namedArgs: {'name': user?.nickname ?? '', 'app': AppConfig.appName},
      );

      await SharePlus.instance.share(
        ShareParams(files: [XFile(filePath)], text: text, subject: '${'分享'.tr()} ${AppConfig.appName} ${'二维码'.tr()}'),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${'分享失败:'.tr()} $e'),
            backgroundColor: AppTheme.badgeColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AccountService().currentUser;

    if (user == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('请先登录'.tr()),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: () => Navigator.pop(context), child: Text('返回'.tr())),
            ],
          ),
        ),
      );
    }

    final String qrData = 'cryptalk:add_friend?id=${user.id}&account=${user.account}';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          '我的二维码'.tr(),
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded, color: Colors.white),
            onPressed: _shareQrCode,
          ),
          const SizedBox(width: 8),
        ],
        flexibleSpace: Container(decoration: AppTheme.getAppBarDecoration(context)),
      ),
      body: SingleChildScrollView(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 二维码卡片 - 包裹 RepaintBoundary 以便截取
              RepaintBoundary(
                key: _qrKey,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 40),
                  padding: const EdgeInsets.all(30),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 顶部用户信息
                      Row(
                        children: [
                          AvatarWidget(avatar: user.avatar, size: 50),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user.nickname,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1A1D26),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${'账号:'.tr()} ${user.account}',
                                  style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 30),

                      // 二维码
                      QrImageView(
                        data: qrData,
                        version: QrVersions.auto,
                        size: 240.0,
                        eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.circle, color: Color(0xFF1A1D26)),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.circle,
                          color: Color(0xFF1A1D26),
                        ),
                      ),

                      const SizedBox(height: 30),

                      // 底部提示
                      Text(
                        '扫一扫上面的二维码图案，加我为朋友。'.tr(),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: const Color(0xFF6B7280).withValues(alpha: 0.8)),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 40),

              // 操作按钮
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildActionButton(
                    context,
                    icon: _isSaving ? Icons.sync_rounded : Icons.download_rounded,
                    label: _isSaving ? '保存中...'.tr() : '保存图片'.tr(),
                    onTap: _saveQrCode,
                  ),
                  const SizedBox(width: 40),
                  _buildActionButton(
                    context,
                    icon: Icons.qr_code_scanner_rounded,
                    label: '扫一扫'.tr(),
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const ScannerPage()));
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppTheme.primaryColor.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: _isSaving && icon == Icons.sync_rounded
                ? const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                    ),
                  )
                : Icon(icon, color: AppTheme.primaryColor, size: 28),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
