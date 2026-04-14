import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../theme/app_theme.dart';
import '../../models/user.dart';
import '../../widgets/avatar_widget.dart';
import '../../services/friend_service.dart';

/// 搜索到的用户详情页面 - 陌生人查看
class UserDetailPage extends StatefulWidget {
  final User user;

  const UserDetailPage({super.key, required this.user});

  @override
  State<UserDetailPage> createState() => _UserDetailPageState();
}

class _UserDetailPageState extends State<UserDetailPage> {
  final FriendService _friendService = FriendService();
  bool _isSubmitting = false;

  /// 发送好友申请
  Future<void> _sendFriendRequest() async {
    if (_isSubmitting) return;

    setState(() => _isSubmitting = true);

    try {
      final result = await _friendService.addFriend(widget.user.account);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: result.success ? AppTheme.accentColor : AppTheme.badgeColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );

      if (result.success) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('发送失败，请检查网络'.tr()),
            backgroundColor: AppTheme.badgeColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
            title: Text(
              '用户详情'.tr(),
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1),
            ),
            centerTitle: true,
            flexibleSpace: Container(decoration: AppTheme.getAppBarDecoration(context)),
          ),

          // 顶部个人信息渐变背景区域 - 移入 body
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
                  Hero(
                    tag: 'avatar_${widget.user.id}',
                    child: AvatarWidget(avatar: widget.user.avatar, size: 88),
                  ),
                  const SizedBox(height: 16),
                  // 名字
                  Text(
                    widget.user.nickname,
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  // 账号
                  Text(
                    '${'账号:'.tr()} ${widget.user.account}',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 14),
                  ),
                ],
              ),
            ),
          ),

          // 个人资料卡片
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('个人信息'.tr(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  _buildInfoRow(
                    context,
                    Icons.edit_note_rounded,
                    '个性签名'.tr(),
                    widget.user.signature?.isNotEmpty == true ? widget.user.signature! : '该用户暂未设置签名'.tr(),
                  ),
                  if (widget.user.mobile?.isNotEmpty == true) ...[
                    const Divider(height: 32),
                    _buildInfoRow(context, Icons.phone_android_rounded, '手机号'.tr(), widget.user.mobile!),
                  ],
                ],
              ),
            ),
          ),

          // 底部填充
          const SliverFillRemaining(hasScrollBody: false, child: SizedBox(height: 100)),
        ],
      ),
      // 底部固定按钮
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Container(
            height: 54,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: AppTheme.headerGradient,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryColor.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _isSubmitting ? null : _sendFriendRequest,
                borderRadius: BorderRadius.circular(16),
                child: Center(
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.person_add_alt_1_rounded, color: Colors.white, size: 20),
                            SizedBox(width: 8),
                            Text(
                              '申请加为好友'.tr(),
                              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppTheme.primaryColor, size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textHint)),
              const SizedBox(height: 4),
              Text(value, style: TextStyle(fontSize: 15, color: Theme.of(context).colorScheme.onSurface)),
            ],
          ),
        ),
      ],
    );
  }
}
