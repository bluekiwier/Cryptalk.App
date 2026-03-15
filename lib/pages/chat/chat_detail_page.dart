import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:dio/dio.dart';
import 'dart:io';
import 'dart:convert';
import 'package:logger/logger.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_theme.dart';
import '../../models/conversation.dart';
import '../../models/message.dart';
import '../../models/send_message_result.dart';
import '../../models/db/conversation_entity.dart';
import '../../models/db/conversation_message_entity.dart';
import '../../widgets/avatar_widget.dart';
import '../../widgets/bubble_tail_painter.dart';
import '../../services/account_service.dart';
import '../../services/chat_service.dart';
import '../../services/conversation_service.dart';
import '../../services/message_service.dart';
import '../../services/database_service.dart';
import '../../services/file_service.dart';
import 'chat_settings_page.dart';

/// 聊天详情页面
/// 展示与某人或某群的具体聊天内容
class ChatDetailPage extends StatefulWidget {
  final Conversation conversation;

  const ChatDetailPage({super.key, required this.conversation});

  @override
  State<ChatDetailPage> createState() => _ChatDetailPageState();
}

const _weekDays = {1: '星期一', 2: '星期二', 3: '星期三', 4: '星期四', 5: '星期五', 6: '星期六', 7: '星期日'};

class _ChatDetailPageState extends State<ChatDetailPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late List<Message> _messages;
  bool _isLoading = false;
  bool _hasMore = true;
  Message? _quotedMessage;
  int _groupMemberCount = 0;
  String _currentTitle = '';

  final ChatService _chatService = ChatService();
  final AccountService _accountService = AccountService();
  final _logger = Logger();

  @override
  void initState() {
    super.initState();
    _messages = [];
    _currentTitle = widget.conversation.title;
    // 设置当前聊天会话ID
    _chatService.setCurrentChatConversation(widget.conversation.id);
    // 进入聊天页时清零未读数
    ConversationService().clearUnread(widget.conversation.id);
    _loadMessagesAndSync();
    // 监听WebSocket消息
    _chatService.addListener(_onChatServiceUpdated);
    // 如果是群聊，加载群成员数量
    if (widget.conversation.isGroup) {
      _loadGroupMemberCount();
      // ConversationService().enterGroup(widget.conversation.id);
    }
  }

  /// 加载群成员数量
  Future<void> _loadGroupMemberCount() async {
    final count = await ConversationService().getGroupMemberCount(widget.conversation.id);
    if (mounted) {
      setState(() {
        _groupMemberCount = count;
      });
    }
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
    // // 如果是群聊，离开群聊室
    // if (widget.conversation.isGroup) {
    //   ConversationService().exitGroup(widget.conversation.id);
    // }
    super.dispose();
  }

  /// 处理ChatService更新（收到新消息或删除消息等事件）
  void _onChatServiceUpdated() async {
    // 从ChatService获取当前会话的新消息
    final newMessages = _chatService.getMessagesForConversation(widget.conversation.id);

    // 保存到本地数据库并更新UI（无论是否有新消息，都需要更新UI以反映删除等状态变化）
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
          'sender_nickname': chatMessage.payload.senderNickname,
          'sender_avatar': chatMessage.payload.senderAvatar,
          'quote_id': quoteId,
          'content': chatMessage.payload.content,
          'type': chatMessage.payload.type,
          'status': chatMessage.payload.status,
          'created_at': chatMessage.payload.createdAt,
        });
      }
    }

    // 从数据库重新读取所有消息（包括状态变化，如删除）
    final messageMaps = await DatabaseService().getMessages(int.parse(widget.conversation.id), limit: 1000);

    final updatedMessages = messageMaps.map((map) {
      final quoteIdInt = map['quote_id'] as int?;
      final statusInt = map['status'] as int? ?? 0;
      return Message(
        id: map['id']?.toString() ?? '',
        senderId: map['sender_id']?.toString() ?? '',
        senderNickname: map['sender_nickname']?.toString(),
        senderAvatar: map['sender_avatar']?.toString(),
        content: map['content']?.toString() ?? '',
        type: MessageType.values.firstWhere((e) => e.index == (map['type'] ?? 0), orElse: () => MessageType.text),
        createdAt: map['created_at'] != null
            ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
            : DateTime.now(),
        isRead: true,
        quoteId: quoteIdInt != null && quoteIdInt > 0 ? quoteIdInt.toString() : null,
        status: MessageStatus.values.firstWhere((e) => e.index == statusInt, orElse: () => MessageStatus.normal),
      );
    }).toList();

    // 对消息按ID升序排序
    updatedMessages.sort((a, b) {
      final aId = int.tryParse(a.id) ?? 0;
      final bId = int.tryParse(b.id) ?? 0;
      return aId.compareTo(bId);
    });

    if (mounted) {
      setState(() {
        _messages = updatedMessages;
      });

      // 滚动到底部
      if (newMessages.isNotEmpty) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
          }
        });
      }

      // 更新群名称（如果有变化）
      if (widget.conversation.isGroup) {
        _updateGroupTitle();
      }
    }
  }

  /// 从数据库更新群名称
  Future<void> _updateGroupTitle() async {
    final db = await DatabaseService().database;
    final result = await db.query(
      'conversations',
      columns: ['title'],
      where: 'id = ?',
      whereArgs: [int.tryParse(widget.conversation.id) ?? 0],
    );
    if (result.isNotEmpty && mounted) {
      final newTitle = result.first['title']?.toString() ?? '';
      if (newTitle.isNotEmpty && newTitle != _currentTitle) {
        setState(() {
          _currentTitle = newTitle;
        });
      }
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
      // _logger.d('从数据库读取消息: $map');
      final quoteIdInt = map['quote_id'] as int?;
      final statusInt = map['status'] as int? ?? 0;
      return Message(
        id: map['id']?.toString() ?? '',
        senderId: map['sender_id']?.toString() ?? '',
        senderNickname: map['sender_nickname']?.toString(),
        senderAvatar: map['sender_avatar']?.toString(),
        content: map['content']?.toString() ?? '',
        type: MessageType.values.firstWhere((e) => e.index == (map['type'] ?? 0), orElse: () => MessageType.text),
        createdAt: map['created_at'] != null
            ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
            : DateTime.now(),
        isRead: true,
        quoteId: quoteIdInt != null && quoteIdInt > 0 ? quoteIdInt.toString() : null,
        status: MessageStatus.values.firstWhere((e) => e.index == statusInt, orElse: () => MessageStatus.normal),
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
          'sender_nickname': json['senderNickname'] ?? '',
          'sender_avatar': json['senderAvatar'] ?? '',
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
        final statusInt = json['status'] as int? ?? 0;
        return Message(
          id: json['id']?.toString() ?? '',
          senderId: json['senderId']?.toString() ?? '',
          senderNickname: json['senderNickname']?.toString(),
          senderAvatar: json['senderAvatar']?.toString(),
          content: json['content']?.toString() ?? '',
          type: MessageType.values.firstWhere((e) => e.index == (json['type'] ?? 0), orElse: () => MessageType.text),
          createdAt: json['createdAt'] != null
              ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
              : DateTime.now(),
          isRead: true,
          quoteId: quoteIdInt != null && quoteIdInt > 0 ? quoteIdInt.toString() : null,
          status: MessageStatus.values.firstWhere((e) => e.index == statusInt, orElse: () => MessageStatus.normal),
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

  /// 处理消息删除后的本地数据库更新（与收消息人删除逻辑保持一致）
  /// 1. 将本地数据库消息表 messages 中的对应消息的 status 设置为已删除(2)
  /// 2. 如果删除的消息是会话的最后一条消息，则更新会话表中的 last_message_id, last_message_at, last_message_preview, last_sender_id 为最新消息信息
  Future<void> _handleMessageDeleted(String messageId, String conversationId) async {
    // 解析消息ID和会话ID
    final msgId = int.tryParse(messageId) ?? 0;
    final convId = int.tryParse(conversationId) ?? 0;

    if (msgId == 0 || convId == 0) return;

    try {
      final dbService = DatabaseService();
      final db = await dbService.database;

      // 1. 将本地数据库消息表 messages 中的对应消息的 status 设置为已删除(2)
      await db.update(
        ConversationMessageEntity.tableName,
        {ConversationMessageEntity.status: 2},
        where: '${ConversationMessageEntity.id} = ?',
        whereArgs: [msgId],
      );

      // 2. 查询会话表，获取当前会话信息
      final conversationResult = await db.query(
        ConversationEntity.tableName,
        where: '${ConversationEntity.id} = ?',
        whereArgs: [convId],
      );

      // 如果会话存在
      if (conversationResult.isNotEmpty) {
        final conversation = conversationResult.first;
        final lastMessageId = conversation[ConversationEntity.lastMessageId] as int?;

        // 判断删除的消息是否为会话的最后一条消息
        if (lastMessageId == msgId) {
          // 查询该会话中未删除的最新一条消息
          final latestMessages = await db.query(
            ConversationMessageEntity.tableName,
            where: '${ConversationMessageEntity.conversationId} = ? AND ${ConversationMessageEntity.status} != 2',
            whereArgs: [convId],
            orderBy: '${ConversationMessageEntity.id} DESC',
            limit: 1,
          );

          // 如果还有未删除的消息，则更新会话的最后一条消息信息
          if (latestMessages.isNotEmpty) {
            final latestMessage = latestMessages.first;
            final newLastMessageId = latestMessage[ConversationMessageEntity.id] as int;
            final newLastMessageAt = latestMessage[ConversationMessageEntity.createdAt] as String;
            final newLastMessagePreview = _truncate(
              latestMessage[ConversationMessageEntity.content] as String? ?? '',
              50,
            );
            final newLastSenderId = latestMessage[ConversationMessageEntity.senderId] as int;

            await db.update(
              ConversationEntity.tableName,
              {
                ConversationEntity.lastMessageId: newLastMessageId,
                ConversationEntity.lastMessageAt: newLastMessageAt,
                ConversationEntity.lastMessagePreview: newLastMessagePreview,
                ConversationEntity.lastSenderId: newLastSenderId,
                ConversationEntity.updatedAt: DateTime.now().toUtc().toString(),
              },
              where: '${ConversationEntity.id} = ?',
              whereArgs: [convId],
            );
          } else {
            // 如果该会话所有消息都已删除，则将会话的最后一条消息信息置空
            await db.update(
              ConversationEntity.tableName,
              {
                ConversationEntity.lastMessageId: 0,
                ConversationEntity.lastMessageAt: '',
                ConversationEntity.lastMessagePreview: '',
                ConversationEntity.lastSenderId: 0,
                ConversationEntity.updatedAt: DateTime.now().toUtc().toString(),
              },
              where: '${ConversationEntity.id} = ?',
              whereArgs: [convId],
            );
          }
        }
      }
    } catch (e) {
      _logger.e('处理消息删除失败: $e');
    }
  }

  /// 截断字符串到指定长度，超过部分用省略号替代
  String _truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }

  /// 滚动到指定消息的位置
  Future<void> _scrollToMessage(String messageId) async {
    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index == -1) return;

    // 计算消息在列表中的位置（假设每条消息高度约为 80 像素）
    const estimatedItemHeight = 80.0;
    final targetPosition = index * estimatedItemHeight;

    // 确保滚动位置不超过最大滚动范围
    final maxScroll = _scrollController.position.maxScrollExtent;
    final finalPosition = targetPosition > maxScroll ? maxScroll : targetPosition;

    // 滚动到指定位置
    await _scrollController.animateTo(
      finalPosition,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
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
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                backgroundImage: widget.conversation.avatar.isNotEmpty
                    ? NetworkImage(widget.conversation.avatar)
                    : null,
                child: widget.conversation.avatar.isEmpty
                    ? const Icon(Icons.group, size: 20, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      _currentTitle,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.conversation.isGroup) ...[
                    const SizedBox(width: 4),
                    Text('($_groupMemberCount人)', style: TextStyle(fontSize: 20, color: Colors.white)),
                  ],
                ],
              ),
            ],
          ),
          centerTitle: true,
          actions: [
            // IconButton(
            //   icon: const Icon(Icons.phone_outlined, size: 22, color: Colors.white),
            //   onPressed: () {},
            // ),
            IconButton(
              icon: const Icon(Icons.more_horiz_rounded, size: 22, color: Colors.white),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => ChatSettingsPage(conversation: widget.conversation)),
                );
              },
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

              // 群通知消息（系统消息/加入群，退出群）居中显示
              if (widget.conversation.isGroup && message.type == MessageType.groupNotify) {
                return Column(
                  children: [if (showTime) _buildTimeLabel(message.createdAt), _buildGroupNotifyMessage(message)],
                );
              }

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

  /// 群通知消息（居中显示，灰色背景）
  Widget _buildGroupNotifyMessage(Message message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(16)),
          child: Text(message.content, style: TextStyle(fontSize: 13, color: Colors.grey[700])),
        ),
      ),
    );
  }

  /// 消息气泡
  Widget _buildMessageBubble(Message message, bool isMe) {
    if (message.status == MessageStatus.recalled) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Text(isMe ? '你撤回了一条消息' : '对方撤回了一条消息', style: TextStyle(fontSize: 12, color: AppTheme.textHint)),
        ),
      );
    }

    // 被删除的消息显示提示文案，但不隐藏消息气泡（保留引用等信息）
    final isDeleted = message.status == MessageStatus.deleted;

    final key = GlobalKey();
    final quotedMessage = message.quoteId != null
        ? _messages.firstWhere(
            (m) => m.id == message.quoteId,
            orElse: () =>
                Message(id: '', content: '', senderId: '', createdAt: DateTime.now(), status: MessageStatus.deleted),
          )
        : null;

    // 获取被引用消息的发送者昵称
    String quotedSenderName = '';
    if (quotedMessage != null && quotedMessage.id.isNotEmpty) {
      if (quotedMessage.senderId == _accountService.currentUser?.id) {
        quotedSenderName = '你';
      } else if (widget.conversation.isGroup) {
        quotedSenderName = quotedMessage.senderNickname ?? '未知用户';
      } else {
        quotedSenderName = widget.conversation.title;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe && widget.conversation.isGroup)
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onLongPress: () => _showMentionMenu(message.senderNickname ?? '未知用户'),
              child: Container(
                padding: const EdgeInsets.all(4),
                child: AvatarWidget(avatar: message.senderAvatar ?? '', size: 36, isGroup: false),
              ),
            ),
          if (!isMe && !widget.conversation.isGroup)
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onLongPress: () => _showMentionMenu(widget.conversation.title),
              child: Container(
                padding: const EdgeInsets.all(4),
                child: AvatarWidget(avatar: widget.conversation.avatar, size: 36),
              ),
            ),
          if (!isMe) const SizedBox(width: 8),
          Flexible(
            child: GestureDetector(
              key: key,
              onLongPress: () => _showMessageMenu(message, isMe, key),
              child: CustomPaint(
                painter: isMe
                    ? null
                    : BubbleTailPainter(
                        color: isDeleted ? Colors.grey[300]! : Colors.white,
                        tailDirection: TailDirection.left,
                      ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: isMe && !isDeleted ? AppTheme.headerGradient : null,
                    color: isDeleted ? Colors.grey[300] : (isMe ? null : Colors.white),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(10),
                      topRight: const Radius.circular(10),
                      bottomLeft: Radius.circular(isMe ? 10 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 10),
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
                      if (!isMe && widget.conversation.isGroup)
                        Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            message.senderNickname?.isNotEmpty == true ? message.senderNickname! : '未知用户',
                            style: TextStyle(fontSize: 12, color: AppTheme.primaryColor, fontWeight: FontWeight.w500),
                          ),
                        ),
                      if (quotedMessage != null && quotedMessage.id.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            final quotedIndex = _messages.indexWhere((m) => m.id == quotedMessage.id);
                            if (quotedIndex != -1) {
                              _scrollToMessage(quotedMessage.id);
                            }
                          },
                          child: Container(
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
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 引用消息
                                if (quotedSenderName.isNotEmpty)
                                  Text(
                                    quotedSenderName,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: (isDeleted || quotedMessage.status == MessageStatus.deleted)
                                          ? Colors.grey[400]
                                          : (isMe ? Colors.white.withValues(alpha: 0.9) : AppTheme.primaryColor),
                                    ),
                                  ),
                                if (quotedMessage.type == MessageType.image)
                                  _buildImageMessage(quotedMessage.content)
                                else if (quotedMessage.type == MessageType.file)
                                  _buildFileMessage(quotedMessage.content)
                                else
                                  Text(
                                    quotedMessage.status == MessageStatus.deleted ? '消息已被删除' : quotedMessage.content,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: (isDeleted || quotedMessage.status == MessageStatus.deleted)
                                          ? Colors.grey[350]
                                          : (isMe ? Colors.white : AppTheme.textSecondary).withValues(alpha: 0.8),
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      if (message.type == MessageType.image)
                        _buildImageMessage(message.content)
                      else if (message.type == MessageType.file)
                        _buildFileMessage(message.content)
                      else
                        Text(
                          isDeleted ? '消息已被删除' : message.content,
                          style: TextStyle(
                            fontSize: 15,
                            color: isDeleted ? Colors.grey[500] : (isMe ? Colors.white : AppTheme.textPrimary),
                            height: 1.4,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: 8),
            AvatarWidget(avatar: _accountService.currentUser?.avatar ?? '', size: 36),
          ],
        ],
      ),
    );
  }

  /// 长按消息显示操作菜单
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
    bool isMenuAbove = false;

    if (top + menuHeight > screenSize.height - inputBarHeight) {
      top = offset.dy - menuHeight - 35; // 如果下方空间不足，将菜单移至气泡上方，刚好贴近
      isMenuAbove = true;
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
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 6,
                    spreadRadius: 1,
                    offset: Offset(0, isMenuAbove ? -4 : 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildMenuButton(
                    icon: Icons.format_quote_sharp,
                    label: '引用',
                    onTap: () {
                      Navigator.pop(context);
                      _quoteMessage(message);
                    },
                  ),
                  _buildMenuButton(
                    icon: Icons.copy_sharp,
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
                      icon: Icons.delete_sharp,
                      label: '删除',
                      labelColor: Colors.red,
                      iconColor: Colors.red,
                      onTap: () async {
                        // 在异步操作前获取 ScaffoldMessenger，避免 context 跨异步 gap 使用
                        final scaffoldMessenger = ScaffoldMessenger.of(context);
                        Navigator.pop(context);
                        final success = await MessageService().deleteMessage(message.id);
                        if (success && mounted) {
                          // 异步执行本地数据库操作，与收消息人删除逻辑保持一致
                          _handleMessageDeleted(message.id, widget.conversation.id);
                          // 不从消息列表移除消息，只更新状态，这样引用该消息的消息仍然可以找到被引用的消息
                          setState(() {
                            final index = _messages.indexWhere((m) => m.id == message.id);
                            if (index != -1) {
                              _messages[index] = Message(
                                id: _messages[index].id,
                                content: _messages[index].content,
                                senderId: _messages[index].senderId,
                                type: _messages[index].type,
                                createdAt: _messages[index].createdAt,
                                isRead: _messages[index].isRead,
                                quoteId: _messages[index].quoteId,
                                status: MessageStatus.deleted,
                              );
                            }
                          });
                          scaffoldMessenger.showSnackBar(const SnackBar(content: Text('消息已删除')));
                        } else if (mounted) {
                          scaffoldMessenger.showSnackBar(const SnackBar(content: Text('删除失败，请稍后重试')));
                        }
                      },
                    ),
                ],
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        width: 50,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: iconColor ?? AppTheme.textPrimary),
            const SizedBox(height: 1),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: labelColor ?? AppTheme.textPrimary,
                fontWeight: FontWeight(500),
                decoration: TextDecoration.none,
              ),
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

  Widget _buildImageMessage(String content) {
    try {
      final data = jsonDecode(content);
      final url = data['url'] as String?;
      final width = (data['width'] as num?)?.toDouble() ?? 120;
      final height = (data['height'] as num?)?.toDouble() ?? 120;

      if (url == null) {
        return Text(content, style: TextStyle(fontSize: 13, color: Colors.grey[700]));
      }

      final displayWidth = width > 120 ? 120.0 : width;
      final displayHeight = displayWidth * height / width;

      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: GestureDetector(
          onTap: () => _showFullScreenImage(url),
          child: Image.network(
            url,
            width: displayWidth,
            height: displayHeight,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Container(
                width: displayWidth,
                height: displayHeight,
                color: Colors.grey[200],
                child: Center(
                  child: CircularProgressIndicator(
                    value: loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                        : null,
                  ),
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return Container(
                width: displayWidth,
                height: displayHeight,
                color: Colors.grey[200],
                child: const Icon(Icons.broken_image, color: Colors.grey),
              );
            },
          ),
        ),
      );
    } catch (e) {
      return Text(content, style: TextStyle(fontSize: 13, color: Colors.grey[700]));
    }
  }

  Widget _buildFileMessage(String content) {
    try {
      final data = jsonDecode(content);
      final name = data['name'] as String? ?? '未知文件';
      final size = data['size'] as int? ?? 0;
      final url = data['url'] as String?;

      if (url == null) {
        return Text(content, style: TextStyle(fontSize: 13, color: Colors.grey[700]));
      }

      return GestureDetector(
        onTap: () => _downloadFile(url, name),
        child: Container(
          width: 220,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(_getFileIconData(name), color: AppTheme.primaryColor, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(_formatFileSize(size), style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  ],
                ),
              ),
              const Icon(Icons.download, color: AppTheme.primaryColor, size: 24),
            ],
          ),
        ),
      );
    } catch (e) {
      return Text(content, style: TextStyle(fontSize: 13, color: Colors.grey[700]));
    }
  }

  IconData _getFileIconData(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    const iconMap = {
      'pdf': Icons.picture_as_pdf,
      'doc': Icons.description,
      'docx': Icons.description,
      'xls': Icons.table_chart,
      'xlsx': Icons.table_chart,
      'ppt': Icons.slideshow,
      'pptx': Icons.slideshow,
      'txt': Icons.text_snippet,
      'zip': Icons.folder_zip,
      'rar': Icons.folder_zip,
      '7z': Icons.folder_zip,
      'mp3': Icons.audio_file,
      'wav': Icons.audio_file,
      'mp4': Icons.video_file,
      'avi': Icons.video_file,
      'mov': Icons.video_file,
      'apk': Icons.android,
    };
    return iconMap[extension] ?? Icons.insert_drive_file;
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Future<void> _downloadFile(String url, String fileName) async {
    try {
      final uri = Uri.parse(url);
      final result = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!result) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('无法打开文件链接'), backgroundColor: AppTheme.badgeColor));
        }
      }
    } catch (e) {
      _logger.e('下载文件失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('下载文件失败'), backgroundColor: AppTheme.badgeColor));
      }
    }
  }

  /// 显示@提及菜单
  void _showMentionMenu(String nickname) {
    if (widget.conversation.isGroup) {
      final text = '@$nickname ';
      _messageController.text = text;
      _messageController.selection = TextSelection.fromPosition(TextPosition(offset: text.length));
      FocusScope.of(context).requestFocus(FocusNode());
    }
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
                color: AppTheme.dividerColor,
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
                // +按钮
                _buildInputAction(Icons.add, () => _showMoreOptions()),
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

  Widget _buildInputAction(IconData icon, [VoidCallback? onTap]) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 26, color: AppTheme.textSecondary),
      ),
    );
  }

  void _showMoreOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildMoreOption(Icons.image, '图片', () {
                    Navigator.pop(context);
                    _sendImage();
                  }),
                  _buildMoreOption(Icons.insert_drive_file, '文件', () {
                    Navigator.pop(context);
                    _sendFile();
                  }),
                  // _buildMoreOption(Icons.monetization_on, '红包', () {
                  //   Navigator.pop(context);
                  //   _showRedEnvelopeDialog();
                  // }),
                  // _buildMoreOption(Icons.location_on, '位置', () {
                  //   Navigator.pop(context);
                  //   _shareLocation();
                  // }),
                  // _buildMoreOption(Icons.contact_page, '名片', () {
                  //   Navigator.pop(context);
                  //   _shareContact();
                  // }),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMoreOption(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppTheme.scaffoldBg, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: AppTheme.primaryColor, size: 28),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary)),
        ],
      ),
    );
  }

  /// 发送图片
  void _sendImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null) return;

    final file = File(pickedFile.path);
    final fileSize = await file.length();
    final maxSize = 15 * 1024 * 1024;
    if (fileSize > maxSize) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('图片大小不能超过15MB')));
      }
      return;
    }

    bool? result;
    bool isOriginal = false;

    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          backgroundColor: Colors.black,
          insetPadding: EdgeInsets.zero,
          child: Container(
            width: double.infinity,
            height: double.infinity,
            color: Colors.black,
            child: Column(
              children: [
                Container(
                  height: 56,
                  color: Colors.black.withValues(alpha: 0.8),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white, size: 28),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '图片和视频',
                              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                            ),
                            SizedBox(width: 4),
                            Icon(Icons.arrow_drop_down, color: Colors.white, size: 20),
                          ],
                        ),
                      ),
                      const Spacer(),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
                Expanded(
                  child: Center(child: Image.file(file, fit: BoxFit.contain)),
                ),
                Container(
                  height: 60,
                  color: Colors.black.withValues(alpha: 0.8),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Text('预览', style: TextStyle(color: Colors.white, fontSize: 16)),
                      const Spacer(),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            isOriginal = !isOriginal;
                          });
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              value: isOriginal,
                              onChanged: (value) {
                                setState(() {
                                  isOriginal = value ?? false;
                                });
                              },
                              checkColor: Colors.white,
                              activeColor: AppTheme.primaryColor,
                              fillColor: WidgetStateProperty.resolveWith((states) {
                                if (states.contains(WidgetState.selected)) {
                                  return AppTheme.primaryColor;
                                }
                                return Colors.transparent;
                              }),
                              side: const BorderSide(color: Colors.white, width: 2),
                            ),
                            const Text('原图', style: TextStyle(color: Colors.white, fontSize: 16)),
                          ],
                        ),
                      ),
                      const Spacer(),
                      ElevatedButton(
                        onPressed: () {
                          result = true;
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        child: const Text(
                          '发送',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final currentUser = _accountService.currentUser;
    if (currentUser == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未登录')));
      }
      return;
    }

    if (result == null || !mounted) return;

    Uint8List imageBytes;
    int width = 0;
    int height = 0;

    if (!isOriginal && fileSize > 3 * 1024 * 1024) {
      // 压缩图片
      final compressed = await FlutterImageCompress.compressWithFile(
        file.absolute.path,
        quality: 80,
        minWidth: 1920,
        minHeight: 1080,
      );
      if (compressed == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('图片压缩失败')));
        }
        return;
      }
      imageBytes = compressed; // 压缩后的字节
      final decodedImage = await decodeImageFromList(imageBytes);
      width = decodedImage.width;
      height = decodedImage.height;
    } else {
      // 原图
      imageBytes = await file.readAsBytes(); // 原图的字节
      final decodedImage = await decodeImageFromList(imageBytes);
      width = decodedImage.width;
      height = decodedImage.height;
    }

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 20),
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text('正在上传图片...', style: TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );

    final fileName = pickedFile.name;
    final contentType = 'image/${fileName.split('.').last}';
    _logger.d('准备上传图片, fileName: $fileName, contentType: $contentType, imageBytes.length: ${imageBytes.length}');
    final uploadResult = await FileService().createUploadUrl(contentType, fileName, imageBytes.length, 'image');

    if (!mounted) return;
    Navigator.pop(context);

    if (uploadResult == null || !uploadResult.isSuccess) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('获取上传链接失败')));
      }
      return;
    }

    double progress = 0.0;
    void Function(VoidCallback)? setDialogState;
    bool isCancelled = false;
    CancelToken? cancelToken;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            setDialogState = setState;
            return AlertDialog(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 20),
                  CircularProgressIndicator(value: progress > 0 ? progress : null),
                  const SizedBox(height: 20),
                  const Text('正在上传图片...', style: TextStyle(fontSize: 16)),
                  const SizedBox(height: 10),
                  Text('${(progress * 100).toInt()}%', style: const TextStyle(fontSize: 14, color: Colors.grey)),
                  const SizedBox(height: 5),
                  SizedBox(width: 200, child: LinearProgressIndicator(value: progress > 0 ? progress : null)),
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: () {
                      isCancelled = true;
                      cancelToken?.cancel('用户取消上传');
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('上传已取消')));
                    },
                    child: const Text('取消上传', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    cancelToken = CancelToken();
    final uploaded = await FileService().uploadToR2(
      uploadResult.uploadUrl!,
      imageBytes,
      contentType,
      cancelToken: cancelToken,
      onProgress: (sent, total) {
        if (isCancelled) return;
        progress = sent / total;
        _logger.d('上传进度: ${(progress * 100).toInt()}%');
        setDialogState?.call(() {});
      },
    );
    _logger.d('上传图片到R2结果: $uploaded');
    if (!uploaded) {
      if (mounted && !isCancelled) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('上传图片失败'), duration: Duration(seconds: 5)));
      }
      return;
    }

    if (!mounted) return;
    Navigator.pop(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 20),
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text('正在发送消息...', style: TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );

    final imageJsonContent = jsonEncode({
      'url': uploadResult.fileUrl,
      'width': width,
      'height': height,
      'size': imageBytes.length,
    });

    SendMessageResult sendResult;
    if (widget.conversation.isGroup) {
      sendResult = await ChatService().sendGroupMessage(
        conversationId: widget.conversation.id,
        message: imageJsonContent,
        type: 1,
      );
      if (!sendResult.isSuccess && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(sendResult.message ?? '图片发送失败')));
      }
    } else {
      sendResult = await ChatService().sendPrivateMessage(
        conversationId: widget.conversation.id,
        receiverId: widget.conversation.chatUserId,
        message: imageJsonContent,
        type: 1,
      );
      if (!sendResult.isSuccess && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(sendResult.message ?? '图片发送失败')));
      }
    }

    if (sendResult.isSuccess) {
      if (mounted) {
        Navigator.pop(context);
        setState(() {
          _quotedMessage = null;
        });
      }
    }
  }

  /// 点击查看图片
  void _showFullScreenImage(String url) {
    showDialog(
      context: context,
      barrierColor: Colors.black,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) =>
                      const Center(child: Icon(Icons.broken_image, color: Colors.white, size: 50)),
                ),
              ),
            ),
            Positioned(
              top: 40,
              right: 10,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 获取文件MIME类型
  String _getMimeType(String extension) {
    const mimeTypes = {
      'pdf': 'application/pdf',
      'doc': 'application/msword',
      'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls': 'application/vnd.ms-excel',
      'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'ppt': 'application/vnd.ms-powerpoint',
      'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'txt': 'text/plain',
      'rtf': 'application/rtf',
      'zip': 'application/zip',
      'rar': 'application/vnd.rar',
      '7z': 'application/x-7z-compressed',
      'mp3': 'audio/mpeg',
      'wav': 'audio/wav',
      'mp4': 'video/mp4',
      'avi': 'video/x-msvideo',
      'mov': 'video/quicktime',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'svg': 'image/svg+xml',
    };
    return mimeTypes[extension] ?? 'application/octet-stream';
  }

  /// 发送文件
  void _sendFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.isEmpty) return;

    final file = File(result.files.first.path!);
    final fileSize = await file.length();
    final maxSize = 50 * 1024 * 1024; // 50MB限制
    if (fileSize > maxSize) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('文件大小不能超过50MB')));
      }
      return;
    }

    final currentUser = _accountService.currentUser;
    if (currentUser == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未登录')));
      }
      return;
    }

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 20),
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text('正在获取上传链接...', style: TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );

    final fileName = result.files.first.name;
    final extension = fileName.split('.').last.toLowerCase();
    final contentType = _getMimeType(extension);
    final fileBytes = await file.readAsBytes();

    _logger.d('准备上传文件, fileName: $fileName, contentType: $contentType, fileBytes.length: ${fileBytes.length}');

    final uploadResult = await FileService().createUploadUrl(contentType, fileName, fileBytes.length, 'file');

    if (!mounted) return;
    Navigator.pop(context);

    if (uploadResult == null || !uploadResult.isSuccess) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('获取上传链接失败')));
      }
      return;
    }

    double progress = 0.0;
    void Function(VoidCallback)? setDialogState;
    bool isCancelled = false;
    CancelToken? cancelToken;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            setDialogState = setState;
            return AlertDialog(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 20),
                  CircularProgressIndicator(value: progress > 0 ? progress : null),
                  const SizedBox(height: 20),
                  const Text('正在上传文件...', style: TextStyle(fontSize: 16)),
                  const SizedBox(height: 10),
                  Text('${(progress * 100).toInt()}%', style: const TextStyle(fontSize: 14, color: Colors.grey)),
                  const SizedBox(height: 5),
                  SizedBox(width: 200, child: LinearProgressIndicator(value: progress > 0 ? progress : null)),
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: () {
                      isCancelled = true;
                      cancelToken?.cancel('用户取消上传');
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('上传已取消')));
                    },
                    child: const Text('取消上传', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    cancelToken = CancelToken();
    final uploaded = await FileService().uploadToR2(
      uploadResult.uploadUrl!,
      fileBytes,
      contentType,
      cancelToken: cancelToken,
      onProgress: (sent, total) {
        if (isCancelled) return;
        progress = sent / total;
        _logger.d('上传进度: ${(progress * 100).toInt()}%');
        setDialogState?.call(() {});
      },
    );
    _logger.d('上传文件到R2结果: $uploaded');
    if (!uploaded) {
      if (mounted && !isCancelled) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('上传文件失败'), duration: Duration(seconds: 5)));
      }
      return;
    }

    if (!mounted) return;
    Navigator.pop(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 20),
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text('正在发送消息...', style: TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );

    final fileJsonContent = jsonEncode({'name': fileName, 'size': fileSize, 'url': uploadResult.fileUrl});

    SendMessageResult sendResult;
    if (widget.conversation.isGroup) {
      sendResult = await ChatService().sendGroupMessage(
        conversationId: widget.conversation.id,
        message: fileJsonContent,
        type: 4, // 文件类型
      );
      if (!sendResult.isSuccess && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(sendResult.message ?? '文件发送失败')));
      }
    } else {
      sendResult = await ChatService().sendPrivateMessage(
        conversationId: widget.conversation.id,
        receiverId: widget.conversation.chatUserId,
        message: fileJsonContent,
        type: 4, // 文件类型
      );
      if (!sendResult.isSuccess && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(sendResult.message ?? '文件发送失败')));
      }
    }

    if (sendResult.isSuccess) {
      if (mounted) {
        Navigator.pop(context);
        setState(() {
          _quotedMessage = null;
        });
      }
    }
  }

  void _showRedEnvelopeDialog() {}

  void _shareLocation() {}

  void _shareContact() {}

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

    SendMessageResult result;
    if (widget.conversation.isGroup) {
      result = await ChatService().sendGroupMessage(
        conversationId: widget.conversation.id,
        message: text,
        quoteId: _quotedMessage?.id,
      );
    } else {
      result = await ChatService().sendPrivateMessage(
        conversationId: widget.conversation.id,
        receiverId: widget.conversation.chatUserId,
        message: text,
        quoteId: _quotedMessage?.id,
      );
    }

    if (result.isSuccess) {
      if (mounted) {
        setState(() {
          _messageController.clear();
          _quotedMessage = null;
        });
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result.message ?? '消息发送失败'), backgroundColor: AppTheme.badgeColor));
      }
    }
  }

  /// 格式化消息时间
  String _formatMessageTime(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(time.year, time.month, time.day);
    final dateDiff = today.difference(messageDate).inDays;
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    final timeStr = '$hour:$minute';
    if (dateDiff == 0) {
      return '今天 $timeStr';
    } else if (dateDiff == 1) {
      return '昨天 $timeStr';
    } else if (dateDiff <= 7 && dateDiff > 0) {
      return '${_weekDays[time.weekday]} $timeStr';
    } else {
      return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} $timeStr';
    }
  }
}
