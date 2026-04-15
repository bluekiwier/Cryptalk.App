import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_switch.dart';
import '../company/company_page.dart';
import '../../services/theme_service.dart';
import '../../services/database_service.dart';
import '../../services/conversation_service.dart';

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
  String _cacheSizeStr = '计算中...'.tr();
  String _storageSizeStr = '计算中...'.tr();

  double _tempDirSize = 0;
  double _docDirSize = 0;
  double _supportDirSize = 0;

  @override
  void initState() {
    super.initState();
    _loadAllSizes();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _notificationEnabled = prefs.getBool('notificationEnabled') ?? true;
        _soundEnabled = prefs.getBool('soundEnabled') ?? true;
        _vibrateEnabled = prefs.getBool('vibrateEnabled') ?? true;
      });
    }
  }

  Future<void> _updateSetting(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
    if (key == 'vibrateEnabled' && value) {
      // 开启振动时给予反馈
      HapticFeedback.vibrate();
    }
  }

  Future<void> _loadAllSizes() async {
    try {
      _tempDirSize = 0;
      _docDirSize = 0;
      _supportDirSize = 0;

      final tempDir = await getTemporaryDirectory();
      _tempDirSize = await _getTotalSizeOfFilesInDir(tempDir);

      try {
        final docDir = await getApplicationDocumentsDirectory();
        _docDirSize = await _getTotalSizeOfFilesInDir(docDir);
      } catch (_) {}

      try {
        final supportDir = await getApplicationSupportDirectory();
        _supportDirSize = await _getTotalSizeOfFilesInDir(supportDir);
      } catch (_) {}

      if (mounted) {
        setState(() {
          _cacheSizeStr = _formatSize(_tempDirSize);
          _storageSizeStr = _formatSize(_tempDirSize + _docDirSize + _supportDirSize);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _cacheSizeStr = '未知'.tr();
          _storageSizeStr = '未知'.tr();
        });
      }
    }
  }

  Future<void> _showStorageDetails() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('存储空间详情'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.description_outlined, color: Colors.blue),
              title: Text('应用文稿数据'.tr(), style: const TextStyle(fontSize: 14)),
              trailing: Text(
                _formatSize(_docDirSize),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.settings_system_daydream_outlined, color: Colors.purple),
              title: Text('核心支持数据'.tr(), style: const TextStyle(fontSize: 14)),
              trailing: Text(
                _formatSize(_supportDirSize),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.cached_rounded, color: Colors.grey),
              title: Text('临时缓存数据'.tr(), style: const TextStyle(fontSize: 14)),
              trailing: Text(
                _formatSize(_tempDirSize),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${'总计'.tr()} $_storageSizeStr',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                ),
              ),
            ),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text('关闭'.tr()))],
      ),
    );
  }

  Future<double> _getTotalSizeOfFilesInDir(final FileSystemEntity file) async {
    try {
      if (file is File) {
        int length = await file.length();
        return double.parse(length.toString());
      }
      if (file is Directory) {
        final List<FileSystemEntity> children = file.listSync();
        double total = 0;
        for (final FileSystemEntity child in children) {
          total += await _getTotalSizeOfFilesInDir(child);
        }
        return total;
      }
      return 0;
    } catch (e) {
      return 0;
    }
  }

  String _formatSize(double value) {
    if (value == 0) return '0.00 B';
    if (value < 1024) {
      return '${value.toStringAsFixed(2)} B';
    } else if (value < 1024 * 1024) {
      return '${(value / 1024).toStringAsFixed(2)} KB';
    } else if (value < 1024 * 1024 * 1024) {
      return '${(value / (1024 * 1024)).toStringAsFixed(2)} MB';
    } else {
      return '${(value / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
  }

  Future<void> _clearCache() async {
    if (_cacheSizeStr == '0.00 B' || _cacheSizeStr == '未知'.tr() || _cacheSizeStr == '计算中...'.tr()) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('暂无缓存可清理'.tr()), behavior: SnackBarBehavior.floating));
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('清除缓存'.tr()),
        content: Text('确定要清除所有缓存数据吗？'.tr()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('取消'.tr())),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('确定'.tr(), style: const TextStyle(color: AppTheme.primaryColor)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      Directory tempDir = await getTemporaryDirectory();
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }

      if (!mounted) return;
      Navigator.pop(context); // 隐藏loading

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('缓存已清理'.tr()), behavior: SnackBarBehavior.floating));

      _loadAllSizes();
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // 隐藏loading
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('清理缓存失败'.tr()), behavior: SnackBarBehavior.floating));
    }
  }

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
            title: Text(
              '设置'.tr(),
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1),
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
                  _buildSectionTitle('通知设置'.tr()),
                  _buildCard([
                    _buildSwitchItem(
                      icon: Icons.notifications_outlined,
                      iconColor: const Color(0xFF6C63FF),
                      label: '新消息通知'.tr(),
                      value: _notificationEnabled,
                      onChanged: (v) {
                        setState(() => _notificationEnabled = v);
                        _updateSetting('notificationEnabled', v);
                      },
                    ),
                    _buildCardDivider(),
                    _buildSwitchItem(
                      icon: Icons.volume_up_outlined,
                      iconColor: const Color(0xFF00D9A6),
                      label: '声音'.tr(),
                      value: _soundEnabled,
                      onChanged: (v) {
                        setState(() => _soundEnabled = v);
                        _updateSetting('soundEnabled', v);
                      },
                    ),
                    _buildCardDivider(),
                    _buildSwitchItem(
                      icon: Icons.vibration_rounded,
                      iconColor: const Color(0xFFF97316),
                      label: '振动'.tr(),
                      value: _vibrateEnabled,
                      onChanged: (v) {
                        setState(() => _vibrateEnabled = v);
                        _updateSetting('vibrateEnabled', v);
                      },
                    ),
                    // _buildCardDivider(),
                    // _buildSwitchItem(
                    //   icon: Icons.visibility_outlined,
                    //   iconColor: const Color(0xFF3B82F6),
                    //   label: '消息预览'.tr(),
                    //   value: _showPreview,
                    //   onChanged: (v) => setState(() => _showPreview = v),
                    // ),
                  ]),

                  const SizedBox(height: 20),

                  // 隐私
                  _buildSectionTitle('隐私'.tr()),
                  _buildCard([
                    _buildNavItem(icon: Icons.block_outlined, iconColor: const Color(0xFFEF4444), label: '黑名单'.tr()),
                    _buildCardDivider(),
                    _buildNavItem(
                      icon: Icons.lock_outline_rounded,
                      iconColor: const Color(0xFF8B5CF6),
                      label: '隐私权限'.tr(),
                    ),
                    _buildCardDivider(),
                    _buildNavItem(
                      icon: Icons.delete_outline_rounded,
                      iconColor: const Color(0xFFF97316),
                      label: '清除聊天记录'.tr(),
                      onTap: _clearChatHistory,
                    ),
                  ]),

                  const SizedBox(height: 20),

                  // 服务器设置
                  _buildSectionTitle('服务器'.tr()),
                  _buildCard([
                    _buildNavItem(
                      icon: Icons.business_rounded,
                      iconColor: const Color(0xFF6366F1),
                      label: '切换服务器'.tr(),
                      onTap: _leaveCompany,
                    ),
                  ]),

                  const SizedBox(height: 20),

                  // 通用
                  _buildSectionTitle('通用'.tr()),
                  _buildCard([
                    _buildNavItem(
                      icon: Icons.language_rounded,
                      iconColor: const Color(0xFF06B6D4),
                      label: '语言'.tr(),
                      subtitle: _languageSubtitle(context),
                      onTap: () => _showLanguagePicker(),
                    ),
                    _buildCardDivider(),
                    _buildNavItem(
                      icon: Icons.font_download_outlined,
                      iconColor: const Color(0xFFFBBF24),
                      label: '字体大小'.tr(),
                      subtitle: _fontSizeLabel(),
                      onTap: _showFontSizePicker,
                    ),
                    _buildCardDivider(),
                    _buildNavItem(
                      icon: Icons.storage_outlined,
                      iconColor: const Color(0xFF22C55E),
                      label: '存储空间'.tr(),
                      subtitle: _storageSizeStr,
                      onTap: _showStorageDetails,
                    ),
                    _buildCardDivider(),
                    _buildNavItem(
                      icon: Icons.cached_rounded,
                      iconColor: const Color(0xFF6B7280),
                      label: '清除缓存'.tr(),
                      subtitle: _cacheSizeStr,
                      onTap: _clearCache,
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
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Theme.of(context).colorScheme.onSurface),
      ),
      trailing: AppSwitch(value: value, onChanged: onChanged),
    );
  }

  /// 退出公司
  Future<void> _leaveCompany() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('温馨提示'.tr()),
        content: Text('切换服务器将清除当前登录信息，确定要继续吗？'.tr()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('取消'.tr())),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('确定'.tr(), style: const TextStyle(color: AppTheme.primaryColor)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('companyId');
    await prefs.remove('accessToken');
    await prefs.remove('refreshToken');
    await prefs.remove('wsServer');
    await prefs.remove('userId');
    await prefs.remove('userAccount');
    await prefs.remove('userNickname');
    await prefs.remove('userAvatar');
    await prefs.remove('userEmail');
    await prefs.remove('userMobile');
    await prefs.remove('userSignature');
    await prefs.remove('userOnline');
    await prefs.remove('userSecretKey');

    if (!mounted) return;
    Navigator.of(
      context,
    ).pushAndRemoveUntil(MaterialPageRoute(builder: (context) => const CompanyPage()), (route) => false);
  }

  Future<void> _clearChatHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('清除聊天记录'.tr()),
        content: Text('确定要清除所有本地聊天记录吗？清除后不可恢复。'.tr()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('取消'.tr())),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('确定'.tr(), style: const TextStyle(color: AppTheme.primaryColor)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await DatabaseService().clearAllChatHistory();
      await ConversationService().notifyConversationListChanged();

      if (!mounted) return;
      Navigator.pop(context); // 隐藏loading

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('聊天记录已清除'.tr()), behavior: SnackBarBehavior.floating),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // 隐藏loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('清除失败'.tr()), behavior: SnackBarBehavior.floating),
      );
    }
  }

  /// 导航选项
  Widget _buildNavItem({
    required IconData icon,
    required Color iconColor,
    required String label,
    String? subtitle,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(
        label,
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Theme.of(context).colorScheme.onSurface),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (subtitle != null) Text(subtitle, style: const TextStyle(fontSize: 13, color: AppTheme.textHint)),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded, color: AppTheme.textHint, size: 20),
        ],
      ),
      onTap: onTap,
    );
  }

  Widget _buildCardDivider() {
    return const Padding(padding: EdgeInsets.only(left: 72), child: Divider(height: 0.5));
  }

  String _languageSubtitle(BuildContext context) {
    return context.locale.languageCode == 'en' ? '英文'.tr() : '简体中文'.tr();
  }

  Future<void> _showLanguagePicker() async {
    if (!mounted) return;
    final selected = await showDialog<Locale>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('语言'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text('简体中文'.tr()), onTap: () => Navigator.pop(dialogContext, const Locale('zh', 'CN'))),
            ListTile(title: Text('英文'.tr()), onTap: () => Navigator.pop(dialogContext, const Locale('en', 'US'))),
          ],
        ),
      ),
    );

    if (selected != null && mounted) {
      await context.setLocale(selected);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('selectedLocale', selected.toLanguageTag());
      setState(() {});
    }
  }

  String _fontSizeLabel() {
    final scale = ThemeService().textScale;
    if (scale <= 0.8) return '小'.tr();
    if (scale == 1.0) return '标准'.tr();
    if (scale == 1.2) return '大'.tr();
    if (scale >= 1.4) return '特大'.tr();
    return '标准'.tr();
  }

  Future<void> _showFontSizePicker() async {
    if (!mounted) return;

    final currentScale = ThemeService().textScale;
    double? selected = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('字体大小'.tr()),
        content: RadioGroup<double>(
          groupValue: currentScale,
          onChanged: (val) {
            if (val != null) {
              Navigator.pop(dialogContext, val);
            }
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<double>(title: Text('小'.tr()), value: 0.8, activeColor: AppTheme.primaryColor),
              RadioListTile<double>(title: Text('标准'.tr()), value: 1.0, activeColor: AppTheme.primaryColor),
              RadioListTile<double>(title: Text('大'.tr()), value: 1.2, activeColor: AppTheme.primaryColor),
              RadioListTile<double>(title: Text('特大'.tr()), value: 1.4, activeColor: AppTheme.primaryColor),
            ],
          ),
        ),
      ),
    );

    if (selected != null && mounted) {
      await ThemeService().setTextScale(selected);
      setState(() {});
    }
  }
}
