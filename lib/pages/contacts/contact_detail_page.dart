import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../models/user.dart';
import '../../widgets/avatar_widget.dart';
import '../../services/friend_service.dart';
import '../chat/chat_detail_page.dart';
import '../../models/conversation.dart';

/// 联系人详情页面
/// 展示联系人的个人信息和操作按钮
class ContactDetailPage extends StatelessWidget {
  final User user;

  const ContactDetailPage({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg,
      body: CustomScrollView(
        slivers: [
          // 带头像的折叠 AppBar
          SliverAppBar(
            pinned: true,
            elevation: 0,
            scrolledUnderElevation: 0,
            backgroundColor: Colors.transparent,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text(
              '联系人详情',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1),
            ),
            centerTitle: true,
            actions: [
              PopupMenuButton<String>(
                offset: const Offset(0, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                icon: const Icon(Icons.more_horiz_rounded, color: Colors.white, size: 22),
                onSelected: (value) => _handleMenuAction(context, value),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'block',
                    child: Row(
                      children: [
                        Icon(Icons.block_rounded, size: 20, color: AppTheme.textPrimary),
                        SizedBox(width: 12),
                        Text('加入黑名单'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'unblock',
                    child: Row(
                      children: [
                        Icon(Icons.person_add_disabled_rounded, size: 20, color: AppTheme.textPrimary),
                        SizedBox(width: 12),
                        Text('移除黑名单'),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline_rounded, size: 20, color: AppTheme.badgeColor),
                        SizedBox(width: 12),
                        Text('删除好友', style: TextStyle(color: AppTheme.badgeColor)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
            flexibleSpace: Container(decoration: AppTheme.getAppBarDecoration(context)),
          ),

          // 顶部渐变背景信息区域 - 移入 body
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 32),
              decoration: BoxDecoration(
                gradient: Theme.of(context).brightness == Brightness.dark ? null : AppTheme.headerGradient,
                color: Theme.of(context).brightness == Brightness.dark ? AppTheme.appBarDarkBg : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 大头像
                  AvatarWidget(avatar: user.avatar, size: 88, showOnline: true, online: user.online),
                  const SizedBox(height: 16),
                  // 名字
                  Text(
                    user.nickname,
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  // 在线状态
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(user.online ? '在线' : '离线', style: const TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                ],
              ),
            ),
          ),

          // 操作按钮
          SliverToBoxAdapter(child: _buildActionButtons(context)),

          // 个人信息卡片
          SliverToBoxAdapter(child: _buildInfoCard()),

          // 更多操作
          SliverToBoxAdapter(child: _buildMoreActions()),
        ],
      ),
    );
  }

  /// 操作按钮行
  Widget _buildActionButtons(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: _buildActionButton(
              icon: Icons.chat_bubble_rounded,
              label: '发消息',
              isPrimary: true,
              onTap: () {
                // 构造一个临时的 Conversation 对象用于私聊
                final conv = Conversation(
                  id: user.id, // 用用户ID作为初始ID
                  chatUserId: user.id,
                  title: user.nickname,
                  avatar: user.avatar,
                  isGroup: false,
                );
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => ChatDetailPage(conversation: conv)),
                );
              },
            ),
          ),
          // const SizedBox(width: 12),
          // Expanded(
          //   child: _buildActionButton(
          //     icon: Icons.videocam_rounded,
          //     label: '视频通话',
          //     onTap: () {},
          //   ),
          // ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildActionButton(icon: Icons.phone_rounded, label: '语音通话', onTap: () {}),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    bool isPrimary = false,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: isPrimary ? AppTheme.headerGradient : null,
          color: isPrimary ? null : Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: (isPrimary ? AppTheme.primaryColor : Colors.black).withValues(alpha: isPrimary ? 0.2 : 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: isPrimary ? Colors.white : AppTheme.primaryColor, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isPrimary ? Colors.white : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 信息卡片
  Widget _buildInfoCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '个人信息',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 16),
          _buildInfoRow(
            Icons.edit_note_rounded,
            '个性签名',
            (user.signature?.isNotEmpty == true) ? user.signature! : '这个人很懒，什么都没有留下。',
          ),
          const Divider(height: 24),
          _buildInfoRow(Icons.phone_outlined, '手机号', user.mobile),
          const Divider(height: 24),
          _buildInfoRow(Icons.email_outlined, '邮箱', user.email),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String? value) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.primaryColor, size: 20),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textHint)),
            const SizedBox(height: 2),
            Text(
              (value == null || value.isEmpty) ? '未设置' : value,
              style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
            ),
          ],
        ),
      ],
    );
  }

  /// 更多操作
  Widget _buildMoreActions() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          _buildActionRow(Icons.image_outlined, '发送图片'),
          const Padding(padding: EdgeInsets.only(left: 56), child: Divider(height: 0.5)),
          _buildActionRow(Icons.folder_outlined, '发送文件'),
          const Padding(padding: EdgeInsets.only(left: 56), child: Divider(height: 0.5)),
          _buildActionRow(Icons.location_on_outlined, '发送位置'),
        ],
      ),
    );
  }

  Widget _buildActionRow(IconData icon, String label) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.primaryColor, size: 22),
      title: Text(label, style: const TextStyle(fontSize: 15)),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textHint, size: 20),
      onTap: () {},
    );
  }

  /// 处理菜单操作
  void _handleMenuAction(BuildContext context, String action) async {
    final friendService = FriendService();

    switch (action) {
      case 'delete':
        _showConfirmDialog(
          context,
          title: '删除好友',
          content: '确定要删除好友 "${user.nickname}" 吗？',
          onConfirm: () async {
            final result = await friendService.deleteFriend(user.id);
            if (context.mounted) {
              _showSnackBar(context, result.message);
              if (result.success) {
                // 删除成功，返回上一页并通知上层刷新
                Navigator.pop(context, true);
              }
            }
          },
        );
        break;
      case 'block':
        _showConfirmDialog(
          context,
          title: '加入黑名单',
          content: '加入黑名单后，将不再接收对方的消息。',
          onConfirm: () async {
            final result = await friendService.blockFriendRequest(user.id);
            if (context.mounted) {
              _showSnackBar(context, result.message);
            }
          },
        );
        break;
      case 'unblock':
        final result = await friendService.removeBlock(user.id);
        if (context.mounted) {
          _showSnackBar(context, result.message);
        }
        break;
    }
  }

  /// 显示确认对话框
  void _showConfirmDialog(
    BuildContext context, {
    required String title,
    required String content,
    required VoidCallback onConfirm,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onConfirm();
            },
            style: TextButton.styleFrom(foregroundColor: AppTheme.badgeColor),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 显示提示信息
  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 2)),
    );
  }
}
