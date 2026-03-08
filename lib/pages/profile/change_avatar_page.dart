import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/app_theme.dart';
import '../../services/account_service.dart';

/// 更换头像页面
class ChangeAvatarPage extends StatefulWidget {
  const ChangeAvatarPage({super.key});

  @override
  State<ChangeAvatarPage> createState() => _ChangeAvatarPageState();
}

class _ChangeAvatarPageState extends State<ChangeAvatarPage> {
  final ImagePicker _picker = ImagePicker();
  final AccountService _accountService = AccountService();
  bool _isUploading = false;
  File? _imageFile;

  /// 从相册或相机选择图片
  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        setState(() {
          _imageFile = File(pickedFile.path);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('选择图片失败')));
      }
    }
  }

  /// 执行上传操作
  Future<void> _uploadAvatar() async {
    if (_imageFile == null || _isUploading) return;

    setState(() => _isUploading = true);

    try {
      // 模拟上传逻辑，实际应用中需调用 API
      // final result = await _userService.changeAvatar(_imageFile!.path);

      // 模拟延迟
      await Future.delayed(const Duration(seconds: 2));

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('头像更新成功（模拟）'), backgroundColor: AppTheme.onlineColor));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('更像头像失败'), backgroundColor: AppTheme.badgeColor));
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _accountService.currentUser;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: Container(
          decoration: const BoxDecoration(gradient: AppTheme.headerGradient),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text(
              '个人头像',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1),
            ),
            centerTitle: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.more_horiz_rounded, color: Colors.white),
                onPressed: () => _showPickerOptions(context),
              ),
            ],
          ),
        ),
      ),
      body: Stack(
        children: [
          // 头像预览区域 - 垂直居中
          Center(
            child: Hero(
              tag: 'avatar_large',
              child: Container(
                width: MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.width,
                decoration: const BoxDecoration(color: Colors.white10),
                child: _imageFile != null
                    ? Image.file(_imageFile!, fit: BoxFit.cover)
                    : _buildOriginalAvatar(user?.avatar),
              ),
            ),
          ),
          // 底部操作按钮
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.of(context).padding.bottom + 30,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_imageFile != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => setState(() => _imageFile = null),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white54),
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('取消'),
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _isUploading ? null : _uploadAvatar,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                            child: _isUploading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text('确定使用'),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  TextButton.icon(
                    onPressed: () => _showPickerOptions(context),
                    icon: const Icon(Icons.camera_alt_rounded, color: Colors.white70),
                    label: const Text('更换头像', style: TextStyle(color: Colors.white70, fontSize: 16)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 渲染原始头像内容
  Widget _buildOriginalAvatar(String? avatar) {
    if (avatar == null || avatar.isEmpty) {
      return Image.asset('assets/images/default_user_avatar.png', fit: BoxFit.cover);
    }

    if (avatar.startsWith('http')) {
      return Image.network(
        avatar,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildDefaultAvatar(),
      );
    }

    if (avatar.contains('/')) {
      return Image.asset(
        avatar,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildDefaultAvatar(),
      );
    }

    return Center(
      child: Text(avatar, style: const TextStyle(fontSize: 100, color: Colors.white24)),
    );
  }

  /// 默认兜底头像
  Widget _buildDefaultAvatar() {
    return Image.asset('assets/images/default_user_avatar.png', fit: BoxFit.cover);
  }

  void _showPickerOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: Colors.white),
              title: const Text('从相册选择', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded, color: Colors.white),
              title: const Text('拍照', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}
