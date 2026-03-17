import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import '../../theme/app_theme.dart';
import '../../services/account_service.dart';
import '../../services/user_service.dart';
import '../../services/file_service.dart';

/// 更换头像页面
class ChangeAvatarPage extends StatefulWidget {
  const ChangeAvatarPage({super.key});

  @override
  State<ChangeAvatarPage> createState() => _ChangeAvatarPageState();
}

class _ChangeAvatarPageState extends State<ChangeAvatarPage> {
  final ImagePicker _picker = ImagePicker();
  final AccountService _accountService = AccountService();
  final UserService _userService = UserService();
  final GlobalKey _avatarKey = GlobalKey();
  bool _isUploading = false;
  bool _isSavingLocal = false;
  File? _imageFile;

  /// 从相册或相机选择图片并裁剪
  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(source: source);

      if (pickedFile != null && mounted) {
        final croppedFile = await ImageCropper().cropImage(
          sourcePath: pickedFile.path,
          maxWidth: 512,
          maxHeight: 512,
          aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: '裁剪头像',
              toolbarColor: AppTheme.primaryColor,
              toolbarWidgetColor: Colors.white,
              initAspectRatio: CropAspectRatioPreset.square,
              lockAspectRatio: true,
            ),
            IOSUiSettings(title: '裁剪头像', aspectRatioLockEnabled: true),
          ],
        );

        if (croppedFile != null) {
          setState(() {
            _imageFile = File(croppedFile.path);
          });
        }
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
      final filePath = _imageFile!.absolute.path;
      final outPath = "${Directory.systemTemp.path}/avatar_${DateTime.now().millisecondsSinceEpoch}.png";

      // 1. 压缩和调整大小 (512x512, PNG)
      final result = await FlutterImageCompress.compressAndGetFile(
        filePath,
        outPath,
        quality: 90,
        minWidth: 512,
        minHeight: 512,
        format: CompressFormat.png,
      );

      if (result == null) throw Exception("压缩图片失败");

      final compressedFile = File(result.path);
      final fileSize = await compressedFile.length();

      // 2. 获取上传凭证
      final currentUser = _accountService.currentUser;
      final userId = currentUser?.id ?? '0';
      final now = DateTime.now();
      final timeStr =
          "${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}";
      final fileName = "${userId}_$timeStr.png";

      final uploadResult = await FileService().createUploadUrl("image/png", fileName, fileSize, "avatar");

      if (uploadResult == null || !uploadResult.isSuccess) {
        throw Exception("获取上传凭证失败");
      }

      // 3. 上传到 R2
      final fileBytes = await compressedFile.readAsBytes();
      final uploaded = await FileService().uploadToR2(uploadResult.uploadUrl!, fileBytes, "image/png");

      if (!uploaded) {
        throw Exception("上传图片到存储失败");
      }

      // 4. 更新后端头像
      final success = await _userService.changeAvatar(uploadResult.fileUrl!);

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('头像更新成功'), backgroundColor: AppTheme.onlineColor));
          Navigator.pop(context, true);
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('头像更新失败'), backgroundColor: AppTheme.badgeColor));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('操作失败: $e'), backgroundColor: AppTheme.badgeColor));
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  /// 保存图片到相册
  Future<void> _saveImage() async {
    if (_isSavingLocal) return;

    setState(() => _isSavingLocal = true);

    try {
      // 1. 获取权限
      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        await Gal.requestAccess();
      }

      // 2. 截取图片
      final RenderRepaintBoundary? boundary = _avatarKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;

      if (boundary == null) {
        throw Exception('无法找到头像区域');
      }

      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) {
        throw Exception('图片转换失败');
      }

      final Uint8List pngBytes = byteData.buffer.asUint8List();

      // 3. 临时保存并导出到相册
      final tempDir = await getTemporaryDirectory();
      final String filePath = '${tempDir.path}/avatar_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File(filePath);
      await file.writeAsBytes(pngBytes);

      await Gal.putImage(file.path);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('头像已保存到相册！'), backgroundColor: AppTheme.onlineColor));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败: $e'), backgroundColor: AppTheme.badgeColor));
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingLocal = false);
      }
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
          decoration: AppTheme.getAppBarDecoration(context),
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
              child: RepaintBoundary(
                key: _avatarKey,
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
            ListTile(
              leading: const Icon(Icons.save_alt_rounded, color: Colors.white),
              title: Text(_isSavingLocal ? '保存中...' : '保存图片', style: const TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _saveImage();
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}
