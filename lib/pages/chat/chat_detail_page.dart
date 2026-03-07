import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import '../../theme/app_theme.dart';
import '../../data/mock_data.dart';
import '../../models/conversation.dart';
import '../../models/message.dart';
import '../../widgets/avatar_widget.dart';
import '../../services/account_service.dart';
import '../../services/chat_service.dart';
import '../../services/conversation_service.dart';
import '../../services/message_service.dart';
import '../../services/database_service.dart';

/// 聊天详情页面
/// 展示与某人或某群的具体聊天内容
class ChatDetailPage extends StatefulWidget {
  final Conversation conversation;

  const ChatDetailPage({super.key, required this.conversation});

  @override
  State<ChatDetailPage> createState() => _ChatDetailPageState();
}

class _ChatDetailPageState extends State<ChatDetailPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late List<Message> _messages;
  bool _isLoading = false;
  bool _hasMore = true;
  Message? _quotedMessage;

  final ChatService _chatService = ChatService();
  final AccountService _accountService = AccountService();
  final _logger = Logger();

  @override
  void initState() {
    super.initState();
    _messages = [];
    // 设置当前聊天会话ID
    _chatService.setCurrentChatConversation(widget.conversation.id);
    // 进入聊天页时清零未读数
    ConversationService().clearUnread(widget.conversation.id);
    _loadMessagesAndSync();
    // 监听WebSocket消息
    _chatService.addListener(_onChatServiceUpdated);
  }

  /// 加载本地消息并同步最新消息
  Future<void> _loadMessagesAndSync() async {
    await _loadMessages();
    // 加载完成后再同步最新消息
    _syncLatestMessages();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    // 移除监听
    _chatService.removeListener(_onChatServiceUpdated);
    // 清除当前聊天会话ID
    _chatService.setCurrentChatConversation(null);
    super.dispose();
  }

  /// 处理ChatService更新
  void _onChatServiceUpdated() async {
    // 从ChatService获取当前会话的新消息
    final newMessages = _chatService.getMessagesForConversation(widget.conversation.id);
    if (newMessages.isNotEmpty) {
      // 保存到本地数据库
      for (final chatMessage in newMessages) {
        final quoteIdStr = chatMessage.payload.quoteId;
        final quoteId = quoteIdStr.isNotEmpty ? (int.tryParse(quoteIdStr) ?? 0) : 0;
        await DatabaseService().insertMessage({
          'id': chatMessage.payload.id,
          'conversation_id': int.parse(widget.conversation.id),
          'conversation_type': widget.conversation.isGroup ? 2 : 1,
          'sender_id': chatMessage.payload.senderId,
          'quote_id': quoteId,
          'content': chatMessage.payload.content,
          'type': 0,
          'status': 0,
          'created_at': chatMessage.payload.createdAt,
        });
      }

      setState(() {
        // 将新消息转换为Message对象并添加到列表中
        for (final chatMessage in newMessages) {
          final quoteIdStr = chatMessage.payload.quoteId;
          final message = Message(
            id: chatMessage.payload.id,
            senderId: chatMessage.payload.senderId,
            content: chatMessage.payload.content,
            createdAt: DateTime.tryParse(chatMessage.payload.createdAt) ?? DateTime.now(),
            isRead: true,
            quoteId: quoteIdStr.isNotEmpty ? quoteIdStr : null,
          );
          // 检查消息是否已经存在
          if (!_messages.any((m) => m.id == message.id)) {
            _messages.add(message);
          }
        }
        // 对消息按ID排序（升序，旧在前、新在后），安全处理非数字ID
        _messages.sort((a, b) {
          final aId = int.tryParse(a.id) ?? 0;
          final bId = int.tryParse(b.id) ?? 0;
          return aId.compareTo(bId);
        });
      });

      // 滚动到底部
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  /// 从本地数据库加载消息
  Future<void> _loadMessages({bool isLoadMore = false}) async {
    if (_isLoading) return;
    if (isLoadMore && !_hasMore) return;

    setState(() {
      _isLoading = true;
    });

    int minMessageId = 0;
    if (isLoadMore && _messages.isNotEmpty) {
      // 找出当前列表中最小的消息ID作为翻页依据
      minMessageId = _messages
          .map((m) => int.tryParse(m.id) ?? 0)
          .where((id) => id > 0)
          .fold(0, (minId, id) => (minId == 0 || id < minId) ? id : minId);
    }

    final messageMaps = await DatabaseService().getMessages(
      int.parse(widget.conversation.id),
      limit: 20,
      minMessageId: minMessageId,
    );

    final newMessages = messageMaps.map((map) {
      _logger.d('从数据库读取消息: $map');
      final quoteIdInt = map['quote_id'] as int?;
      return Message(
        id: map['id']?.toString() ?? '',
        senderId: map['sender_id']?.toString() ?? '',
        content: map['content']?.toString() ?? '',
        type: MessageType.values.firstWhere((e) => e.index == (map['type'] ?? 0), orElse: () => MessageType.text),
        createdAt: map['created_at'] != null
            ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
            : DateTime.now(),
        isRead: true, // 默认设为已读
        quoteId: quoteIdInt != null && quoteIdInt > 0 ? quoteIdInt.toString() : null,
      );
    }).toList();

    // 对新的消息按ID升序（旧在前、新在后）确保UI表现正常
    newMessages.sort((a, b) => int.parse(a.id).compareTo(int.parse(b.id)));

    if (mounted) {
      setState(() {
        if (isLoadMore) {
          _messages.insertAll(0, newMessages);
        } else {
          _messages = newMessages;
        }
        _hasMore = newMessages.length == 20;
        _isLoading = false;
      });

      // 如果是首次加载或者是刷新最新页，滚动到底部
      if (!isLoadMore) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
          }
        });
      }
    }
  }

  /// 后台非阻塞同步最新消息
  Future<void> _syncLatestMessages() async {
    // 获取本地最新消息ID
    int latestMessageId = 0;
    if (_messages.isNotEmpty) {
      // 检查消息ID是否为数字格式
      final numericIds = _messages
          .map((m) => int.tryParse(m.id))
          .where((id) => id != null && id > 0)
          .cast<int>()
          .toList();

      if (numericIds.isNotEmpty) {
        latestMessageId = numericIds.reduce((a, b) => a > b ? a : b);
      }
    }

    // 从服务器同步最新消息
    final response = await ConversationService().getMessages(
      int.parse(widget.conversation.id),
      messageId: latestMessageId,
      pageSize: 30,
    );

    // 检查是否有网络超时错误
    if (response != null && response['success'] == false && response['error'] == 'connection_timeout') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(response['message'] ?? '网络连接超时，请检查网络后重试'), duration: const Duration(seconds: 3)),
        );
      }
      return;
    }

    if (response != null && response['success'] == true) {
      final data = response['data'];
      final list = (data['list'] as List<dynamic>?) ?? [];

      // 将消息转换为数据库格式并存储
      final messageRows = list.map((json) {
        _logger.d('从服务器同步消息: $json');
        return {
          'id': json['id'],
          'conversation_id': int.parse(widget.conversation.id),
          'conversation_type': widget.conversation.isGroup ? 2 : 1,
          'sender_id': json['senderId'],
          'quote_id': json['quoteId'] ?? 0,
          'content': json['content'],
          'type': json['type'] ?? 0,
          'status': json['status'] ?? 0,
          'created_at': json['createdAt'],
        };
      }).toList();

      // 批量插入到本地数据库
      await DatabaseService().insertMessages(messageRows);

      final newMessages = list.map((json) {
        final quoteIdInt = json['quoteId'] as int?;
        return Message(
          id: json['id']?.toString() ?? '',
          senderId: json['senderId']?.toString() ?? '',
          content: json['content']?.toString() ?? '',
          type: MessageType.values.firstWhere((e) => e.index == (json['type'] ?? 0), orElse: () => MessageType.text),
          createdAt: json['createdAt'] != null
              ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
              : DateTime.now(),
          isRead: true, // 默认设为已读
          quoteId: quoteIdInt != null && quoteIdInt > 0 ? quoteIdInt.toString() : null,
        );
      }).toList();

      // 对新的消息按ID升序（旧在前、新在后）确保UI表现正常
      newMessages.sort((a, b) => int.parse(a.id).compareTo(int.parse(b.id)));

      if (mounted) {
        setState(() {
          // 去重合并新消息
          for (final message in newMessages) {
            if (!_messages.any((m) => m.id == message.id)) {
              _messages.add(message);
            }
          }
          // 重新排序所有消息
          _messages.sort((a, b) => int.parse(a.id).compareTo(int.parse(b.id)));
        });

        // 滚动到底部
        Future.delayed(const Duration(milliseconds: 100), () {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          // 消息列表
          Expanded(child: _buildMessageList()),
          // 底部输入栏
          _buildInputBar(),
        ],
      ),
    );
  }

  /// 构建顶部 AppBar
  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(60),
      child: Container(
        decoration: const BoxDecoration(gradient: AppTheme.headerGradient),
        child: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          title: Column(
            children: [
              Text(
                widget.conversation.title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              if (widget.conversation.isGroup)
                Text(
                  '${widget.conversation.members.length}人',
                  style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.7)),
                ),
            ],
          ),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.phone_outlined, size: 22, color: Colors.white),
              onPressed: () {},
            ),
            IconButton(
              icon: const Icon(Icons.more_horiz_rounded, size: 22, color: Colors.white),
              onPressed: () {},
            ),
          ],
        ),
      ),
    );
  }

  /// 构建消息列表
  Widget _buildMessageList() {
    if (_messages.isEmpty && _isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListenableBuilder(
      listenable: _accountService,
      builder: (context, child) {
        final currentUserId = _accountService.currentUser?.id;
        _logger.d('当前用户ID: $currentUserId, 消息数量: ${_messages.length}');

        return RefreshIndicator(
          onRefresh: () => _loadMessages(isLoadMore: true),
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final message = _messages[index];
              final isMe = message.senderId == currentUserId;

              // 时间分隔线
              final showTime =
                  index == 0 || _messages[index].createdAt.difference(_messages[index - 1].createdAt).inMinutes > 1;

              return Column(
                children: [if (showTime) _buildTimeLabel(message.createdAt), _buildMessageBubble(message, isMe)],
              );
            },
          ),
        );
      },
    );
  }

  /// 时间标签
  Widget _buildTimeLabel(DateTime time) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10)),
        child: Text(_formatMessageTime(time.toLocal()), style: const TextStyle(fontSize: 11, color: AppTheme.textHint)),
      ),
    );
  }

  /// 消息气泡
  Widget _buildMessageBubble(Message message, bool isMe) {
    final key = GlobalKey();
    final quotedMessage = message.quoteId != null
        ? _messages.firstWhere(
            (m) => m.id == message.quoteId,
            orElse: () => Message(id: '', content: '消息已删除', createdAt: DateTime.now()),
          )
        : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[AvatarWidget(avatar: widget.conversation.avatar, size: 36), const SizedBox(width: 8)],
          Flexible(
            child: GestureDetector(
              key: key,
              onLongPress: () => _showMessageMenu(message, isMe, key),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  gradient: isMe ? AppTheme.headerGradient : null,
                  color: isMe ? null : Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isMe ? 16 : 4),
                    bottomRight: Radius.circular(isMe ? 4 : 16),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (isMe ? AppTheme.primaryColor : Colors.black).withValues(alpha: 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (quotedMessage != null && quotedMessage.id.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: (isMe ? Colors.white : AppTheme.surfaceBg).withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(8),
                          border: Border(
                            left: BorderSide(
                              color: isMe ? Colors.white.withValues(alpha: 0.8) : AppTheme.primaryColor,
                              width: 3,
                            ),
                          ),
                        ),
                        child: Text(
                          quotedMessage.content,
                          style: TextStyle(
                            fontSize: 13,
                            color: (isMe ? Colors.white : AppTheme.textSecondary).withValues(alpha: 0.8),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    Text(
                      message.content,
                      style: TextStyle(fontSize: 15, color: isMe ? Colors.white : AppTheme.textPrimary, height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: 8),
            AvatarWidget(avatar: _accountService.currentUser?.avatar ?? MockData.currentUser.avatar, size: 36),
          ],
        ],
      ),
    );
  }

  /// 显示消息操作菜单
  void _showMessageMenu(Message message, bool isMe, GlobalKey key) async {
    // 获取消息控件的位置和大小
    final RenderBox? renderBox = key.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final offset = renderBox.localToGlobal(Offset.zero); // 获取消息气泡在屏幕上的绝对坐标
    final size = renderBox.size; // 获取消息气泡的尺寸
    final screenSize = MediaQuery.of(context).size; // 获取屏幕尺寸
    const menuPadding = 2.0; // 菜单内边距
    const itemWidth = 56.0; // 菜单项宽度
    final itemCount = isMe ? 3 : 2; // 菜单项数量（自己发的消息有3个选项：引用、复制、删除；别人的消息有2个：引用、复制）
    const menuHeight = 60.0; // 菜单高度
    const inputBarHeight = 100.0; // 底部输入栏高度

    double left = offset.dx; // 菜单左侧与气泡左侧对齐
    double top = offset.dy + size.height - 20; // 菜单位于气泡下方，刚好贴近

    if (top + menuHeight > screenSize.height - inputBarHeight) {
      top = offset.dy - menuHeight - 35; // 如果下方空间不足，将菜单移至气泡上方，刚好贴近
    }

    final menuWidth = itemWidth * itemCount + menuPadding * 2; // 计算菜单总宽度
    if (left + menuWidth > screenSize.width - 20) {
      left = screenSize.width - menuWidth - 20; // 如果右侧空间不足，向左移动菜单，使其距离屏幕右边缘20像素
    }

    if (left < 16) {
      left = 16; // 如果左侧空间不足，将菜单左边缘固定在距离屏幕左边缘16像素的位置
    }

    if (top < MediaQuery.of(context).padding.top + 16) {
      top = offset.dy + size.height; // 如果上方空间不足（被状态栏遮挡），将菜单移回气泡下方
    }

    await showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(color: Colors.transparent),
            ),
          ),
          Positioned(
            left: left,
            top: top,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildMenuButton(
                      icon: Icons.format_quote_rounded,
                      label: '引用',
                      onTap: () {
                        Navigator.pop(context);
                        _quoteMessage(message);
                      },
                    ),
                    _buildMenuButton(
                      icon: Icons.copy_rounded,
                      label: '复制',
                      onTap: () {
                        Navigator.pop(context);
                        Clipboard.setData(ClipboardData(text: message.content));
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
                        }
                      },
                    ),
                    if (isMe)
                      _buildMenuButton(
                        icon: Icons.delete_rounded,
                        label: '删除',
                        labelColor: Colors.red,
                        iconColor: Colors.red,
                        onTap: () async {
                          Navigator.pop(context);
                          final success = await MessageService().deleteMessage(message.id);
                          if (success && mounted) {
                            setState(() {
                              _messages.removeWhere((m) => m.id == message.id);
                            });
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('消息已删除')));
                          } else if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('删除失败，请稍后重试')));
                          }
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建菜单按钮
  Widget _buildMenuButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? labelColor,
    Color? iconColor,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        width: 56,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: iconColor ?? AppTheme.textPrimary),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: labelColor ?? AppTheme.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  /// 引用消息
  void _quoteMessage(Message message) {
    setState(() {
      _quotedMessage = message;
    });
  }

  /// 底部输入栏
  Widget _buildInputBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, -2)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_quotedMessage != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.surfaceBg,
                border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: AppTheme.headerGradient,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _quotedMessage!.senderId == _accountService.currentUser?.id
                              ? '回复你'
                              : '回复 ${widget.conversation.title}',
                          style: TextStyle(fontSize: 12, color: AppTheme.primaryColor, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _quotedMessage!.content,
                          style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    color: AppTheme.textSecondary,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      setState(() {
                        _quotedMessage = null;
                      });
                    },
                  ),
                ],
              ),
            ),
          Container(
            padding: EdgeInsets.only(left: 12, right: 12, top: 8, bottom: MediaQuery.of(context).padding.bottom + 8),
            child: Row(
              children: [
                // 语音按钮
                _buildInputAction(Icons.mic_none_rounded),
                const SizedBox(width: 4),
                // 输入框
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(color: AppTheme.surfaceBg, borderRadius: BorderRadius.circular(20)),
                    child: TextField(
                      controller: _messageController,
                      decoration: const InputDecoration(
                        hintText: '输入消息...',
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 10),
                        filled: false,
                      ),
                      style: const TextStyle(fontSize: 15),
                      maxLines: 4,
                      minLines: 1,
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // 表情按钮
                _buildInputAction(Icons.emoji_emotions_outlined),
                const SizedBox(width: 4),
                // 更多/发送按钮
                GestureDetector(
                  onTap: _sendMessage,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: AppTheme.headerGradient,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryColor.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 输入栏操作按钮
  Widget _buildInputAction(IconData icon) {
    return IconButton(
      icon: Icon(icon, color: AppTheme.textSecondary, size: 24),
      onPressed: () {},
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      padding: EdgeInsets.zero,
    );
  }

  /// 发送消息
  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final currentUser = _accountService.currentUser;
    if (currentUser == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未登录')));
      }
      return;
    }

    // conversation.id 这里我们假定，如果是从联系人详情页进来，它是对方的 receiverId；
    // 如果是从会话列表进来，它可能是 conversationId。暂时都传对方ID，具体根据后端逻辑判断。
    final messageId = await ChatService().sendPrivateMessage(
      conversationId: widget.conversation.id, // 如果后端接收0表示新会话，这里可以根据具体情况调整
      senderId: currentUser.id,
      receiverId: widget.conversation.chatUserId, // 私聊的接收者
      message: text,
      quoteId: _quotedMessage?.id,
    );

    if (messageId.isNotEmpty) {
      final now = DateTime.now();
      final convId = int.parse(widget.conversation.id);
      final senderIdInt = int.tryParse(currentUser.id) ?? 0;
      final messageIdInt = int.tryParse(messageId) ?? 0;

      // 保存消息到本地数据库
      await DatabaseService().insertMessage({
        'id': messageId,
        'conversation_id': convId,
        'conversation_type': widget.conversation.isGroup ? 2 : 1,
        'sender_id': currentUser.id,
        'quote_id': _quotedMessage != null ? (int.tryParse(_quotedMessage!.id) ?? 0) : 0,
        'content': text,
        'type': 0,
        'status': 0,
        'created_at': now.toIso8601String(),
      });

      // 更新会话表的最新消息信息和内存中的会话列表
      await ConversationService().onNewMessage(
        conversationId: convId,
        senderId: senderIdInt,
        messageId: messageIdInt,
        messageAt: now.toIso8601String(),
        messagePreview: text,
        messageType: 0,
        isInChatPage: true, // 当前在聊天页面
      );

      if (mounted) {
        setState(() {
          _messages.add(
            Message(
              id: messageId,
              senderId: currentUser.id,
              content: text,
              createdAt: now,
              isRead: true,
              quoteId: _quotedMessage?.id,
            ),
          );
          _messageController.clear();
          _quotedMessage = null;
        });

        // 滚动到底部
        Future.delayed(const Duration(milliseconds: 100), () {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('消息发送失败，请重试')));
      }
    }
  }

  /// 格式化消息时间
  String _formatMessageTime(DateTime time) {
    final now = DateTime.now();
    // 获取当前日期的0点（只保留年月日）
    final today = DateTime(now.year, now.month, now.day);
    // 获取消息日期的0点（只保留年月日）
    final messageDate = DateTime(time.year, time.month, time.day);
    // 计算日期差（负数表示消息日期早于今天）
    final dateDiff = today.difference(messageDate).inDays;
    if (dateDiff == 0) {
      return '今天 ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    } else if (dateDiff == 1) {
      return '昨天 ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    } else if (dateDiff.abs() <= 7) {
      return '${time.weekday} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    } else {
      return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
  }
}
