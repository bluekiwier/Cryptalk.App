import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_switch.dart';

/// 设置页面
/// 包含通知、隐私、通用等设置项
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _notificationEnabled = true;
  bool _soundEnabled = true;
  bool _vibrateEnabled = true;
  bool _showPreview = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Container(
          decoration: AppTheme.getAppBarDecoration(context),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text(
              '设置',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            centerTitle: true,
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 通知设置
                    _buildSectionTitle('通知设置'),
                    _buildCard([
                      _buildSwitchItem(
                        icon: Icons.notifications_outlined,
                        iconColor: const Color(0xFF6C63FF),
                        label: '新消息通知',
                        value: _notificationEnabled,
                        onChanged: (v) => setState(() => _notificationEnabled = v),
                      ),
                      _buildCardDivider(),
                      _buildSwitchItem(
                        icon: Icons.volume_up_outlined,
                        iconColor: const Color(0xFF00D9A6),
                        label: '声音',
                        value: _soundEnabled,
                        onChanged: (v) => setState(() => _soundEnabled = v),
                      ),
                      _buildCardDivider(),
                      _buildSwitchItem(
                        icon: Icons.vibration_rounded,
                        iconColor: const Color(0xFFF97316),
                        label: '振动',
                        value: _vibrateEnabled,
                        onChanged: (v) => setState(() => _vibrateEnabled = v),
                      ),
                      _buildCardDivider(),
                      _buildSwitchItem(
                        icon: Icons.visibility_outlined,
                        iconColor: const Color(0xFF3B82F6),
                        label: '消息预览',
                        value: _showPreview,
                        onChanged: (v) => setState(() => _showPreview = v),
                      ),
                    ]),

                    const SizedBox(height: 20),

                    // 隐私
                    _buildSectionTitle('隐私'),
                    _buildCard([
                      _buildNavItem(icon: Icons.block_outlined, iconColor: const Color(0xFFEF4444), label: '黑名单'),
                      _buildCardDivider(),
                      _buildNavItem(
                        icon: Icons.lock_outline_rounded,
                        iconColor: const Color(0xFF8B5CF6),
                        label: '隐私权限',
                      ),
                      _buildCardDivider(),
                      _buildNavItem(
                        icon: Icons.delete_outline_rounded,
                        iconColor: const Color(0xFFF97316),
                        label: '清除聊天记录',
                      ),
                    ]),

                    const SizedBox(height: 20),

                    // 通用
                    _buildSectionTitle('通用'),
                    _buildCard([
                      _buildNavItem(
                        icon: Icons.language_rounded,
                        iconColor: const Color(0xFF06B6D4),
                        label: '语言',
                        subtitle: '简体中文',
                      ),
                      _buildCardDivider(),
                      _buildNavItem(
                        icon: Icons.font_download_outlined,
                        iconColor: const Color(0xFFFBBF24),
                        label: '字体大小',
                        subtitle: '标准',
                      ),
                      _buildCardDivider(),
                      _buildNavItem(
                        icon: Icons.storage_outlined,
                        iconColor: const Color(0xFF22C55E),
                        label: '存储空间',
                        subtitle: '234 MB',
                      ),
                      _buildCardDivider(),
                      _buildNavItem(
                        icon: Icons.cached_rounded,
                        iconColor: const Color(0xFF6B7280),
                        label: '清除缓存',
                        subtitle: '18.5 MB',
                      ),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
    );
  }

  /// 区域标题
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14, 
          fontWeight: FontWeight.w600, 
          color: Theme.of(context).brightness == Brightness.dark 
              ? Colors.white.withValues(alpha: 0.7) 
              : AppTheme.textSecondary,
        ),
      ),
    );
  }

  /// 卡片容器
  Widget _buildCard(List<Widget> children) {
    return Container(
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
      child: Column(children: children),
    );
  }

  /// 开关选项
  Widget _buildSwitchItem({
    required IconData icon,
    required Color iconColor,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(
        label, 
        style: TextStyle(
          fontSize: 15, 
          fontWeight: FontWeight.w500,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
      trailing: AppSwitch(value: value, onChanged: onChanged),
    );
  }

  /// 导航选项
  Widget _buildNavItem({required IconData icon, required Color iconColor, required String label, String? subtitle}) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(
        label, 
        style: TextStyle(
          fontSize: 15, 
          fontWeight: FontWeight.w500,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (subtitle != null) Text(subtitle, style: const TextStyle(fontSize: 13, color: AppTheme.textHint)),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded, color: AppTheme.textHint, size: 20),
        ],
      ),
      onTap: () {},
    );
  }

  Widget _buildCardDivider() {
    return const Padding(padding: EdgeInsets.only(left: 72), child: Divider(height: 0.5));
  }
}
