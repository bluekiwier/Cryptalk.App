import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import '../../services/account_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/avatar_widget.dart';
import '../contacts/scanner_page.dart';

/// 我的二维码页面
class MyQrCodePage extends StatefulWidget {
  const MyQrCodePage({super.key});

  @override
  State<MyQrCodePage> createState() => _MyQrCodePageState();
}

class _MyQrCodePageState extends State<MyQrCodePage> {
  final GlobalKey _qrKey = GlobalKey();
  bool _isSaving = false;

  /// 保存二维码到相册
  Future<void> _saveQrCode() async {
    if (_isSaving) return;

    setState(() => _isSaving = true);

    try {
      // 1. 获取权限 (gal 权限检查)
      // 注意：Gal.hasAccess 并不能完全代表存储权限，但在 gal 2.x 中是推荐的检查方式之一
      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        await Gal.requestAccess();
      }

      // 2. 截取图片
      final RenderRepaintBoundary? boundary =
          _qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;

      if (boundary == null) {
        throw Exception('无法找到二维码区域');
      }

      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );

      if (byteData == null) {
        throw Exception('图片转换失败');
      }

      final Uint8List pngBytes = byteData.buffer.asUint8List();

      // 3. 临时保存并导出到相册
      final tempDir = await getTemporaryDirectory();
      final String filePath =
          '${tempDir.path}/qr_code_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File(filePath);
      await file.writeAsBytes(pngBytes);

      await Gal.putImage(file.path);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('二维码已保存到相册！'),
            backgroundColor: AppTheme.onlineColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存失败: $e'),
            backgroundColor: AppTheme.badgeColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
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
              const Text('请先登录'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('返回'),
              ),
            ],
          ),
        ),
      );
    }

    final String qrData =
        'cryptalk:add_friend?id=${user.id}&account=${user.account}';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          '我的二维码',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded, color: Colors.white),
            onPressed: () {
              // TODO: 实现分享
            },
          ),
          const SizedBox(width: 8),
        ],
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppTheme.headerGradient),
        ),
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
                                  '账号: ${user.account}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF6B7280),
                                  ),
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
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.circle,
                          color: Color(0xFF1A1D26),
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.circle,
                          color: Color(0xFF1A1D26),
                        ),
                      ),

                      const SizedBox(height: 30),

                      // 底部提示
                      Text(
                        '扫一扫上面的二维码图案，加我为好友',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: const Color(0xFF6B7280).withValues(alpha: 0.8),
                        ),
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
                    icon: _isSaving
                        ? Icons.sync_rounded
                        : Icons.download_rounded,
                    label: _isSaving ? '保存中...' : '保存图片',
                    onTap: _saveQrCode,
                  ),
                  const SizedBox(width: 40),
                  _buildActionButton(
                    context,
                    icon: Icons.qr_code_scanner_rounded,
                    label: '扫一扫',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ScannerPage(),
                        ),
                      );
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
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: _isSaving && icon == Icons.sync_rounded
                ? const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppTheme.primaryColor,
                      ),
                    ),
                  )
                : Icon(icon, color: AppTheme.primaryColor, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
