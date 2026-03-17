import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../models/user.dart';
import '../../services/friend_service.dart';
import '../../services/user_service.dart';
import '../../widgets/avatar_widget.dart';
import '../../widgets/search_bar_widget.dart';
import 'contact_detail_page.dart';
import 'new_friends_page.dart';
import 'scanner_page.dart';
import 'add_friend_page.dart';
import 'package:lpinyin/lpinyin.dart';

/// 通讯录页面
/// 从 API 获取真实好友列表并展示
class ContactsPage extends StatefulWidget {
  /// 好友申请数量变更回调，用于同步 HomePage 的 tab 角标
  final ValueChanged<int>? onRequestCountChanged;

  const ContactsPage({super.key, this.onRequestCountChanged});

  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends State<ContactsPage> {
  final FriendService _friendService = FriendService();

  /// 好友列表
  List<User> _friends = [];

  /// 按字母分组的好友列表
  Map<String, List<User>> _groupedFriends = {};

  /// 好友申请数量
  int _requestCount = 0;

  /// 是否正在加载
  bool _isLoading = true;

  final ScrollController _scrollController = ScrollController();
  final List<String> _indexList = [];
  final Map<String, GlobalKey> _letterKeys = {};

  /// 搜索关键词
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 滚动到指定字母
  void _scrollToLetter(String letter) {
    final key = _letterKeys[letter];
    if (key != null && key.currentContext != null) {
      Scrollable.ensureVisible(
        key.currentContext!,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  /// 加载好友列表和申请数量
  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    // 并行请求好友列表和申请数量
    final results = await Future.wait([_friendService.getFriendList(), _friendService.getRequestsCount()]);

    final friendListData = results[0] as List<Map<String, dynamic>>;
    final count = results[1] as int;

    if (mounted) {
      final friends = friendListData.map((item) => User.fromJson(item)).toList();

      setState(() {
        _friends = friends;
        _requestCount = count;
        _updateGroupedFriends();
        _isLoading = false;
      });
      // 通知 HomePage 更新 tab 角标
      widget.onRequestCountChanged?.call(count);
    }
  }

  /// 搜索变化回调
  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
      _updateGroupedFriends();
    });
  }

  /// 更新分组数据
  void _updateGroupedFriends() {
    // 1. 过滤
    final filtered = _friends.where((u) {
      final q = _searchQuery.trim().toLowerCase();
      if (q.isEmpty) return true;

      // 基础名称匹配
      bool isMatch = u.nickname.toLowerCase().contains(q);

      // 扩展匹配：如果搜索词长度 > 1，或者是字母/符号（非单数字），则搜索账号、手机号和签名
      // 这样可以避免输入 "1" 时匹配所有以 "1" 开头的手机号，同时保留对包含 "13" 等更具体内容的搜索
      if (q.length > 1 || !RegExp(r'^\d$').hasMatch(q)) {
        isMatch =
            isMatch ||
            u.account.toLowerCase().contains(q) ||
            (u.mobile?.toLowerCase().contains(q) ?? false) ||
            (u.signature?.toLowerCase().contains(q) ?? false);
      }

      return isMatch;
    }).toList();

    // 2. 排序 (按拼音排序)
    filtered.sort((a, b) {
      final pinyinA = PinyinHelper.getPinyin(a.nickname).toLowerCase();
      final pinyinB = PinyinHelper.getPinyin(b.nickname).toLowerCase();
      return pinyinA.compareTo(pinyinB);
    });

    // 3. 分组
    final Map<String, List<User>> grouped = {};
    final List<String> index = [];
    _letterKeys.clear();

    for (var user in filtered) {
      String tag = '#';
      if (user.nickname.isNotEmpty) {
        // 使用 lpinyin 获取首字母
        String firstLetter = PinyinHelper.getShortPinyin(user.nickname[0]);
        if (firstLetter.isNotEmpty) {
          tag = firstLetter[0].toUpperCase();
        }
      }

      if (!RegExp(r'[A-Z]').hasMatch(tag)) tag = '#';

      if (!grouped.containsKey(tag)) {
        grouped[tag] = [];
        index.add(tag);
        _letterKeys[tag] = GlobalKey();
      }
      grouped[tag]!.add(user);
    }

    // 4. 索引栏排序
    index.sort((a, b) {
      if (a == '#') return 1;
      if (b == '#') return -1;
      return a.compareTo(b);
    });

    _groupedFriends = grouped;
    _indexList.clear();
    _indexList.addAll(index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scrollController,
            slivers: [
              // 顶部渐变 AppBar
              _buildAppBar(),
              // 搜索栏
              SliverToBoxAdapter(
                child: CustomSearchBar(hintText: '搜索联系人', readOnly: false, onChanged: _onSearchChanged),
              ),
              // 快捷入口
              SliverToBoxAdapter(child: _buildQuickActions(context)),
              // 好友列表
              ..._buildFriendList(context),
              // 联系人总数
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      _isLoading ? '正在加载...' : '共 ${_friends.length} 位联系人',
                      style: const TextStyle(fontSize: 13, color: AppTheme.textHint),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (!_isLoading && _indexList.isNotEmpty)
            Positioned(
              right: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: _AlphabetIndexBar(indexList: _indexList, onLetterSelected: _scrollToLetter),
              ),
            ),
        ],
      ),
    );
  }

  /// 构建顶部 AppBar
  Widget _buildAppBar() {
    return SliverAppBar(
      pinned: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
      automaticallyImplyLeading: false,
      title: Row(
        children: [
          const Text(
            '通讯录',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1),
          ),
          const Spacer(),
          // 扫码按钮
          GestureDetector(
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const ScannerPage()));
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 20),
            ),
          ),
          const SizedBox(width: 10),
          // 添加好友按钮
          GestureDetector(
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const AddFriendPage()));
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.person_add_outlined, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
      titleSpacing: 20,
      flexibleSpace: Container(decoration: AppTheme.getAppBarDecoration(context)),
    );
  }

  /// 快捷入口：新朋友、群聊、标签
  Widget _buildQuickActions(BuildContext context) {
    final actions = [
      {'icon': Icons.person_add_alt_1_rounded, 'label': '新朋友', 'badge': _requestCount},
      // {'icon': Icons.group_rounded, 'label': '群聊', 'badge': 0},
      // {'icon': Icons.label_rounded, 'label': '标签', 'badge': 0},
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.2 : 0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: actions.map((action) {
          final isLast = action == actions.last;
          return Column(
            children: [
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(gradient: AppTheme.headerGradient, borderRadius: BorderRadius.circular(10)),
                  child: Icon(action['icon'] as IconData, color: Colors.white, size: 20),
                ),
                title: Text(
                  action['label'] as String,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if ((action['badge'] as int) > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: AppTheme.badgeColor, borderRadius: BorderRadius.circular(10)),
                        child: Text(
                          '${action['badge']}',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right_rounded, color: AppTheme.textHint, size: 20),
                  ],
                ),
                onTap: () async {
                  if (action['label'] == '新朋友') {
                    // 从新朋友页面返回时刷新数据
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const NewFriendsPage()));
                    // 返回后刷新好友列表和申请数量
                    _loadData();
                  }
                },
              ),
              if (!isLast) const Padding(padding: EdgeInsets.only(left: 72), child: Divider(height: 1)),
            ],
          );
        }).toList(),
      ),
    );
  }

  /// 构建好友列表
  List<Widget> _buildFriendList(BuildContext context) {
    if (_isLoading) {
      return [
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: EdgeInsets.only(top: 60),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                    ),
                  ),
                  SizedBox(height: 12),
                  Text('正在加载好友列表...', style: TextStyle(color: AppTheme.textHint, fontSize: 13)),
                ],
              ),
            ),
          ),
        ),
      ];
    }

    if (_friends.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.people_outline_rounded, size: 64, color: AppTheme.primaryColor.withValues(alpha: 0.2)),
                  const SizedBox(height: 12),
                  const Text(
                    '暂无好友',
                    style: TextStyle(color: AppTheme.textHint, fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 6),
                  const Text('点击右上角添加好友', style: TextStyle(color: AppTheme.textHint, fontSize: 13)),
                ],
              ),
            ),
          ),
        ),
      ];
    }

    // 按字母分组显示
    final List<Widget> slivers = [];

    for (var tag in _indexList) {
      // 字母分组标题
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

      // 该字母下的好友列表
      final sectionFriends = _groupedFriends[tag] ?? [];

      slivers.add(
        SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            final user = sectionFriends[index];
            return _ContactTile(user: user, onTap: () => _openContact(context, user.id));
          }, childCount: sectionFriends.length),
        ),
      );
    }

    return slivers;
  }

  Future<void> _openContact(BuildContext context, String userId) async {
    // 显示加载提示
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.white)),
    );

    try {
      final userData = await UserService().getUserProfile(userId);
      if (context.mounted) Navigator.pop(context); // 关闭加载提示

      if (userData != null) {
        final user = User.fromJson(userData);
        if (context.mounted) {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => ContactDetailPage(user: user)),
          );
          if (result == true) {
            _loadData();
          }
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('获取用户信息失败')));
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // 确保关闭加载提示
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('网络错误，请稍后重试')));
      }
    }
  }
}

/// 联系人列表项
class _ContactTile extends StatelessWidget {
  final User user;
  final VoidCallback onTap;

  const _ContactTile({required this.user, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: Theme.of(context).cardColor,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        height: 60,
        child: Row(
          children: [
            AvatarWidget(avatar: user.avatar, size: 44, showOnline: true, online: user.online),
            // 头像与文字的间距
            const SizedBox(width: 14),
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppTheme.dividerColor, width: 1)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.nickname,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    if (user.signature != null && user.signature!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        user.signature!,
                        style: const TextStyle(fontSize: 12, color: AppTheme.textHint),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(padding: EdgeInsets.only(left: 14), child: Divider(height: 0.5)),
          ],
        ),
      ),
    );
  }
}

/// 侧边索引栏
class _AlphabetIndexBar extends StatefulWidget {
  final List<String> indexList;
  final ValueChanged<String> onLetterSelected;

  const _AlphabetIndexBar({required this.indexList, required this.onLetterSelected});

  @override
  State<_AlphabetIndexBar> createState() => _AlphabetIndexBarState();
}

class _AlphabetIndexBarState extends State<_AlphabetIndexBar> {
  String? _activeLetter;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragUpdate: (details) => _handleTouch(details.localPosition),
      onVerticalDragDown: (details) => _handleTouch(details.localPosition),
      onVerticalDragEnd: (_) => setState(() => _activeLetter = null),
      onTapDown: (details) => _handleTouch(details.localPosition),
      onTapUp: (_) => setState(() => _activeLetter = null),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
        decoration: BoxDecoration(
          color: _activeLetter != null ? Colors.black.withValues(alpha: 0.05) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: widget.indexList.map((letter) {
            final isActive = _activeLetter == letter;
            return Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: isActive ? AppTheme.primaryColor : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  letter,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isActive ? Colors.white : AppTheme.textSecondary,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  void _handleTouch(Offset localPosition) {
    final RenderBox box = context.findRenderObject() as RenderBox;
    final double itemHeight = box.size.height / widget.indexList.length;
    final int index = (localPosition.dy / itemHeight).floor().clamp(0, widget.indexList.length - 1);

    final letter = widget.indexList[index];
    if (letter != _activeLetter) {
      setState(() => _activeLetter = letter);
      widget.onLetterSelected(letter);
    }
  }
}
