import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../models/conversation.dart';
import '../../models/db/conversation_entity.dart';
import '../../services/database_service.dart';
import '../../services/conversation_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_switch.dart';
import 'group_management_page.dart';

class ChatSettingsPage extends StatefulWidget {
  final Conversation conversation;

  const ChatSettingsPage({super.key, required this.conversation});

  @override
  State<ChatSettingsPage> createState() => _ChatSettingsPageState();
}

class _ChatSettingsPageState extends State<ChatSettingsPage> {
  late bool _isMuted;
  late bool _isPinned;
  late String _groupName;
  late String _groupAnnouncement;
  bool _isLoading = true;
  bool _isQuitting = false;

  @override
  void initState() {
    super.initState();
    _isMuted = widget.conversation.isMuted;
    _isPinned = widget.conversation.isPinned;
    _groupName = widget.conversation.title;
    _groupAnnouncement = '';
    _loadChatSettings();
  }

  Future<void> _loadChatSettings() async {
    final result = await ConversationService().getConversationDetail(widget.conversation.id);
    if (result != null && mounted) {
      setState(() {
        _isMuted = result.isMuted;
        _isPinned = result.isPinned;
        _groupName = result.title.isNotEmpty ? result.title : widget.conversation.title;
        _groupAnnouncement = result.announcement ?? '';
        _isLoading = false;
      });
      await _updateLocalDatabase();
    }
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updateLocalDatabase() async {
    final db = await DatabaseService().database;
    await db.update(
      ConversationEntity.tableName,
      {'is_muted': _isMuted ? 1 : 0, 'is_pinned': _isPinned ? 1 : 0},
      where: 'id = ?',
      whereArgs: [int.tryParse(widget.conversation.id) ?? 0],
    );
    await ConversationService().notifyConversationListChanged();
  }

  Future<void> _toggleMute(bool value) async {
    setState(() => _isMuted = value);

    final result = await ConversationService().muteConversation(widget.conversation.id, value ? 1 : 0);
    if (result != null && result['success'] == true && mounted) {
      await _updateLocalDatabase();
    } else {
      if (mounted) {
        setState(() => _isMuted = !value);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result?['message'] ?? '设置失败'.tr())));
      }
    }
  }

  Future<void> _togglePin(bool value) async {
    setState(() => _isPinned = value);

    final result = await ConversationService().pinTopConversation(widget.conversation.id, value ? 1 : 0);
    if (result != null && result['success'] == true && mounted) {
      await _updateLocalDatabase();
    } else {
      if (mounted) {
        setState(() => _isPinned = !value);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result?['message'] ?? '设置失败'.tr())));
      }
    }
  }

  Future<void> _updateGroupName() async {
    final controller = TextEditingController(text: _groupName);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('修改群名称'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: '请输入群名称', border: OutlineInputBorder()),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('确定')),
        ],
      ),
    );

    if (result != null && result.isNotEmpty && result != _groupName) {
      final updateResult = await ConversationService().updateGroupName(widget.conversation.id, result);
      if (updateResult != null && updateResult['success'] == true && mounted) {
        setState(() => _groupName = result);
        await _updateLocalConversationTitle(result);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(updateResult?['message'] ?? '群名称修改失败'.tr())));
      }
    }
  }

  Future<void> _updateLocalConversationTitle(String title) async {
    final db = await DatabaseService().database;
    await db.update(
      ConversationEntity.tableName,
      {'title': title},
      where: 'id = ?',
      whereArgs: [int.tryParse(widget.conversation.id) ?? 0],
    );
    await ConversationService().notifyConversationListChanged();
  }

  Future<void> _updateGroupAnnouncement() async {
    final controller = TextEditingController(text: _groupAnnouncement);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('修改群公告'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: '请输入群公告', border: OutlineInputBorder()),
          maxLines: 5,
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('确定')),
        ],
      ),
    );

    if (result != null && result != _groupAnnouncement) {
      final updateResult = await ConversationService().updateGroupAnnouncement(widget.conversation.id, result);
      if (updateResult != null && updateResult['success'] == true && mounted) {
        setState(() => _groupAnnouncement = result);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('群公告修改成功'.tr()), backgroundColor: AppTheme.onlineColor));
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(updateResult?['message'] ?? '群公告修改失败'.tr())));
      }
    }
  }

  // Future<void> _showAlertDialog(BuildContext context) async {
  //   return showDialog<void>(
  //     context: context,
  //     barrierDismissible: true,
  //     builder: (context) => AlertDialog(
  //       title: const Text('提示'),
  //       content: const Text('群公告修改成功'),
  //       actions: [
  //         TextButton(child: const Text('取消'), onPressed: () => Navigator.pop(context)),
  //         TextButton(child: const Text('确定'), onPressed: () => Navigator.pop(context)),
  //       ],
  //     ),
  //   );
  // }

  void _showGroupQrCode() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('群二维码', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              QrImageView(
                data: 'cryptalk:join_group?id=${widget.conversation.id}',
                version: QrVersions.auto,
                size: 200,
                backgroundColor: Colors.white,
              ),
              const SizedBox(height: 10),
              Text(_groupName, style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
              const SizedBox(height: 20),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _navigateToGroupManagement() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Center(child: CircularProgressIndicator()),
      ),
    );

    try {
      final result = await ConversationService().getMyRole(widget.conversation.id);
      if (!mounted) return;

      Navigator.of(context, rootNavigator: true).pop(); // 关闭 loading

      if (result != null && result['success'] == true) {
        final role = result['data'];
        if (role == 1 || role == 2) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => GroupManagementPage(conversation: widget.conversation)),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('仅限群主或管理员才能进入群管理')));
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result?['message'] ?? '获取角色权限失败'.tr())));
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // 发生异常时关闭 loading
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('获取角色权限异常')));
    }
  }

  Future<void> _quitGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出群聊'),
        content: const Text('确定要退出该群聊吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('退出'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _isQuitting = true);
      try {
        final result = await ConversationService().quitGroup(widget.conversation.id);
        if (result.success == true && mounted) {
          final db = await DatabaseService().database;
          await db.delete(
            ConversationEntity.tableName,
            where: 'id = ?',
            whereArgs: [int.tryParse(widget.conversation.id) ?? 0],
          );
          await ConversationService().notifyConversationListChanged();
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('已退出群聊'.tr()), backgroundColor: AppTheme.onlineColor));
            Navigator.of(context).popUntil((route) => route.isFirst);
          }
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
        }
      } finally {
        if (mounted) {
          setState(() => _isQuitting = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isGroup = widget.conversation.isGroup;

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg,
      appBar: AppBar(
        flexibleSpace: Container(decoration: AppTheme.getAppBarDecoration(context)),
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          isGroup ? '群设置' : '聊天设置',
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                const SizedBox(height: 10),
                if (isGroup) ...[
                  _buildSettingItem(
                    icon: Icons.group_outlined,
                    title: '群名称',
                    subtitle: _groupName,
                    onTap: _updateGroupName,
                  ),
                  _buildSettingItem(icon: Icons.qr_code_2_outlined, title: '群二维码', onTap: _showGroupQrCode),
                  _buildSettingItem(
                    icon: Icons.campaign_outlined,
                    title: '群公告',
                    subtitle: _groupAnnouncement.isEmpty ? '暂无公告' : _groupAnnouncement,
                    subtitleMaxLines: 2,
                    onTap: _updateGroupAnnouncement,
                  ),
                  const SizedBox(height: 10),
                ],
                _buildSettingItem(
                  icon: Icons.notifications_off_outlined,
                  title: '消息免打扰',
                  trailing: AppSwitch(value: _isMuted, onChanged: _toggleMute),
                ),
                _buildSettingItem(
                  icon: Icons.push_pin_outlined,
                  title: '置顶聊天',
                  trailing: AppSwitch(value: _isPinned, onChanged: _togglePin),
                ),
                if (isGroup) ...[
                  const SizedBox(height: 10),
                  _buildSettingItem(
                    icon: Icons.admin_panel_settings_outlined,
                    title: '群管理',
                    onTap: _navigateToGroupManagement,
                  ),
                ],
                const SizedBox(height: 80),
                if (isGroup)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _isQuitting
                        ? const Center(child: CircularProgressIndicator())
                        : ElevatedButton(
                            onPressed: _quitGroup,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: const Text('退出群聊', style: TextStyle(fontSize: 16)),
                          ),
                  ),
                const SizedBox(height: 30),
              ],
            ),
    );
  }

  Widget _buildSettingItem({
    required IconData icon,
    required String title,
    String? subtitle,
    int subtitleMaxLines = 1,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: Icon(icon, color: AppTheme.primaryColor),
        title: Text(title, style: const TextStyle(fontSize: 16, color: AppTheme.textPrimary)),
        subtitle: subtitle != null
            ? Text(
                subtitle,
                style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                maxLines: subtitleMaxLines,
                overflow: TextOverflow.ellipsis,
              )
            : null,
        trailing: trailing ?? const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
}
