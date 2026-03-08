import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// 头像组件
/// 支持 emoji 头像、在线状态指示和群组标识
class AvatarWidget extends StatelessWidget {
  final String avatar;
  final double size;
  final bool showOnline;
  final bool isOnline;
  final bool isGroup;

  const AvatarWidget({
    super.key,
    required this.avatar,
    this.size = 48,
    this.showOnline = false,
    this.isOnline = false,
    this.isGroup = false,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 头像主体
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isGroup
                  ? [const Color(0xFFE8F5FF), const Color(0xFFF0F0FF)]
                  : [const Color(0xFFF5F0FF), const Color(0xFFFFF0F5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(size * 0.3),
            boxShadow: [
              BoxShadow(color: AppTheme.primaryColor.withValues(alpha: 0.2), blurRadius: 4, offset: const Offset(0, 2)),
            ],
          ),
          child: ClipRRect(borderRadius: BorderRadius.circular(size * 0.15), child: _buildAvatarContent()),
        ),

        // 在线状态指示器
        if (showOnline)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: size * 0.25,
              height: size * 0.25,
              decoration: BoxDecoration(
                color: isOnline ? AppTheme.onlineColor : AppTheme.offlineColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  if (isOnline)
                    BoxShadow(color: AppTheme.onlineColor.withValues(alpha: 0.4), blurRadius: 4, spreadRadius: 1),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// 渲染头像内容
  Widget _buildAvatarContent() {
    // 1. 如果头像为空，使用默认图片
    if (avatar.isEmpty) {
      return Image.asset('assets/images/default_user_avatar.png', width: size, height: size, fit: BoxFit.cover);
    }

    // 2. 如果是网络图片
    if (avatar.startsWith('http')) {
      return Image.network(
        avatar,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildErrorAvatar(),
      );
    }

    // 3. 如果是本地资产路径 (通常包含 /)
    if (avatar.contains('/')) {
      return Image.asset(
        avatar,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildErrorAvatar(),
      );
    }

    // 4. 其它情况视为 Emoji 或文字
    return Center(
      child: Text(avatar, style: TextStyle(fontSize: size * 0.5)),
    );
  }

  /// 渲染错误时的兜底头像
  Widget _buildErrorAvatar() {
    return Image.asset('assets/images/default_user_avatar.png', width: size, height: size, fit: BoxFit.cover);
  }
}
