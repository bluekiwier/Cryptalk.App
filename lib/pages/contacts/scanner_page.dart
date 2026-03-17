import 'package:cryptalk/services/conversation_service.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/friend_service.dart';
import '../../theme/app_theme.dart';
import '../profile/my_qr_code_page.dart';

/// 扫码页面
class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> with SingleTickerProviderStateMixin {
  final MobileScannerController _controller = MobileScannerController();
  final FriendService _friendService = FriendService();
  final ConversationService _conversationService = ConversationService();
  final ImagePicker _picker = ImagePicker();
  bool _isProcessing = false;

  late AnimationController _animationController;
  late Animation<double> _scanAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);

    _scanAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _animationController.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// 处理扫描结果
  Future<void> _handleBarcode(BarcodeCapture capture) async {
    if (_isProcessing) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final String? code = barcodes.first.rawValue;
    if (code == null || !code.startsWith('cryptalk:')) return;

    setState(() => _isProcessing = true);

    // 解析内容 cryptalk:add_friend?id={id}&account={account}
    final uri = Uri.parse(code);
    if (uri.scheme == 'cryptalk' && uri.path == 'add_friend') {
      final String? account = uri.queryParameters['account'];
      final String? id = uri.queryParameters['id'];

      final String target = account ?? id ?? '';

      if (target.isNotEmpty) {
        // 尝试添加好友
        final result = await _friendService.addFriend(target);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.message),
              backgroundColor: result.success ? AppTheme.onlineColor : AppTheme.badgeColor,
              behavior: SnackBarBehavior.floating,
            ),
          );
          if (result.success) {
            Navigator.pop(context, true);
          } else {
            setState(() => _isProcessing = false);
          }
        }
      } else {
        setState(() => _isProcessing = false);
      }
    } else if (uri.scheme == 'cryptalk' && uri.path == 'join_group') {
      // 解析内容 cryptalk:join_group?id=${conversationId}
      final String? conversationId = uri.queryParameters['id'];
      if (conversationId != null) {
        // 尝试加入群聊
        final result = await _conversationService.joinGroup(conversationId);

        if (result.success == true && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.message),
              backgroundColor: result.success ? AppTheme.onlineColor : AppTheme.badgeColor,
              behavior: SnackBarBehavior.floating,
            ),
          );
          if (result.success) {
            Navigator.pop(context, true);
          } else {
            setState(() => _isProcessing = false);
          }
        }
      } else {
        setState(() => _isProcessing = false);
      }
    } else {
      setState(() => _isProcessing = false);
    }
  }

  /// 从相册选择并扫描
  Future<void> _pickAndScanImage() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image == null) return;

      final BarcodeCapture? capture = await _controller.analyzeImage(image.path);
      if (capture != null && capture.barcodes.isNotEmpty) {
        await _handleBarcode(capture);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('未在图片中识别到有效的二维码'),
              backgroundColor: AppTheme.badgeColor,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('识别异常: $e'),
            backgroundColor: AppTheme.badgeColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: AppBar(
          title: const Text('扫一扫', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1)),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            // 手电筒
            ValueListenableBuilder<MobileScannerState>(
              valueListenable: _controller,
              builder: (context, state, child) {
                final torchState = state.torchState;
                return IconButton(
                  icon: Icon(
                    torchState == TorchState.on ? Icons.flash_on : Icons.flash_off,
                    color: torchState == TorchState.on ? Colors.yellow : Colors.white,
                  ),
                  onPressed: () => _controller.toggleTorch(),
                );
              },
            ),
            // 切换镜头
            IconButton(icon: const Icon(Icons.cameraswitch_rounded), onPressed: () => _controller.switchCamera()),
          ],
        ),
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _handleBarcode),
          // 扫描框 Overlay
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 250,
                  height: 250,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Stack(
                    children: [
                      // 四角装饰
                      ..._buildCorners(),
                      // 扫描动画线
                      AnimatedBuilder(
                        animation: _scanAnimation,
                        builder: (context, child) {
                          return Positioned(
                            top: _scanAnimation.value * 240, // 略小于容器高度使其不超出
                            left: 10,
                            right: 10,
                            child: Container(
                              height: 2,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    AppTheme.primaryColor.withValues(alpha: 0.1),
                                    AppTheme.primaryColor,
                                    AppTheme.primaryColor.withValues(alpha: 0.1),
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.primaryColor.withValues(alpha: 0.5),
                                    blurRadius: 10,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  '将二维码放入框内，即可自动扫描',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 60),
                // 底部操作按钮
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildBottomButton(
                      icon: Icons.qr_code_rounded,
                      label: '我的二维码',
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const MyQrCodePage()));
                      },
                    ),
                    const SizedBox(width: 60),
                    _buildBottomButton(icon: Icons.photo_library_rounded, label: '相册', onTap: _pickAndScanImage),
                  ],
                ),
              ],
            ),
          ),
          if (_isProcessing)
            Container(
              color: Colors.black.withValues(alpha: 0.5),
              child: const Center(child: CircularProgressIndicator(color: Colors.white)),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomButton({required IconData icon, required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
  }

  List<Widget> _buildCorners() {
    const double length = 20;
    const double width = 4;
    return [
      // 左上
      Positioned(
        top: 0,
        left: 0,
        child: _cornerBlock(top: true, left: true, l: length, w: width),
      ),
      // 右上
      Positioned(
        top: 0,
        right: 0,
        child: _cornerBlock(top: true, left: false, l: length, w: width),
      ),
      // 左下
      Positioned(
        bottom: 0,
        left: 0,
        child: _cornerBlock(top: false, left: true, l: length, w: width),
      ),
      // 右下
      Positioned(
        bottom: 0,
        right: 0,
        child: _cornerBlock(top: false, left: false, l: length, w: width),
      ),
    ];
  }

  Widget _cornerBlock({required bool top, required bool left, required double l, required double w}) {
    return Container(
      width: l,
      height: l,
      decoration: BoxDecoration(
        border: Border(
          top: top ? BorderSide(color: AppTheme.primaryColor, width: w) : BorderSide.none,
          bottom: !top ? BorderSide(color: AppTheme.primaryColor, width: w) : BorderSide.none,
          left: left ? BorderSide(color: AppTheme.primaryColor, width: w) : BorderSide.none,
          right: !left ? BorderSide(color: AppTheme.primaryColor, width: w) : BorderSide.none,
        ),
      ),
    );
  }
}
