import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import '../../models/conversation.dart';
import '../../services/conversation_service.dart';
import '../../services/file_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/avatar_widget.dart';
import '../../widgets/app_switch.dart';

/// 群管理页面，用于管理群成员、群设置等
class GroupManagementPage extends StatefulWidget {
  final Conversation conversation;

  const GroupManagementPage({super.key, required this.conversation});

  @override
  State<GroupManagementPage> createState() => _GroupManagementPageState();
}

class _GroupManagementPageState extends State<GroupManagementPage> {
  List<dynamic> _members = [];
  List<dynamic> _filteredMembers = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  int _currentPage = 1;
  bool _hasMore = true;
  bool _isAllMuted = false;
  bool _isUpdatingAvatar = false;
  String _searchKeyword = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadGroupDetail();
    _loadGroupMembers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadGroupDetail() async {
    final result = await ConversationService().getConversationDetail(widget.conversation.id);
    if (result != null && mounted) {
      setState(() {
        _isAllMuted = result.isAllMuted;
      });
    }
  }

  Future<void> _loadGroupMembers({bool refresh = false}) async {
    if (refresh) {
      _currentPage = 1;
      _hasMore = true;
    }
    setState(() => _isLoading = true);

    final result = await ConversationService().getGroupMembers(
      widget.conversation.id,
      page: _currentPage,
      keyword: _searchKeyword,
    );

    if (result != null && result['success'] == true && mounted) {
      final data = result['data'];
      if (data != null) {
        final list = data['list'] as List<dynamic>?;
        final hasNext = data['hasNext'] == true;

        if (list != null) {
          setState(() {
            if (refresh || _currentPage == 1) {
              _members = list;
            } else {
              _members = [..._members, ...list];
            }
            _filteredMembers = _members;
            _hasMore = hasNext;
            _isLoading = false;
          });
        }
      }
    }
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMoreMembers() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() {
      _isLoadingMore = true;
      _currentPage++;
    });

    await _loadGroupMembers();

    if (mounted) {
      setState(() => _isLoadingMore = false);
    }
  }

  void _onSearchChanged(String value) {
    setState(() {
      _searchKeyword = value;
      _filteredMembers = _members.where((member) {
        final nickname = (member['nickname'] ?? '').toString().toLowerCase();
        final account = (member['account'] ?? '').toString().toLowerCase();
        final keyword = value.toLowerCase();
        return nickname.contains(keyword) || account.contains(keyword);
      }).toList();
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchKeyword = '';
      _filteredMembers = _members;
    });
  }

  Future<void> _showMemberActions(BuildContext context, dynamic member) async {
    final userId = member['userId'];
    final nickname = member['nickname'] ?? '';
    final avatar = member['avatar'] ?? '';
    final isOwner = member['role'] == 1;
    final isAdmin = member['role'] == 2;

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: AvatarWidget(avatar: avatar ?? '', size: 40),
              title: Text(nickname),
              subtitle: Text(isOwner ? '群主' : (isAdmin ? '管理员' : '成员')),
            ),
            const Divider(),
            if (!isOwner) ...[
              ListTile(
                leading: Icon(isAdmin ? Icons.arrow_downward : Icons.arrow_upward),
                title: Text(isAdmin ? '移除管理员' : '设为管理员'),
                onTap: () async {
                  Navigator.pop(context);
                  if (isAdmin) {
                    await _removeAdmin(userId);
                  } else {
                    await _addAdmin(userId);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.volume_off),
                title: const Text('禁言'),
                onTap: () {
                  Navigator.pop(context);
                  _showMuteDialog(userId, nickname);
                },
              ),
              ListTile(
                leading: const Icon(Icons.remove_circle, color: Colors.red),
                title: const Text('移出群聊', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _showRemoveMemberDialog(userId, nickname);
                },
              ),
            ],
            if (!isOwner) ...[
              ListTile(
                leading: const Icon(Icons.swap_horiz),
                title: const Text('转让群主'),
                onTap: () {
                  Navigator.pop(context);
                  _showTransferOwnerDialog(userId, nickname);
                },
              ),
            ],
            ListTile(leading: const Icon(Icons.cancel), title: const Text('取消'), onTap: () => Navigator.pop(context)),
          ],
        ),
      ),
    );
  }

  Future<void> _addAdmin(int userId) async {
    final result = await ConversationService().addGroupAdmin(widget.conversation.id, userId);
    if (result != null && result['success'] == true) {
      _showToast('已设为管理员', isSuccess: true);
      await _loadGroupMembers();
    } else {
      _showToast(result?['message'] ?? '操作失败');
    }
  }

  Future<void> _removeAdmin(int userId) async {
    final result = await ConversationService().removeGroupAdmin(widget.conversation.id, userId);
    if (result != null && result['success'] == true) {
      _showToast('已移除管理员', isSuccess: true);
      await _loadGroupMembers();
    } else {
      _showToast(result?['message'] ?? '操作失败');
    }
  }

  Future<void> _showMuteDialog(dynamic userId, String nickname) async {
    final durations = [
      {'label': '取消禁言', 'value': -1},
      {'label': '30分钟', 'value': 30},
      {'label': '1小时', 'value': 60},
      {'label': '24小时', 'value': 1440},
      {'label': '7天', 'value': 10080},
      {'label': '永久禁言', 'value': 0},
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('禁言 $nickname'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: durations.map((d) {
            return ListTile(
              title: Text(d['label'] as String),
              onTap: () async {
                Navigator.pop(context);
                final value = d['value'] as int;
                final result = value == -1
                    ? await ConversationService().unmuteMember(widget.conversation.id, userId)
                    : await ConversationService().muteMember(widget.conversation.id, userId, value);
                if (result != null && result['success'] == true) {
                  _showToast(value == -1 ? '已取消禁言' : '已禁言', isSuccess: true);
                } else {
                  _showToast(result?['message'] ?? '操作失败');
                }
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  Future<void> _showRemoveMemberDialog(int userId, String nickname) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移出群聊'),
        content: Text('确定要将 $nickname 移出群聊吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final result = await ConversationService().removeGroupMember(widget.conversation.id, userId);
      if (result != null && result['success'] == true) {
        _showToast('已移出群聊', isSuccess: true);
        await _loadGroupMembers();
      } else {
        _showToast(result?['message'] ?? '操作失败');
      }
    }
  }

  Future<void> _showTransferOwnerDialog(int userId, String nickname) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('转让群主'),
        content: Text('确定要将群主转让给 $nickname 吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final result = await ConversationService().transferGroupOwner(widget.conversation.id, userId);
      if (result != null && result['success'] == true) {
        _showToast('已转让群主', isSuccess: true);
        if (mounted) Navigator.pop(context);
      } else {
        _showToast(result?['message'] ?? '操作失败');
      }
    }
  }

  Future<void> _showDissolveGroupDialog() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('解散群聊'),
        content: const Text('确定要解散该群聊吗？此操作不可恢复！'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final result = await ConversationService().dissolveGroup(widget.conversation.id);
      if (result != null && result['success'] == true) {
        _showToast('群聊已解散', isSuccess: true);
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      } else {
        _showToast(result?['message'] ?? '操作失败');
      }
    }
  }

  void _showToast(String message, {bool isSuccess = false}) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message), backgroundColor: isSuccess ? AppTheme.onlineColor : null));
    }
  }

  Future<void> _showAddMemberDialog() async {
    final controller = TextEditingController();
    final account = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('邀请成员'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.text,
          decoration: const InputDecoration(hintText: '请输入用户账号', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('确定')),
        ],
      ),
    );

    if (account != null && account.isNotEmpty) {
      final result = await ConversationService().addGroupMember(widget.conversation.id, account);
      if (result != null && result['success'] == true) {
        _showToast('邀请成功', isSuccess: true);
        await _loadGroupMembers(refresh: true);
      } else {
        _showToast(result?['message'] ?? '邀请失败');
      }
    }
  }

  /// 选择并上传群头像
  Future<void> _pickAndUploadAvatar() async {
    final ImagePicker picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('从相册选择'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('拍照'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    try {
      final XFile? pickedFile = await picker.pickImage(source: source);
      if (pickedFile == null || !mounted) return;

      final croppedFile = await ImageCropper().cropImage(
        sourcePath: pickedFile.path,
        maxWidth: 512,
        maxHeight: 512,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: '裁剪头像',
            toolbarColor: AppTheme.primaryColor,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: true,
          ),
          IOSUiSettings(title: '裁剪头像', aspectRatioLockEnabled: true),
        ],
      );

      if (croppedFile == null || !mounted) return;

      setState(() => _isUpdatingAvatar = true);

      final filePath = croppedFile.path;
      final outPath = "${Directory.systemTemp.path}/group_avatar_${DateTime.now().millisecondsSinceEpoch}.png";

      final result = await FlutterImageCompress.compressAndGetFile(
        filePath,
        outPath,
        quality: 90,
        minWidth: 512,
        minHeight: 512,
        format: CompressFormat.png,
      );

      if (result == null) throw Exception("压缩图片失败");

      final compressedFile = File(result.path);
      final fileSize = await compressedFile.length();
      final fileName = "group_${widget.conversation.id}_${DateTime.now().millisecondsSinceEpoch}.png";

      final uploadResult = await FileService().createUploadUrl("image/png", fileName, fileSize, "group-avatar");

      if (uploadResult == null || !uploadResult.isSuccess) {
        throw Exception("获取上传凭证失败");
      }

      final fileBytes = await compressedFile.readAsBytes();
      final uploaded = await FileService().uploadToR2(uploadResult.uploadUrl!, fileBytes, "image/png");

      if (!uploaded) {
        throw Exception("上传图片到存储失败");
      }

      final updateResult = await ConversationService().updateGroupAvatar(widget.conversation.id, uploadResult.fileUrl!);

      if (mounted) {
        if (updateResult != null && updateResult['success'] == true) {
          _showToast('群头像更新成功', isSuccess: true);
          // 发送全局通知或通过回调更新上一级页面
          await ConversationService().notifyConversationListChanged();
        } else {
          _showToast(updateResult?['message'] ?? '头像更新失败');
        }
      }
    } catch (e) {
      if (mounted) _showToast('操作失败: $e');
    } finally {
      if (mounted) setState(() => _isUpdatingAvatar = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
        title: const Text(
          '群管理',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add, color: Colors.white),
            onPressed: _showAddMemberDialog,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildSearchBar(),
                Expanded(
                  child: ListView(
                    children: [
                      // const SizedBox(height: 10),
                      _buildSectionHeader('群成员 (${_filteredMembers.length})'),
                      _buildMemberList(),
                      _buildLoadMoreButton(),
                      const SizedBox(height: 10),
                      _buildMuteAllSwitch(),
                      _buildUpdateAvatarItem(),
                      const SizedBox(height: 80),
                      _buildManagementSection(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSearchBar() {
    return Column(
      children: [
        Container(
          color: Theme.of(context).cardColor,
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: '搜索成员昵称或账号',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchKeyword.isNotEmpty
                  ? IconButton(icon: const Icon(Icons.clear), onPressed: _clearSearch)
                  : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              filled: true,
              fillColor: Theme.of(context).scaffoldBackgroundColor,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadMoreButton() {
    if (_searchKeyword.isNotEmpty) return const SizedBox.shrink();
    if (!_hasMore || _members.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: _isLoadingMore
            ? const CircularProgressIndicator()
            : TextButton(onPressed: _loadMoreMembers, child: const Text('点击加载更多')),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(title, style: const TextStyle(fontSize: 14, color: Colors.grey)),
    );
  }

  /// 构建群成员列表
  Widget _buildMemberList() {
    return Container(
      color: Colors.white,
      child: Column(
        children: _filteredMembers.map((member) {
          final nickname = member['nickname'] ?? member['name'] ?? '未知';
          final avatar = member['avatar'] ?? '';
          final isOwner = member['role'] == 1;
          final isAdmin = member['role'] == 2;

          return ListTile(
            leading: CircleAvatar(
              backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
              child: avatar.isEmpty ? const Icon(Icons.person) : null,
            ),
            title: Text(nickname),
            subtitle: Text(isOwner ? '群主' : (isAdmin ? '管理员' : '')),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () => _showMemberActions(context, member),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMuteAllSwitch() {
    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('全体禁言', style: TextStyle(fontSize: 16)),
              AppSwitch(
                value: _isAllMuted,
                onChanged: (value) async {
                  if (value) {
                    final result = await ConversationService().muteAll(widget.conversation.id);
                    if (result != null && result['success'] == true) {
                      _showToast('已开启全体禁言', isSuccess: true);
                      setState(() => _isAllMuted = true);
                    } else {
                      _showToast(result?['message'] ?? '操作失败');
                    }
                  } else {
                    final result = await ConversationService().unmuteAll(widget.conversation.id);
                    if (result != null && result['success'] == true) {
                      _showToast('已关闭全体禁言', isSuccess: true);
                      setState(() => _isAllMuted = false);
                    } else {
                      _showToast(result?['message'] ?? '操作失败');
                    }
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 构建群管理操作按钮
  Widget _buildManagementSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: ElevatedButton(
        onPressed: _showDissolveGroupDialog,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: const Text('解散群聊'),
      ),
    );
  }

  Widget _buildUpdateAvatarItem() {
    return Column(
      children: [
        const Divider(height: 1, indent: 16, endIndent: 16),
        InkWell(
          onTap: _isUpdatingAvatar ? null : _pickAndUploadAvatar,
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('修改群头像', style: TextStyle(fontSize: 16)),
                Row(
                  children: [
                    if (_isUpdatingAvatar)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryColor),
                      )
                    else
                      const Icon(Icons.chevron_right, color: Colors.grey),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
