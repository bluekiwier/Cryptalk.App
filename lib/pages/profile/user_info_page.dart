import 'package:flutter/material.dart';
import '../../models/user.dart';
import '../../services/account_service.dart';
import '../../services/user_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/avatar_widget.dart';

/// 个人信息详情页面
class UserInfoPage extends StatefulWidget {
  const UserInfoPage({super.key});

  @override
  State<UserInfoPage> createState() => _UserInfoPageState();
}

class _UserInfoPageState extends State<UserInfoPage> {
  final UserService _userService = UserService();
  final AccountService _accountService = AccountService();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _refreshProfile();
  }

  /// 刷新个人资料
  Future<void> _refreshProfile() async {
    setState(() => _isLoading = true);
    try {
      final user = await _userService.getMe();
      if (user != null) {
        _accountService.updateCurrentUser(user);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _accountService,
      builder: (context, _) {
        final user = _accountService.currentUser;

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              SliverAppBar(
                expandedHeight: 60,
                floating: false,
                pinned: true,
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: const BoxDecoration(
                      gradient: AppTheme.headerGradient,
                    ),
                    child: SafeArea(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          const Text(
                            '个人信息',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                          Positioned(
                            right: 16,
                            child: IconButton(
                              onPressed: _isLoading ? null : _refreshProfile,
                              icon: _isLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.refresh_rounded,
                                      color: Colors.white,
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
            body: user == null
                ? const Center(child: Text('未登录'))
                : SingleChildScrollView(
                    child: Column(
                      children: [
                        const SizedBox(height: 20),
                        // 头像区域
                        Center(
                          child: Stack(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppTheme.primaryColor.withValues(
                                      alpha: 0.2,
                                    ),
                                    width: 2,
                                  ),
                                ),
                                child: AvatarWidget(
                                  avatar: user.avatar,
                                  size: 100,
                                ),
                              ),
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Material(
                                  elevation: 2,
                                  shape: const CircleBorder(),
                                  color: AppTheme.primaryColor,
                                  child: InkWell(
                                    onTap: () {
                                      // TODO: 更换头像
                                    },
                                    customBorder: const CircleBorder(),
                                    child: const Padding(
                                      padding: EdgeInsets.all(8.0),
                                      child: Icon(
                                        Icons.camera_alt_rounded,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 30),

                        // 信息列表
                        _buildInfoSection(context, user),

                        const SizedBox(height: 40),

                        // // 底部说明
                        // Padding(
                        //   padding: const EdgeInsets.symmetric(horizontal: 20),
                        //   child: Text(
                        //     '以上为您在 Cryptalk 的基本个人资料',
                        //     textAlign: TextAlign.center,
                        //     style: TextStyle(
                        //       color: AppTheme.textHint.withValues(alpha: 0.6),
                        //       fontSize: 12,
                        //     ),
                        //   ),
                        // ),
                      ],
                    ),
                  ),
          ),
        );
      },
    );
  }

  /// 弹出编辑框并处理提交
  Future<void> _editField({
    required String title,
    required String initialValue,
    required String fieldKey, // 'nickname', 'mobile', 'email', 'signature'
    int maxLines = 1,
  }) async {
    final controller = TextEditingController(text: initialValue);

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('修改$title'),
        content: TextField(
          controller: controller,
          maxLines: maxLines,
          autofocus: true,
          decoration: InputDecoration(
            hintText: '请输入新的$title',
            suffixIcon: IconButton(
              icon: const Icon(Icons.clear, size: 18),
              onPressed: () => controller.clear(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (result == true) {
      final newValue = controller.text.trim();
      if (newValue == initialValue) return;

      // 手机号格式验证
      if (fieldKey == 'mobile') {
        final regExp = RegExp(r'^1[3-9]\d{9}$');
        if (!regExp.hasMatch(newValue)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('请输入正确的手机号码格式'),
                backgroundColor: AppTheme.badgeColor,
              ),
            );
          }
          return;
        }
      }

      setState(() => _isLoading = true);
      try {
        final res = await _userService.changeInfo(
          nickname: fieldKey == 'nickname' ? newValue : null,
          mobile: fieldKey == 'mobile' ? newValue : null,
          email: fieldKey == 'email' ? newValue : null,
          signature: fieldKey == 'signature' ? newValue : null,
        );

        if (res.success) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('$title修改成功！'),
                backgroundColor: AppTheme.onlineColor,
              ),
            );
          }
          await _refreshProfile();
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(res.message),
                backgroundColor: AppTheme.badgeColor,
              ),
            );
          }
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildInfoSection(BuildContext context, User user) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: Theme.of(context).brightness == Brightness.dark
                  ? 0.2
                  : 0.05,
            ),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildInfoTile(
            label: '昵称',
            value: user.nickname,
            onTap: () => _editField(
              title: '昵称',
              initialValue: user.nickname,
              fieldKey: 'nickname',
            ),
          ),
          _buildDivider(),
          _buildInfoTile(label: '账号', value: user.account, showArrow: false),
          _buildDivider(),
          _buildInfoTile(
            label: '手机号',
            value: user.mobile ?? '未绑定',
            onTap: () => _editField(
              title: '手机号',
              initialValue: user.mobile ?? '',
              fieldKey: 'mobile',
            ),
          ),
          _buildDivider(),
          _buildInfoTile(
            label: '邮箱',
            value: user.email ?? '未设置',
            onTap: () => _editField(
              title: '邮箱',
              initialValue: user.email ?? '',
              fieldKey: 'email',
            ),
          ),
          _buildDivider(),
          _buildInfoTile(
            label: '个性签名',
            value: user.signature?.isNotEmpty == true
                ? user.signature!
                : '这个家伙很懒，什么都没写',
            isLongText: true,
            onTap: () => _editField(
              title: '个性签名',
              initialValue: user.signature ?? '',
              fieldKey: 'signature',
              maxLines: 3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile({
    required String label,
    required String value,
    bool showArrow = true,
    bool isLongText = false,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 15,
                  color: onTap != null
                      ? AppTheme.textPrimary
                      : AppTheme.textHint,
                ),
                maxLines: isLongText ? 2 : 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (showArrow) ...[
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppTheme.textHint,
                size: 20,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(
      height: 1,
      indent: 20,
      endIndent: 20,
      color: Colors.grey.withValues(alpha: 0.1),
    );
  }
}
