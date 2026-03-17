import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../models/friend_request.dart';
import '../../services/friend_service.dart';
import '../../services/user_service.dart';
import '../../widgets/avatar_widget.dart';

/// 好友申请详情页
/// 展示申请人的详细资料，并提供接受、拒绝、拉黑操作
class FriendRequestDetailPage extends StatefulWidget {
  /// 好友申请记录
  final FriendRequest request;

  const FriendRequestDetailPage({super.key, required this.request});

  @override
  State<FriendRequestDetailPage> createState() => _FriendRequestDetailPageState();
}

class _FriendRequestDetailPageState extends State<FriendRequestDetailPage> with SingleTickerProviderStateMixin {
  final FriendService _friendService = FriendService();

  /// 用户详情数据
  Map<String, dynamic>? _userProfile;

  /// 是否正在加载详情
  bool _isLoading = true;

  /// 是否正在执行操作（接受/拒绝/拉黑）
  bool _isProcessing = false;

  /// 错误信息
  String? _errorMessage;

  /// 入场动画控制器
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _fadeAnimation = CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic);
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));
    _loadUserProfile();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  /// 加载用户详情
  Future<void> _loadUserProfile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 使用申请记录中的 account 作为查询 ID
      final profile = await UserService().getUserProfile(widget.request.id);
      if (mounted) {
        setState(() {
          _userProfile = profile;
          _isLoading = false;
        });
        _animController.forward();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '加载用户信息失败';
          _isLoading = false;
        });
      }
    }
  }

  /// 执行好友操作（接受/拒绝/拉黑）
  Future<void> _handleAction(
    String actionType,
    Future<({bool success, String message})> Function(String) apiCall,
  ) async {
    if (_isProcessing) return;

    // 拉黑操作需要二次确认
    if (actionType == 'block') {
      final confirmed = await _showConfirmDialog(
        title: '确认拉黑',
        content: '拉黑后将不再接收该用户的消息和好友申请，确定要拉黑吗？',
        confirmText: '拉黑',
        confirmColor: Colors.red,
      );
      if (!confirmed) return;
    }

    setState(() => _isProcessing = true);

    final result = await apiCall(widget.request.id);

    if (mounted) {
      setState(() => _isProcessing = false);

      // 显示操作结果
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: result.success ? AppTheme.accentColor : AppTheme.badgeColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );

      // 操作成功后返回上一页，并传回 true 表示有变更
      if (result.success) {
        Navigator.pop(context, true);
      }
    }
  }

  /// 显示确认对话框
  Future<bool> _showConfirmDialog({
    required String title,
    required String content,
    required String confirmText,
    required Color confirmColor,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            content: Text(content, style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消', style: TextStyle(color: AppTheme.textHint)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(
                  confirmText,
                  style: TextStyle(color: confirmColor, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg,
      body: Column(
        children: [
          // 顶部 AppBar
          _buildAppBar(),
          // 内容区域
          Expanded(child: _buildBody()),
          // 底部操作按钮
          if (!_isLoading && _errorMessage == null) _buildBottomActions(),
        ],
      ),
    );
  }

  /// 构建顶部 AppBar
  Widget _buildAppBar() {
    return Container(
      decoration: AppTheme.getAppBarDecoration(context),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
              const Text(
                '申请详情',
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
              const Spacer(),
              const SizedBox(width: 48),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建页面主体
  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
              ),
            ),
            SizedBox(height: 16),
            Text('正在加载用户资料...', style: TextStyle(color: AppTheme.textHint, fontSize: 14)),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 56, color: AppTheme.textHint.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(_errorMessage!, style: const TextStyle(color: AppTheme.textHint, fontSize: 14)),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: _loadUserProfile,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                decoration: BoxDecoration(gradient: AppTheme.headerGradient, borderRadius: BorderRadius.circular(20)),
                child: const Text(
                  '重新加载',
                  style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // 用户头像卡片
              _buildAvatarCard(),
              const SizedBox(height: 16),
              // 用户信息卡片
              _buildInfoCard(),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建头像卡片
  Widget _buildAvatarCard() {
    final nickname = _userProfile?['nickname']?.toString() ?? widget.request.nickname;
    final avatar = _userProfile?['avatar']?.toString() ?? widget.request.avatar;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: AppTheme.primaryColor.withValues(alpha: 0.06), blurRadius: 20, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          // 头像
          _buildProfileAvatar(avatar),
          const SizedBox(height: 16),
          // 昵称
          Text(
            nickname.isNotEmpty ? nickname : '未知用户',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          // 在线状态
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _userProfile?['online'] == 1 ? AppTheme.onlineColor : AppTheme.offlineColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _userProfile?['online'] == 1 ? '在线' : '离线',
                style: TextStyle(
                  fontSize: 13,
                  color: _userProfile?['online'] == 1 ? AppTheme.onlineColor : AppTheme.textHint,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建用户详情头像
  Widget _buildProfileAvatar(String avatar) {
    if (avatar.isEmpty || avatar.length <= 2) {
      return Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: AppTheme.primaryColor.withValues(alpha: 0.15), blurRadius: 20, offset: const Offset(0, 6)),
          ],
        ),
        child: AvatarWidget(avatar: avatar.isNotEmpty ? avatar : '👤', size: 88),
      );
    }
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(color: AppTheme.primaryColor.withValues(alpha: 0.15), blurRadius: 20, offset: const Offset(0, 6)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Image.network(
          avatar,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => AvatarWidget(avatar: '👤', size: 88),
        ),
      ),
    );
  }

  /// 构建信息卡片
  Widget _buildInfoCard() {
    final account = _userProfile?['account']?.toString() ?? widget.request.account;
    final email = _userProfile?['email']?.toString() ?? '';
    final mobile = _userProfile?['mobile']?.toString() ?? '';
    final inviteCode = _userProfile?['inviteCode']?.toString() ?? '';
    final createdAt = _userProfile?['createdAt']?.toString() ?? '';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 16,
                  decoration: BoxDecoration(gradient: AppTheme.headerGradient, borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(width: 8),
                const Text(
                  '基本信息',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                ),
              ],
            ),
          ),
          // 信息列表
          _buildInfoRow(Icons.account_circle_outlined, '账号', account),
          if (email.isNotEmpty) _buildInfoRow(Icons.email_outlined, '邮箱', email),
          if (mobile.isNotEmpty) _buildInfoRow(Icons.phone_outlined, '手机', mobile),
          if (inviteCode.isNotEmpty) _buildInfoRow(Icons.card_giftcard_outlined, '邀请码', inviteCode),
          if (createdAt.isNotEmpty) _buildInfoRow(Icons.access_time_rounded, '注册时间', createdAt),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  /// 构建信息行
  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: AppTheme.primaryColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textHint)),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppTheme.textPrimary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建底部操作按钮区
  Widget _buildBottomActions() {
    return Container(
      padding: EdgeInsets.only(left: 20, right: 20, top: 16, bottom: MediaQuery.of(context).padding.bottom + 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -2)),
        ],
      ),
      child: _isProcessing
          ? const Center(
              child: SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                ),
              ),
            )
          : Row(
              children: [
                // 拉黑按钮
                Expanded(
                  child: _buildActionButton(
                    label: '拉黑',
                    icon: Icons.block_rounded,
                    bgColor: Colors.grey.shade100,
                    textColor: Colors.red.shade400,
                    onTap: () => _handleAction('block', _friendService.blockFriendRequest),
                  ),
                ),
                const SizedBox(width: 12),
                // 拒绝按钮
                Expanded(
                  child: _buildActionButton(
                    label: '拒绝',
                    icon: Icons.close_rounded,
                    bgColor: Colors.grey.shade100,
                    textColor: AppTheme.textSecondary,
                    onTap: () => _handleAction('disagree', _friendService.disagreeFriendRequest),
                  ),
                ),
                const SizedBox(width: 12),
                // 接受按钮
                Expanded(
                  flex: 2,
                  child: _buildGradientActionButton(
                    label: '接受',
                    icon: Icons.check_rounded,
                    onTap: () => _handleAction('agree', _friendService.agreeFriendRequest),
                  ),
                ),
              ],
            ),
    );
  }

  /// 构建普通操作按钮
  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color bgColor,
    required Color textColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(14)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: textColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建渐变操作按钮（接受按钮使用）
  Widget _buildGradientActionButton({required String label, required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: AppTheme.headerGradient,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(color: AppTheme.primaryColor.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
