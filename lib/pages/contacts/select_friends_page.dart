import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import '../../theme/app_theme.dart';
import '../../models/user.dart';
import '../../services/friend_service.dart';
import '../../services/chat_service.dart';
import '../../services/conversation_service.dart';
import '../../widgets/avatar_widget.dart';
import '../../widgets/search_bar_widget.dart';
import 'package:lpinyin/lpinyin.dart';

class SelectFriendsPage extends StatefulWidget {
  const SelectFriendsPage({super.key});

  @override
  State<SelectFriendsPage> createState() => _SelectFriendsPageState();
}

class _SelectFriendsPageState extends State<SelectFriendsPage> {
  final FriendService _friendService = FriendService();
  final ChatService _chatService = ChatService();
  final _logger = Logger();

  List<User> _friends = [];
  Map<String, List<User>> _groupedFriends = {};
  final List<String> _indexList = [];
  final Map<String, GlobalKey> _letterKeys = {};
  final ScrollController _scrollController = ScrollController();

  String _searchQuery = '';
  bool _isLoading = true;

  final Set<String> _selectedUserIds = {};

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadFriends() async {
    setState(() => _isLoading = true);

    final friendListData = await _friendService.getFriendList();

    if (mounted) {
      final friends = friendListData.map((item) => User.fromJson(item)).toList();

      setState(() {
        _friends = friends;
        _updateGroupedFriends();
        _isLoading = false;
      });
    }
  }

  void _updateGroupedFriends() {
    final grouped = <String, List<User>>{};
    final indexSet = <String>{};

    final filteredFriends = _searchQuery.isEmpty
        ? _friends
        : _friends.where((user) {
            final query = _searchQuery.toLowerCase();
            return user.nickname.toLowerCase().contains(query) || user.account.toLowerCase().contains(query);
          }).toList();

    for (var user in filteredFriends) {
      String letter = '#';
      final pinyin = PinyinHelper.getFirstWordPinyin(user.nickname);
      if (pinyin.isNotEmpty && RegExp(r'[A-Z]').hasMatch(pinyin[0])) {
        letter = pinyin[0].toUpperCase();
      }

      if (!grouped.containsKey(letter)) {
        grouped[letter] = [];
      }
      grouped[letter]!.add(user);
      indexSet.add(letter);
    }

    final sortedKeys = indexSet.toList()..sort();
    if (grouped.containsKey('#')) {
      sortedKeys.remove('#');
      sortedKeys.add('#');
    }

    setState(() {
      _groupedFriends = grouped;
      _indexList.clear();
      _indexList.addAll(sortedKeys);
    });
  }

  List<User> get _filteredFriends {
    if (_searchQuery.isEmpty) return _friends;
    return _friends.where((user) {
      final query = _searchQuery.toLowerCase();
      return user.nickname.toLowerCase().contains(query) || user.account.toLowerCase().contains(query);
    }).toList();
  }

  void _toggleSelection(String userId) {
    setState(() {
      if (_selectedUserIds.contains(userId)) {
        _selectedUserIds.remove(userId);
      } else {
        _selectedUserIds.add(userId);
      }
    });
  }

  Future<void> _createGroup() async {
    if (_selectedUserIds.length < 2) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请至少选择2位好友'), behavior: SnackBarBehavior.floating));
      return;
    }

    final userIds = _selectedUserIds.toList();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.white)),
    );

    try {
      final conversation = await _chatService.createGroup(userIds);

      if (!mounted) return;
      Navigator.pop(context);

      if (conversation != null) {
        await ConversationService().notifyConversationListChanged();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('群聊创建成功'),
            backgroundColor: AppTheme.accentColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('群聊创建失败'),
            backgroundColor: AppTheme.badgeColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      _logger.e('创建群组异常: $e');
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('创建群组失败，请稍后重试'),
          backgroundColor: AppTheme.badgeColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '发起群聊',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
            ),
            Text(
              '已选择 ${_selectedUserIds.length} 位好友',
              style: const TextStyle(fontSize: 12, color: AppTheme.textHint, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _selectedUserIds.length >= 2 ? _createGroup : null,
            child: Text(
              '完成',
              style: TextStyle(
                fontSize: 16,
                color: _selectedUserIds.length >= 2 ? AppTheme.primaryColor : AppTheme.textHint,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Theme.of(context).scaffoldBackgroundColor,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: CustomSearchBar(
              hintText: '搜索好友',
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                  _updateGroupedFriends();
                });
              },
            ),
          ),
          if (_selectedUserIds.isNotEmpty)
            Container(
              height: 76,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _selectedUserIds.length,
                itemBuilder: (context, index) {
                  final userId = _selectedUserIds.toList()[index];
                  final user = _friends.firstWhere(
                    (u) => u.id == userId,
                    orElse: () => User(id: '', account: '', nickname: '', avatar: ''),
                  );
                  if (user.id.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Stack(
                          children: [
                            AvatarWidget(avatar: user.avatar, size: 40),
                            Positioned(
                              right: 0,
                              top: 0,
                              child: GestureDetector(
                                onTap: () => _toggleSelection(userId),
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: const BoxDecoration(color: AppTheme.badgeColor, shape: BoxShape.circle),
                                  child: const Icon(Icons.close, size: 10, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        SizedBox(
                          width: 50,
                          child: Text(
                            user.nickname,
                            style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredFriends.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.people_outline_rounded,
                          size: 64,
                          color: AppTheme.primaryColor.withValues(alpha: 0.2),
                        ),
                        const SizedBox(height: 12),
                        const Text('暂无好友', style: TextStyle(color: AppTheme.textHint, fontSize: 15)),
                      ],
                    ),
                  )
                : _buildFriendList(),
          ),
        ],
      ),
    );
  }

  Widget _buildFriendList() {
    final List<Widget> slivers = [];

    for (var tag in _indexList) {
      _letterKeys[tag] ??= GlobalKey();

      slivers.add(
        SliverToBoxAdapter(
          key: _letterKeys[tag],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Theme.of(context).scaffoldBackgroundColor,
            child: Text(
              tag,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
            ),
          ),
        ),
      );

      final sectionFriends = _groupedFriends[tag] ?? [];

      slivers.add(
        SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            final user = sectionFriends[index];
            final isSelected = _selectedUserIds.contains(user.id);
            return _SelectFriendTile(user: user, isSelected: isSelected, onTap: () => _toggleSelection(user.id));
          }, childCount: sectionFriends.length),
        ),
      );
    }

    return CustomScrollView(controller: _scrollController, slivers: slivers);
  }
}

class _SelectFriendTile extends StatelessWidget {
  final User user;
  final bool isSelected;
  final VoidCallback onTap;

  const _SelectFriendTile({required this.user, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: Theme.of(context).cardColor,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        height: 56,
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? AppTheme.primaryColor : Colors.transparent,
                border: Border.all(color: isSelected ? AppTheme.primaryColor : AppTheme.textHint, width: 1.5),
              ),
              child: isSelected ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
            ),
            const SizedBox(width: 12),
            AvatarWidget(avatar: user.avatar, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppTheme.dividerColor, width: 1)),
                ),
                alignment: Alignment.centerLeft,
                child: Text(
                  user.nickname,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
