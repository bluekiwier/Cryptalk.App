import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../data/mock_data.dart';
import '../../models/conversation.dart';
import '../../widgets/avatar_widget.dart';
import '../../widgets/search_bar_widget.dart';
import 'chat_detail_page.dart';
import '../contacts/scanner_page.dart';
import '../contacts/add_friend_page.dart';
import '../profile/my_qr_code_page.dart';

/// 聊天列表页面
/// 展示最近的聊天会话
class ChatListPage extends StatelessWidget {
  const ChatListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: CustomScrollView(
        slivers: [
          // 顶部渐变 AppBar
          _buildAppBar(context),
          // 搜索栏
          SliverToBoxAdapter(child: const CustomSearchBar(hintText: '搜索聊天记录')),
          // 会话列表
          SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final conversation = MockData.conversations[index];
              return _ConversationTile(
                conversation: conversation,
                onTap: () => _openChat(context, conversation),
              );
            }, childCount: MockData.conversations.length),
          ),
          // 底部间距
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
    );
  }

  /// 构建顶部渐变 AppBar
  Widget _buildAppBar(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 60,
      floating: false,
      pinned: true,
      elevation: 0,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(gradient: AppTheme.headerGradient),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Text(
                    'Cryptalk',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      '18条未读',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const Spacer(),
                  _buildAddMenu(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 构建右上角添加菜单
  Widget _buildAddMenu(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        hoverColor: Colors.transparent,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
      ),
      child: PopupMenuButton<String>(
        offset: const Offset(0, 10),
        position: PopupMenuPosition.under,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: _buildHeaderAction(
          const Icon(
            Icons.add_circle_outline_rounded,
            color: Colors.white,
            size: 24,
          ),
        ),
        onSelected: (value) {
          switch (value) {
            case 'add_friend':
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AddFriendPage()),
              );
              break;
            case 'scanner':
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ScannerPage()),
              );
              break;
            case 'my_qr':
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const MyQrCodePage()),
              );
              break;
          }
        },
        itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
          _buildPopupItem('add_friend', Icons.person_add_outlined, '添加好友'),
          const PopupMenuDivider(height: 1),
          _buildPopupItem('scanner', Icons.qr_code_scanner_rounded, '扫一扫'),
          const PopupMenuDivider(height: 1),
          _buildPopupItem('my_qr', Icons.qr_code_rounded, '我的二维码'),
        ],
      ),
    );
  }

  PopupMenuItem<String> _buildPopupItem(
    String value,
    IconData icon,
    String title,
  ) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppTheme.primaryColor),
          const SizedBox(width: 12),
          Text(title, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }

  /// 顶部操作按钮容器
  Widget _buildHeaderAction(Widget child) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
    );
  }

  /// 打开聊天详情
  void _openChat(BuildContext context, Conversation conversation) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatDetailPage(conversation: conversation),
      ),
    );
  }
}

/// 会话列表项组件
class _ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback onTap;

  const _ConversationTile({required this.conversation, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: conversation.isPinned
              ? AppTheme.primaryColor.withValues(alpha: 0.05)
              : Theme.of(context).cardColor,
          border: const Border(
            bottom: BorderSide(color: AppTheme.dividerColor, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            // 头像
            AvatarWidget(
              avatar: conversation.avatar,
              size: 52,
              isGroup: conversation.isGroup,
            ),
            const SizedBox(width: 14),
            // 中间内容
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题行
                  Row(
                    children: [
                      if (conversation.isPinned)
                        Container(
                          margin: const EdgeInsets.only(right: 4),
                          child: Icon(
                            Icons.push_pin_rounded,
                            size: 12,
                            color: AppTheme.primaryColor.withValues(alpha: 0.5),
                          ),
                        ),
                      Expanded(
                        child: Text(
                          conversation.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // 最后消息
                  Row(
                    children: [
                      if (conversation.isMuted)
                        const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: Icon(
                            Icons.notifications_off_outlined,
                            size: 14,
                            color: AppTheme.textHint,
                          ),
                        ),
                      Expanded(
                        child: Text(
                          conversation.lastMessage?.content ?? '',
                          style: TextStyle(
                            fontSize: 13,
                            color: conversation.unreadCount > 0
                                ? AppTheme.textSecondary
                                : AppTheme.textHint,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // 右侧时间和未读数
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _formatTime(conversation.lastMessage?.timestamp),
                  style: TextStyle(
                    fontSize: 11,
                    color: conversation.unreadCount > 0
                        ? AppTheme.primaryColor
                        : AppTheme.textHint,
                  ),
                ),
                const SizedBox(height: 6),
                if (conversation.unreadCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: conversation.isMuted
                          ? AppTheme.textHint
                          : AppTheme.badgeColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      conversation.unreadCount > 99
                          ? '99+'
                          : conversation.unreadCount.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 16),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 格式化时间显示
  String _formatTime(DateTime? time) {
    if (time == null) return '';
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${time.month}/${time.day}';
  }
}
