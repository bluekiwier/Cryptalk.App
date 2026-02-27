import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../models/friend_request.dart';
import '../../services/friend_service.dart';
import '../../widgets/avatar_widget.dart';
import '../../widgets/search_bar_widget.dart';
import 'friend_request_detail_page.dart';

/// 新朋友页面
/// 展示待处理的好友申请列表
class NewFriendsPage extends StatefulWidget {
  const NewFriendsPage({super.key});

  @override
  State<NewFriendsPage> createState() => _NewFriendsPageState();
}

class _NewFriendsPageState extends State<NewFriendsPage>
    with SingleTickerProviderStateMixin {
  final FriendService _friendService = FriendService();

  /// 好友申请列表
  List<FriendRequest> _requests = [];

  /// 是否正在加载
  bool _isLoading = true;

  /// 错误信息
  String? _errorMessage;

  /// 搜索关键词
  String _searchQuery = '';

  /// 搜索变化回调
  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
    });
  }

  /// 入场动画控制器
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    _loadPendingRequests();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  /// 加载待处理的好友申请列表
  Future<void> _loadPendingRequests() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final requests = await _friendService.getRequests();
      if (mounted) {
        setState(() {
          _requests = requests;
          _isLoading = false;
        });
        _animController.forward();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '加载失败，请稍后重试';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          _buildAppBar(),
          // 搜索栏
          SliverToBoxAdapter(child: _buildSearchBar()),
          // 内容区域
          _buildContent(),
        ],
      ),
    );
  }

  /// 构建顶部 AppBar
  Widget _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 60,
      floating: false,
      pinned: true,
      elevation: 0,
      automaticallyImplyLeading: false,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(gradient: AppTheme.headerGradient),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(left: 4, right: 16),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Text(
                    '新朋友',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  const Spacer(),
                  // 刷新按钮
                  GestureDetector(
                    onTap: _loadPendingRequests,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.refresh_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 构建搜索栏
  Widget _buildSearchBar() {
    return CustomSearchBar(
      hintText: '搜索账号 / 昵称',
      readOnly: false,
      onChanged: _onSearchChanged,
    );
  }

  /// 构建内容区域
  Widget _buildContent() {
    // 过滤列表
    final filteredRequests = _requests.where((r) {
      final q = _searchQuery.trim().toLowerCase();
      if (q.isEmpty) return true;
      return (r.nickname.toLowerCase().contains(q)) ||
          (r.account.toLowerCase().contains(q)) ||
          (r.alias?.toLowerCase().contains(q) ?? false);
    }).toList();

    // 加载中
    if (_isLoading) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppTheme.primaryColor,
                  ),
                ),
              ),
              SizedBox(height: 16),
              Text(
                '正在加载...',
                style: TextStyle(color: AppTheme.textHint, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    // 加载出错
    if (_errorMessage != null) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_rounded,
                size: 56,
                color: AppTheme.textHint.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: const TextStyle(color: AppTheme.textHint, fontSize: 14),
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: _loadPendingRequests,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    gradient: AppTheme.headerGradient,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    '重新加载',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 列表为空
    if (filteredRequests.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.person_search_rounded,
                size: 72,
                color: AppTheme.primaryColor.withValues(alpha: 0.2),
              ),
              const SizedBox(height: 16),
              const Text(
                '暂无好友申请',
                style: TextStyle(
                  color: AppTheme.textHint,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '新的好友申请将会显示在这里',
                style: TextStyle(color: AppTheme.textHint, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    // 好友申请列表
    return SliverToBoxAdapter(
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 16,
                      decoration: BoxDecoration(
                        gradient: AppTheme.headerGradient,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '待处理 (${filteredRequests.length})',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              // 申请列表
              ...List.generate(filteredRequests.length, (index) {
                return _FriendRequestTile(
                  request: filteredRequests[index],
                  isLast: index == filteredRequests.length - 1,
                  animationDelay: index * 80,
                  onChanged: () {
                    // 详情页操作成功后刷新列表
                    _animController.reset();
                    _loadPendingRequests();
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

/// 好友申请列表项
class _FriendRequestTile extends StatefulWidget {
  final FriendRequest request;
  final bool isLast;
  final int animationDelay;
  final VoidCallback? onChanged;

  const _FriendRequestTile({
    required this.request,
    required this.isLast,
    required this.animationDelay,
    this.onChanged,
  });

  @override
  State<_FriendRequestTile> createState() => _FriendRequestTileState();
}

class _FriendRequestTileState extends State<_FriendRequestTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.15, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _opacityAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    // 延迟动画，实现错落入场效果
    Future.delayed(Duration(milliseconds: widget.animationDelay), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _opacityAnimation,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  // 头像
                  _buildAvatar(),
                  const SizedBox(width: 14),
                  // 信息区
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.request.nickname.isNotEmpty
                              ? widget.request.nickname
                              : widget.request.account,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '账号: ${widget.request.account}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textHint,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 操作按钮 - 查看
                  _buildViewButton(),
                ],
              ),
            ),
            // 分割线
            if (!widget.isLast)
              const Padding(
                padding: EdgeInsets.only(left: 76),
                child: Divider(height: 0.5, color: AppTheme.dividerColor),
              ),
          ],
        ),
      ),
    );
  }

  /// 构建头像
  Widget _buildAvatar() {
    // 如果头像是空字符串或只是 emoji，使用 AvatarWidget
    if (widget.request.avatar.isEmpty || widget.request.avatar.length <= 2) {
      return AvatarWidget(
        avatar: widget.request.avatar.isNotEmpty ? widget.request.avatar : '👤',
        size: 48,
      );
    }
    // 如果是网络头像 URL
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.network(
          widget.request.avatar,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              AvatarWidget(avatar: '👤', size: 48),
        ),
      ),
    );
  }

  /// 构建查看按钮
  Widget _buildViewButton() {
    return GestureDetector(
      onTap: () async {
        // 跳转到好友申请详情页
        final result = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => FriendRequestDetailPage(request: widget.request),
          ),
        );
        // 如果详情页操作成功（返回 true），通知父组件刷新列表
        if (result == true) {
          widget.onChanged?.call();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.primaryColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppTheme.primaryColor.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.visibility_outlined,
              size: 14,
              color: AppTheme.primaryColor,
            ),
            const SizedBox(width: 4),
            Text(
              '查看',
              style: TextStyle(
                color: AppTheme.primaryColor,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
