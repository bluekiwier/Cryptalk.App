import 'package:flutter/material.dart';
import '../../models/conversation.dart';
import '../../services/database_service.dart';
import '../../services/conversation_service.dart';
import '../../theme/app_theme.dart';

class ChatSettingsPage extends StatefulWidget {
  final Conversation conversation;

  const ChatSettingsPage({super.key, required this.conversation});

  @override
  State<ChatSettingsPage> createState() => _ChatSettingsPageState();
}

class _ChatSettingsPageState extends State<ChatSettingsPage> {
  late bool _isMuted;
  late bool _isPinned;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _isMuted = widget.conversation.isMuted;
    _isPinned = widget.conversation.isPinned;
    _loadChatSettings();
  }

  Future<void> _loadChatSettings() async {
    final result = await ConversationService().getChatSettings(widget.conversation.id);
    if (result != null && result['success'] == true && mounted) {
      final data = result['data'];
      if (data != null) {
        setState(() {
          _isMuted = (data['isMuted'] ?? 0) == 1;
          _isPinned = (data['isPinned'] ?? 0) == 1;
          _isLoading = false;
        });
        await _updateLocalDatabase();
      }
    }
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updateLocalDatabase() async {
    final db = await DatabaseService().database;
    await db.update(
      'conversations',
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result?['message'] ?? '设置失败')));
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result?['message'] ?? '设置失败')));
      }
    }
  }

  // Future<void> _clearChatHistory() async {
  //   final confirmed = await showDialog<bool>(
  //     context: context,
  //     builder: (context) => AlertDialog(
  //       title: const Text('清空聊天记录'),
  //       content: const Text('确定要清空与该用户的聊天记录吗？此操作不可恢复。'),
  //       actions: [
  //         TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
  //         TextButton(
  //           onPressed: () => Navigator.pop(context, true),
  //           style: TextButton.styleFrom(foregroundColor: Colors.red),
  //           child: const Text('清空'),
  //         ),
  //       ],
  //     ),
  //   );

  //   if (confirmed == true && mounted) {
  //     final db = await DatabaseService().database;
  //     await db.delete('messages', where: 'conversation_id = ?', whereArgs: [int.tryParse(widget.conversation.id) ?? 0]);
  //     if (mounted) {
  //       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('聊天记录已清空')));
  //       Navigator.pop(context);
  //     }
  //   }
  // }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '聊天设置',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                const SizedBox(height: 10),
                _buildSettingItem(
                  icon: Icons.notifications_off_outlined,
                  title: '消息免打扰',
                  trailing: Switch(
                    value: _isMuted,
                    onChanged: _toggleMute,
                    activeTrackColor: AppTheme.primaryColor.withValues(alpha: 0.5),
                    thumbColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return AppTheme.primaryColor;
                      }
                      return Colors.grey;
                    }),
                  ),
                ),
                _buildSettingItem(
                  icon: Icons.push_pin_outlined,
                  title: '置顶聊天',
                  trailing: Switch(
                    value: _isPinned,
                    onChanged: _togglePin,
                    activeTrackColor: AppTheme.primaryColor.withValues(alpha: 0.5),
                    thumbColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return AppTheme.primaryColor;
                      }
                      return Colors.grey;
                    }),
                  ),
                ),
                // _buildSettingItem(
                //   icon: Icons.delete_outline,
                //   title: '清空聊天记录',
                //   titleColor: Colors.red,
                //   onTap: _clearChatHistory,
                // ),
              ],
            ),
    );
  }

  Widget _buildSettingItem({
    required IconData icon,
    required String title,
    Widget? trailing,
    Color? titleColor,
    VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: Icon(icon, color: titleColor ?? AppTheme.primaryColor),
        title: Text(title, style: TextStyle(fontSize: 16, color: titleColor ?? AppTheme.textPrimary)),
        trailing: trailing ?? const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
}
