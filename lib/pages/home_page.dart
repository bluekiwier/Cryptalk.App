import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/friend_service.dart';
import '../services/chat_service.dart';
import 'chat/chat_list_page.dart';
import 'contacts/contacts_page.dart';
import 'profile/profile_page.dart';

/// 首页 - 底部导航栏
/// 包含聊天、通讯录、我的三个 Tab
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  int _currentIndex = 0;
  late final List<Widget> _pages;
  late final AnimationController _fabController;
  final FriendService _friendService = FriendService();
  final ChatService _chatService = ChatService();

  /// 好友申请数量，用于通讯录 tab 角标
  int _friendRequestCount = 0;

  @override
  void initState() {
    super.initState();
    _pages = [
      const ChatListPage(),
      ContactsPage(
        onRequestCountChanged: (count) {
          // 通讯录页面操作后同步更新 tab 角标
          if (mounted && _friendRequestCount != count) {
            setState(() => _friendRequestCount = count);
          }
        },
      ),
      const ProfilePage(),
    ];
    _fabController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fabController.forward();

    // 进入首页时加载好友申请数量
    _loadFriendRequestCount();

    // 检查并重新连接 WebSocket（用于 APP 重新打开时）
    _chatService.checkAndReconnect();
  }

  @override
  void dispose() {
    _fabController.dispose();
    super.dispose();
  }

  /// 从 API 加载好友申请数量
  Future<void> _loadFriendRequestCount() async {
    final count = await _friendService.getRequestsCount();
    if (mounted) {
      setState(() => _friendRequestCount = count);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: _pages[_currentIndex],
      ),
      bottomNavigationBar: _buildBottomNav(),
      floatingActionButton: _currentIndex == 0
          ? ScaleTransition(
              scale: _fabController,
              child: FloatingActionButton(
                onPressed: () {
                  // 新建聊天
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('新建聊天功能开发中...'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                backgroundColor: AppTheme.primaryColor,
                elevation: 4,
                child: const Icon(Icons.edit_rounded, color: Colors.white),
              ),
            )
          : null,
    );
  }

  /// 构建底部导航栏
  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1A1D2E)
            : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(
                0,
                Icons.chat_bubble_rounded,
                Icons.chat_bubble_outline_rounded,
                '聊天',
                18,
              ),
              _buildNavItem(
                1,
                Icons.contacts_rounded,
                Icons.contacts_outlined,
                '通讯录',
                _friendRequestCount,
              ),
              _buildNavItem(
                2,
                Icons.person_rounded,
                Icons.person_outline_rounded,
                '我的',
                0,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建单个导航项
  Widget _buildNavItem(
    int index,
    IconData activeIcon,
    IconData inactiveIcon,
    String label,
    int badge,
  ) {
    final isSelected = _currentIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() => _currentIndex = index);
          if (index == 0) {
            _fabController.forward();
          } else {
            _fabController.reverse();
          }
          // 切换到聊天 tab 时刷新好友申请数量
          if (index == 0) {
            _loadFriendRequestCount();
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.primaryColor.withValues(alpha: 0.1)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isSelected ? activeIcon : inactiveIcon,
                      color: isSelected
                          ? AppTheme.primaryColor
                          : AppTheme.textHint,
                      size: 24,
                    ),
                  ),
                  // 未读消息角标
                  if (badge > 0)
                    Positioned(
                      right: -4,
                      top: -2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.badgeColor,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.badgeColor.withValues(alpha: 0.3),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Text(
                          badge > 99 ? '99+' : badge.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? AppTheme.primaryColor : AppTheme.textHint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
