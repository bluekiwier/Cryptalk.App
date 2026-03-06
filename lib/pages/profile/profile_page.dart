import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/avatar_widget.dart';
import '../../services/account_service.dart';
import '../../services/theme_service.dart';
import '../../services/chat_service.dart';
import 'settings_page.dart';
import 'change_password_page.dart';
import 'about_page.dart';
import 'user_info_page.dart';
import 'my_qr_code_page.dart';
import 'change_avatar_page.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 个人中心页面
/// 展示个人信息、功能入口和设置
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final accountService = AccountService();
    final loggedInUser = accountService.currentUser;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: CustomScrollView(
        slivers: [
          // 顶部个人信息区域
          SliverAppBar(
            expandedHeight: 120,
            pinned: true,
            elevation: 0,
            backgroundColor: AppTheme.primaryColor,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(color: AppTheme.primaryColor),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        // 左侧头像
                        GestureDetector(
                          onTap: () {
                            Navigator.push(context, MaterialPageRoute(builder: (context) => const ChangeAvatarPage()));
                          },
                          child: Stack(
                            children: [
                              Hero(
                                tag: 'avatar_large',
                                child: AvatarWidget(avatar: loggedInUser?.avatar ?? '', size: 80),
                              ),
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4)],
                                  ),
                                  child: const Icon(Icons.camera_alt_rounded, size: 16, color: AppTheme.primaryColor),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 20),
                        // 右侧昵称和账号
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                loggedInUser?.nickname ?? '我',
                                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '账号: ${loggedInUser?.account ?? ""}',
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 14),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 功能入口
          SliverToBoxAdapter(child: _buildFunctionSection(context)),

          // 工具/服务
          SliverToBoxAdapter(child: _buildToolsSection(context)),

          // 退出登录
          SliverToBoxAdapter(child: _buildLogoutButton(context)),

          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  /// 功能入口区
  Widget _buildFunctionSection(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.2 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildMenuItem(
            icon: Icons.person_outline_rounded,
            iconColor: const Color(0xFF6C63FF),
            label: '个人信息',
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const UserInfoPage()));
            },
          ),
          _buildMenuDivider(),
          _buildMenuItem(
            icon: Icons.qr_code_rounded,
            iconColor: const Color(0xFF00D9A6),
            label: '我的二维码',
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const MyQrCodePage()));
            },
          ),
          // _buildMenuDivider(),
          // _buildMenuItem(
          //   icon: Icons.star_rounded,
          //   iconColor: const Color(0xFFFBBF24),
          //   label: '我的收藏',
          //   onTap: () {},
          // ),
          // _buildMenuDivider(),
          // _buildMenuItem(
          //   icon: Icons.photo_library_outlined,
          //   iconColor: const Color(0xFFF97316),
          //   label: '相册',
          //   onTap: () {},
          // ),
          // _buildMenuDivider(),
          // _buildMenuItem(
          //   icon: Icons.file_copy_outlined,
          //   iconColor: const Color(0xFF3B82F6),
          //   label: '文件传输',
          //   onTap: () {},
          // ),
        ],
      ),
    );
  }

  /// 工具与服务
  Widget _buildToolsSection(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.2 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildMenuItem(
            icon: Icons.settings_rounded,
            iconColor: const Color(0xFF6B7280),
            label: '设置',
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsPage()));
            },
          ),
          _buildMenuDivider(),
          _buildMenuItem(
            icon: Icons.lock_outline_rounded,
            iconColor: const Color(0xFFEF4444),
            label: '修改密码',
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const ChangePasswordPage()));
            },
          ),
          _buildMenuDivider(),
          ListenableBuilder(
            listenable: ThemeService(),
            builder: (context, _) {
              final themeService = ThemeService();
              return _buildMenuItem(
                icon: Icons.dark_mode_outlined,
                iconColor: const Color(0xFF8B5CF6),
                label: '深色模式',
                trailing: Switch(
                  value: themeService.isDarkMode,
                  onChanged: (v) => themeService.toggleTheme(v),
                  activeTrackColor: AppTheme.primaryColor,
                ),
                onTap: () => themeService.toggleTheme(!themeService.isDarkMode),
              );
            },
          ),
          _buildMenuDivider(),
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) {
              final version = snapshot.data?.version ?? '1.0.0';
              return _buildMenuItem(
                icon: Icons.info_outline_rounded,
                iconColor: const Color(0xFF06B6D4),
                label: '关于闲聊',
                subtitle: '版本 $version',
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const AboutPage()));
                },
              );
            },
          ),
        ],
      ),
    );
  }

  /// 退出登录按钮
  Widget _buildLogoutButton(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      child: GestureDetector(
        onTap: () {
          showDialog(
            context: context,
            builder: (dialogContext) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('退出登录'),
              content: const Text('确定要退出当前账号吗？'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('取消')),
                TextButton(
                  onPressed: () async {
                    // 关闭对话框
                    Navigator.pop(dialogContext);
                    // 关闭 WebSocket 连接
                    ChatService().disconnect();
                    // 退出登录
                    await AccountService().signOut();
                    // 这里判断外层的 context 是否依然挂载
                    if (context.mounted) {
                      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
                    }
                  },
                  style: TextButton.styleFrom(foregroundColor: AppTheme.badgeColor),
                  child: const Text('退出'),
                ),
              ],
            ),
          );
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.2 : 0.03),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Center(
            child: Text(
              '退出登录',
              style: TextStyle(color: AppTheme.badgeColor, fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ),
        ),
      ),
    );
  }

  /// 菜单项
  Widget _buildMenuItem({
    required IconData icon,
    required Color iconColor,
    required String label,
    String? subtitle,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
      subtitle: subtitle != null
          ? Text(subtitle, style: const TextStyle(fontSize: 12, color: AppTheme.textHint))
          : null,
      trailing: trailing ?? const Icon(Icons.chevron_right_rounded, color: AppTheme.textHint, size: 20),
      onTap: onTap,
    );
  }

  /// 菜单分割线
  Widget _buildMenuDivider() {
    return const Padding(padding: EdgeInsets.only(left: 72), child: Divider(height: 0.8));
  }
}
