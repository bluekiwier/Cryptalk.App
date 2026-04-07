import 'package:cryptalk/utils/time_util.dart';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../models/conversation.dart';
import '../../widgets/avatar_widget.dart';
import '../../widgets/search_bar_widget.dart';
import '../../services/conversation_service.dart';
import '../../services/account_service.dart';
import '../contacts/scanner_page.dart';
import '../contacts/add_friend_page.dart';
import '../contacts/select_friends_page.dart';
import '../profile/my_qr_code_page.dart';
import 'chat_detail_page.dart';

/// 聊天列表页面
/// 策略：冷启动 < 100ms（本地 DB），60fps（ListView.builder），实时未读（ChangeNotifier）
class ChatListPage extends StatefulWidget {
  const ChatListPage({super.key});

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  final AccountService _accountService = AccountService();
  final ConversationService _conversationService = ConversationService();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  // 是否正在初始化（首次从 DB 加载）
  bool _initializing = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _conversationService.addListener(_onServiceChanged);
    _searchController.addListener(_onSearchChanged);
    _init();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _conversationService.removeListener(_onServiceChanged);
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  /// 搜索文本变化时触发
  void _onSearchChanged() {
    _conversationService.searchConversations(_searchController.text);
  }

  /// 初始化：加载本地 DB（秒开），后台同步网络
  Future<void> _init() async {
    await _conversationService.initialize();
    if (mounted) setState(() => _initializing = false);
  }

  /// ConversationService 状态变化时触发 UI 刷新
  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  /// 滚动到底部时加载更多
  void _onScroll() {
    if (_initializing) return;
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent * 0.9) {
      _conversationService.loadMore();
    }
  }

  /// 下拉刷新
  Future<void> _onRefresh() => _conversationService.refresh();

  @override
  Widget build(BuildContext context) {
    final filteredConversations = _conversationService.filteredConversations;
    final isSearching = _conversationService.isSearching;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        color: AppTheme.primaryColor,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          slivers: [
            // 顶部渐变 AppBar
            _buildAppBar(context),
            // 搜索栏
            SliverToBoxAdapter(
              child: CustomSearchBar(
                hintText: '搜索会话',
                controller: _searchController,
                readOnly: false,
                autofocus: false,
                onSubmitted: (value) {
                  // 搜索
                },
              ),
            ),
            // 内容区
            if (_initializing)
              // 首次加载（本地 DB 还没完成）—— 极短，通常 < 50ms
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(top: 60),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (filteredConversations.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 100),
                  child: Center(
                    child: Text(isSearching ? '未找到相关会话' : '暂无聊天会话', style: const TextStyle(color: AppTheme.textHint)),
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  // 末尾额外的加载指示器 item
                  if (index == filteredConversations.length) {
                    return _buildLoadMoreIndicator();
                  }
                  return _ConversationTile(
                    key: ValueKey(filteredConversations[index].id),
                    conversation: filteredConversations[index],
                    onTap: () async {
                      final conversation = filteredConversations[index];
                      // 进入聊天页时清零未读数
                      await _conversationService.clearUnread(conversation.id);
                      
                      if (!mounted || !context.mounted) return;
                      await _openChat(context, conversation);
                    },
                  );
                }, childCount: filteredConversations.length + 1),
              ),
            // 底部间距
            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadMoreIndicator() {
    if (_conversationService.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_conversationService.hasMore) return const SizedBox.shrink();
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Text('没有更多会话了', style: TextStyle(color: AppTheme.textHint, fontSize: 12)),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
      automaticallyImplyLeading: false,
      title: Row(
        children: [
          const Text(
            '闲聊',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1),
          ),
          const SizedBox(width: 8),
          if (_accountService.currentUser?.messageUnreadCount != null &&
              _accountService.currentUser!.messageUnreadCount! > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '(${_accountService.currentUser!.messageUnreadCount!})',
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
              ),
            ),
          const Spacer(),
          _buildAddMenu(context),
        ],
      ),
      titleSpacing: 20,
      flexibleSpace: Container(decoration: AppTheme.getAppBarDecoration(context)),
    );
  }

  Widget _buildAddMenu(BuildContext context) {
    return Theme(
      data: Theme.of(
        context,
      ).copyWith(hoverColor: Colors.transparent, splashColor: Colors.transparent, highlightColor: Colors.transparent),
      child: PopupMenuButton<String>(
        offset: const Offset(0, 10),
        position: PopupMenuPosition.under,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: _buildHeaderAction(const Icon(Icons.add_circle_outline_rounded, color: Colors.white, size: 24)),
        onSelected: (value) {
          switch (value) {
            case 'create_group':
              Navigator.push(context, MaterialPageRoute(builder: (context) => const SelectFriendsPage()));
              break;
            case 'add_friend':
              Navigator.push(context, MaterialPageRoute(builder: (context) => const AddFriendPage()));
              break;
            case 'scanner':
              Navigator.push(context, MaterialPageRoute(builder: (context) => const ScannerPage()));
              break;
            case 'my_qr':
              Navigator.push(context, MaterialPageRoute(builder: (context) => const MyQrCodePage()));
              break;
          }
        },
        itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
          _buildPopupItem('create_group', Icons.group_add_rounded, '发起群聊'),
          const PopupMenuDivider(height: 1),
          _buildPopupItem('add_friend', Icons.person_add_outlined, '添加好友'),
          const PopupMenuDivider(height: 1),
          _buildPopupItem('scanner', Icons.qr_code_scanner_rounded, '扫一扫'),
          const PopupMenuDivider(height: 1),
          _buildPopupItem('my_qr', Icons.qr_code_rounded, '我的二维码'),
        ],
      ),
    );
  }

  PopupMenuItem<String> _buildPopupItem(String value, IconData icon, String title) {
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

  Widget _buildHeaderAction(Widget child) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
      child: child,
    );
  }

  Future<void> _openChat(BuildContext context, Conversation conversation) {
    return Navigator.push(context, MaterialPageRoute(builder: (context) => ChatDetailPage(conversation: conversation)));
  }
}

class _ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback onTap;

  const _ConversationTile({super.key, required this.conversation, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: conversation.isPinned ? AppTheme.primaryColor.withValues(alpha: 0.05) : Theme.of(context).cardColor,
        child: Row(
          children: [
            // 头像
            AvatarWidget(avatar: conversation.avatar, size: 56, isGroup: conversation.isGroup),
            const SizedBox(width: 14),
            // 右侧内容（标题 + 最后消息 + 时间 + 未读数 + 分隔线）
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 第一行：标题 + 时间
                  Row(
                    children: [
                      if (conversation.isPinned)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(
                            Icons.push_pin_rounded,
                            size: 12,
                            color: AppTheme.primaryColor.withValues(alpha: 0.5),
                          ),
                        ),
                      Expanded(
                        child: Text(
                          conversation.title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        TimeUtil.formatTime(conversation.lastMessageAt),
                        style: TextStyle(
                          fontSize: 11,
                          color: conversation.unreadCount > 0 ? AppTheme.primaryColor : AppTheme.textHint,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // 第二行：最后消息 + 未读数
                  Row(
                    children: [
                      if (conversation.isMuted)
                        const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: Icon(Icons.notifications_off_outlined, size: 14, color: AppTheme.textHint),
                        ),
                      Expanded(
                        child: Text(
                          conversation.lastMessagePreview ?? '',
                          style: TextStyle(
                            fontSize: 13,
                            color: conversation.unreadCount > 0 ? AppTheme.textSecondary : AppTheme.textHint,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (conversation.unreadCount > 0)
                        Container(
                          margin: const EdgeInsets.only(left: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: conversation.isMuted ? AppTheme.textHint : AppTheme.badgeColor,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            conversation.unreadCount > 99 ? '99+' : conversation.unreadCount.toString(),
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // 分隔线
                  Container(
                    height: 0.5,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white.withValues(alpha: 0.3)
                        : Colors.black.withValues(alpha: 0.08),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
