import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../data/mock_data.dart';
import '../../models/conversation.dart';
import '../../models/message.dart';
import '../../widgets/avatar_widget.dart';
import '../../services/account_service.dart';
import '../../services/chat_service.dart';
import '../../services/conversation_service.dart';

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

  @override
  void initState() {
    super.initState();
    _messages = [];
    _loadMessages();
  }

  /// 从服务器加载消息
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

    final response = await ConversationService().getMessages(
      widget.conversation.id,
      messageId: minMessageId,
      pageSize: 20,
    );

    if (response != null && response['success'] == true) {
      final data = response['data'];
      final list = (data['list'] as List<dynamic>?) ?? [];

      final newMessages = list.map((json) {
        return Message(
          id: json['id']?.toString() ?? '',
          senderId: json['senderId']?.toString() ?? '',
          content: json['content']?.toString() ?? '',
          type: MessageType.values.firstWhere(
            (e) => e.index == (json['type'] ?? 0),
            orElse: () => MessageType.text,
          ),
          timestamp: json['createdAt'] != null
              ? DateTime.tryParse(json['createdAt'].toString()) ??
                    DateTime.now()
              : DateTime.now(),
          isRead: true, // 默认设为已读
        );
      }).toList();

      // 对新的消息按时间升序（旧在前、新在后）确保UI表现正常
      newMessages.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      if (mounted) {
        setState(() {
          if (isLoadMore) {
            _messages.insertAll(0, newMessages);
          } else {
            _messages = newMessages;
          }
          _hasMore = data['hasMore'] == true;
          _isLoading = false;
        });

        // 如果是首次加载或者是刷新最新页，滚动到底部
        if (!isLoadMore) {
          Future.delayed(const Duration(milliseconds: 100), () {
            if (_scrollController.hasClients) {
              _scrollController.jumpTo(
                _scrollController.position.maxScrollExtent,
              );
            }
          });
        }
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
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
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white,
              size: 20,
            ),
            onPressed: () => Navigator.pop(context),
          ),
          title: Column(
            children: [
              Text(
                widget.conversation.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              if (widget.conversation.isGroup)
                Text(
                  '${widget.conversation.members.length}人',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
            ],
          ),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(
                Icons.phone_outlined,
                size: 22,
                color: Colors.white,
              ),
              onPressed: () {},
            ),
            IconButton(
              icon: const Icon(
                Icons.more_horiz_rounded,
                size: 22,
                color: Colors.white,
              ),
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
    return RefreshIndicator(
      onRefresh: () => _loadMessages(isLoadMore: true),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: _messages.length,
        itemBuilder: (context, index) {
          final message = _messages[index];
          final isMe = message.senderId == AccountService().currentUser?.id;

          // 时间分隔线
          final showTime =
              index == 0 ||
              _messages[index].timestamp
                      .difference(_messages[index - 1].timestamp)
                      .inMinutes >
                  5;

          return Column(
            children: [
              if (showTime) _buildTimeLabel(message.timestamp),
              _buildMessageBubble(message, isMe),
            ],
          );
        },
      ),
    );
  }

  /// 时间标签
  Widget _buildTimeLabel(DateTime time) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          _formatMessageTime(time),
          style: const TextStyle(fontSize: 11, color: AppTheme.textHint),
        ),
      ),
    );
  }

  /// 消息气泡
  Widget _buildMessageBubble(Message message, bool isMe) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            AvatarWidget(avatar: widget.conversation.avatar, size: 36),
            const SizedBox(width: 8),
          ],
          Flexible(
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
                    color: (isMe ? AppTheme.primaryColor : Colors.black)
                        .withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                message.content,
                style: TextStyle(
                  fontSize: 15,
                  color: isMe ? Colors.white : AppTheme.textPrimary,
                  height: 1.4,
                ),
              ),
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: 8),
            AvatarWidget(
              avatar:
                  AccountService().currentUser?.avatar ??
                  MockData.currentUser.avatar,
              size: 36,
            ),
          ],
        ],
      ),
    );
  }

  /// 底部输入栏
  Widget _buildInputBar() {
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          // 语音按钮
          _buildInputAction(Icons.mic_none_rounded),
          const SizedBox(width: 4),
          // 输入框
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: AppTheme.surfaceBg,
                borderRadius: BorderRadius.circular(20),
              ),
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
              child: const Icon(
                Icons.send_rounded,
                color: Colors.white,
                size: 20,
              ),
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

    final currentUser = AccountService().currentUser;
    if (currentUser == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('未登录')));
      }
      return;
    }

    // conversation.id 这里我们假定，如果是从联系人详情页进来，它是对方的 receiverId；
    // 如果是从会话列表进来，它可能是 conversationId。暂时都传对方ID，具体根据后端逻辑判断。
    final success = await ChatService().sendPrivateMessage(
      conversationId: widget.conversation.id, // 如果后端接收0表示新会话，这里可以根据具体情况调整
      senderId: currentUser.id,
      receiverId: widget.conversation.chatUserId, // 私聊的接收者
      message: text,
    );

    if (success) {
      if (mounted) {
        setState(() {
          _messages.add(
            Message(
              id: 'msg_new_${_messages.length}',
              senderId: currentUser.id,
              content: text,
              timestamp: DateTime.now(),
              isRead: true,
            ),
          );
          _messageController.clear();
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('消息发送失败，请重试')));
      }
    }
  }

  /// 格式化消息时间
  String _formatMessageTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
