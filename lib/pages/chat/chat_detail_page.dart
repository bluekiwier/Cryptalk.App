import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
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
import '../../utils/time_util.dart';
import '../../services/voice_service.dart';
import 'chat_settings_page.dart';

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
  int _groupMemberCount = 0;
  String _currentTitle = '';

  final ChatService _chatService = ChatService();
  final AccountService _accountService = AccountService();
  final VoiceService _voiceService = VoiceService();
  final _logger = Logger();

  bool _isRecording = false;
  int _recordingSeconds = 0;
  Timer? _recordingTimer;
  String? _playingVoiceId;

  // 已读回执相关
  int _peerLastReadSeqId = 0; // 对方已读的最大序号（私聊）
  int _myLastReadSeqId = 0; // 我已读的最大序号
  int _lastMarkedReadSeqId = 0; // 最近一次通知服务端已读的序号，避免重复调用
  Timer? _readThrottleTimer; // 节流定时器
  int _currentConversationMaxSeqId = 0; // 当前会话后端最大的序号
  int _unreadCount = 0; // 仅群聊：未读消息总数

  @override
  void initState() {
    super.initState();
    _messages = [];
    _currentTitle = widget.conversation.title;

    _voiceService.onError = (message) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message.tr()), backgroundColor: AppTheme.badgeColor));
      }
    };

    _voiceService.initialize();
    // 设置当前聊天会话ID
    _chatService.setCurrentChatConversation(widget.conversation.id);
    // 进入聊天页时清零未读数
    ConversationService().clearUnread(widget.conversation.id);
    _loadMessagesAndSync();
    // 监听WebSocket消息
    _chatService.addListener(_onChatServiceUpdated);
    // 如果是群聊，加载群成员数量并检查/同步群聊密钥
    if (widget.conversation.isGroup) {
      _loadGroupMemberCount();
      _checkGroupKey();
    }

    // 监听滚动，实现已读节流更新
    _scrollController.addListener(_onScroll);
  }

  /// 滚动监听，用于更新已读状态
  void _onScroll() {
    if (_messages.isEmpty) return;

    // 如果已经在节流中，则不做处理
    if (_readThrottleTimer != null && _readThrottleTimer!.isActive) return;

    _readThrottleTimer = Timer(const Duration(seconds: 2), () {
      _updateMyReadStatus();
    });
  }

  /// 更新我的已读进度给服务端
  Future<void> _updateMyReadStatus() async {
    if (_messages.isEmpty) return;

    // 获取列表最后一项的 seqId（通常是最新的）
    // 或者根据可见区域判断（更精确，但此处先简化为最新列表序号）
    final maxSeqId = _messages.last.seqId;

    if (maxSeqId > _lastMarkedReadSeqId) {
      final success = await MessageService().markAsRead(_messages.last.id);
      if (success) {
        _lastMarkedReadSeqId = maxSeqId;
        _myLastReadSeqId = maxSeqId;
        // _logger.d('更新已读进度成功: $maxSeqId');
      }
    }
  }

  /// 检查群聊密钥，如果本地不存在则会通过接口获取并缓存
  Future<void> _checkGroupKey() async {
    try {
      await ConversationService().getGroupKeyWithVersionCheck(widget.conversation.id);
    } catch (e) {
      _logger.e('检查群聊密钥异常: $e');
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
    _recordingTimer?.cancel();
    _voiceService.stopPlay();
    _voiceService.dispose();
    // 移除监听
    _chatService.removeListener(_onChatServiceUpdated);
    // 清除当前聊天会话ID
    _chatService.setCurrentChatConversation(null);
    // // 如果是群聊，离开群聊室
    // if (widget.conversation.isGroup) {
    //   ConversationService().exitGroup(widget.conversation.id);
    // }
    _scrollController.removeListener(_onScroll);
    _readThrottleTimer?.cancel();
    super.dispose();
  }

  /// 转换 DTO 为端上 Message 模型
  Message _dtoToMessage(ChatMessageDto dto) {
    final payload = dto.payload;
    return Message(
      id: payload.id,
      senderId: payload.senderId,
      senderNickname: payload.senderNickname,
      senderAvatar: payload.senderAvatar,
      content: payload.content,
      type: MessageType.values.firstWhere((e) => e.index == payload.type, orElse: () => MessageType.text),
      createdAt: TimeUtil.parseUtcTime(payload.createdAt) ?? DateTime.now(),
      isRead: true,
      quoteId: payload.quoteId.isNotEmpty && payload.quoteId != '0' ? payload.quoteId : null,
      status: MessageStatus.values.firstWhere((e) => e.index == payload.status, orElse: () => MessageStatus.normal),
      seqId: payload.seqId,
    );
  }

  /// 滚动到列表底部
  void _scrollToBottom([bool animated = true]) {
    if (!mounted || !_scrollController.hasClients) return;

    // 延迟一帧，确保 UI 渲染完成并计算出了最新的 maxScrollExtent
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        final target = _scrollController.position.maxScrollExtent;
        if (animated) {
          _scrollController.animateTo(target, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
        } else {
          _scrollController.jumpTo(target);
        }
      }
    });
  }

  /// 处理ChatService更新（收到新消息或删除消息等事件）
  void _onChatServiceUpdated() async {
    if (!mounted) return;
    _logger.d('收到 ChatService 更新通知');

    // 1. 获取最新的对方已读序号并更新 UI
    final conversationId = widget.conversation.id;
    final newPeerReadSeqId = _chatService.getPeerLastReadSeqId(conversationId);
    if (newPeerReadSeqId > _peerLastReadSeqId) {
      if (mounted) {
        setState(() {
          _peerLastReadSeqId = newPeerReadSeqId;
        });
      }
    }

    // 2. 从ChatService获取当前会话的新消息（内存缓存）
    final incomingDtos = _chatService.getMessagesForConversation(conversationId);

    // 3. 如果没有内存中的新消息（可能是由于删除/撤回导致的逻辑更新）
    // 或者目前列表为空，保守起见全量刷新一次
    if (incomingDtos.isEmpty || _messages.isEmpty) {
      await _loadMessages();
      return;
    }

    _logger.d('增量处理新消息数量: ${incomingDtos.length}');

    // 4. 增量更新 UI
    setState(() {
      for (final dto in incomingDtos) {
        final msgId = dto.payload.id;
        final existingIndex = _messages.indexWhere((m) => m.id == msgId);

        if (existingIndex == -1) {
          // 不存在：直接添加
          _messages.add(_dtoToMessage(dto));
        } else {
          // 已存在：可能状态变了（例如变为撤回状态），更新之
          _messages[existingIndex] = _dtoToMessage(dto);
        }
      }

      // 4. 按 seqId 排序（保证乱序到达的消息顺序正确）
      _messages.sort((a, b) => a.seqId.compareTo(b.seqId));
    });

    // 5. 滑动到底部
    _scrollToBottom(true);

    // 6. 已消费的消息清理，防止下次 notifyListeners 再次循环处理
    _chatService.clearMessagesForConversation(conversationId);

    // 7. 更新群组标题（如果需要）
    if (widget.conversation.isGroup) {
      _updateGroupTitle();
    }
  }

  /// 从数据库更新群名称
  Future<void> _updateGroupTitle() async {
    final db = await DatabaseService().database;
    final result = await db.query(
      ConversationEntity.tableName,
      columns: ['title'],
      where: 'id = ?',
      whereArgs: [widget.conversation.id],
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

    String? minMessageId;
    if (isLoadMore && _messages.isNotEmpty) {
      // 找出当前列表中最早（第一个）的消息ID作为翻页依据（按 seqId 排序，旧在前新在后，所以第一条是最旧的）
      // 注意：这里的 getLocalMessages 实现是查询 id < minMessageId，这在 ID 是递增的情况下才有效
      // 如果 ID 不是递增的，建议使用 seqId 或 createdAt 作为游标
      minMessageId = _messages.first.id;
    }

    final messageMaps = await DatabaseService().getLocalMessages(
      widget.conversation.id,
      limit: 20,
      minMessageId: minMessageId,
    );

    final newMessages = messageMaps.map((map) {
      // _logger.d('从数据库读取消息: $map');
      final statusInt = map['status'] as int? ?? 0;
      final isReadInt = map['is_read'] as int? ?? 1;
      final seqId = map['seq_id'] as int? ?? 0;
      return Message(
        id: map['id']?.toString() ?? '',
        senderId: map['sender_id']?.toString() ?? '',
        senderNickname: map['sender_nickname']?.toString(),
        senderAvatar: map['sender_avatar']?.toString(),
        content: map['content']?.toString() ?? '',
        type: MessageType.values.firstWhere((e) => e.index == (map['type'] ?? 0), orElse: () => MessageType.text),
        createdAt: TimeUtil.parseUtcTime(map['created_at']?.toString()),
        isRead: isReadInt == 1,
        quoteId: map['quote_id']?.toString(),
        status: MessageStatus.values.firstWhere((e) => e.index == statusInt, orElse: () => MessageStatus.normal),
        seqId: seqId,
      );
    }).toList();

    // 按seqId升序排序（旧在前、新在后）
    newMessages.sort((a, b) => a.seqId.compareTo(b.seqId));

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
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted && _scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    }
  }

  /// 后台非阻塞同步最新消息
  Future<void> _syncLatestMessages() async {
    // 获取本地最新消息序列ID
    int latestSeqId = 0;
    if (_messages.isNotEmpty) {
      // 检查序列ID是否为数字格式
      final numericSeqIds = _messages.map((m) => m.seqId).where((id) => id > 0).toList();

      if (numericSeqIds.isNotEmpty) {
        latestSeqId = numericSeqIds.reduce((a, b) => a > b ? a : b);
      }
    }

    // 从服务器同步最新消息
    final response = await ConversationService().getMessages(widget.conversation.id, seqId: latestSeqId, pageSize: 30);

    // 检查是否有网络超时错误
    if (response != null && response['success'] == false && response['error'] == 'connection_timeout') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response['message'].tr() ?? '网络连接超时，请检查网络后重试'.tr()),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    if (response != null && response['success'] == true) {
      final data = response['data'];
      final list = (data['list'] as List<dynamic>?) ?? [];

      // 将消息转换为数据库格式并存储
      final messageRows = list.map((json) {
        // _logger.d('从服务器同步消息: $json');
        return {
          'id': json['id']?.toString() ?? '',
          'conversation_id': widget.conversation.id,
          'conversation_type': widget.conversation.isGroup ? 2 : 1,
          'sender_id': json['senderId']?.toString() ?? '',
          'sender_nickname': json['senderNickname'] ?? '',
          'sender_avatar': json['senderAvatar'] ?? '',
          'quote_id': json['quoteId']?.toString() ?? '',
          'content': json['content'],
          'type': json['type'] ?? 0,
          'status': json['status'] ?? 0,
          'is_read': 0,
          'seq_id': int.tryParse(json['seqId']?.toString() ?? '0') ?? 0,
          'created_at': json['createdAt'],
        };
      }).toList();

      // 批量插入到本地数据库
      await DatabaseService().insertMessages(messageRows);

      final newMessages = list.map((json) {
        final statusInt = json['status'] as int? ?? 0;
        return Message(
          id: json['id']?.toString() ?? '',
          senderId: json['senderId']?.toString() ?? '',
          senderNickname: json['senderNickname']?.toString(),
          senderAvatar: json['senderAvatar']?.toString(),
          content: json['content']?.toString() ?? '',
          type: MessageType.values.firstWhere((e) => e.index == (json['type'] ?? 0), orElse: () => MessageType.text),
          createdAt: TimeUtil.parseUtcTime(json['createdAt']?.toString()),
          isRead: true,
          quoteId: json['quoteId']?.toString() ?? '',
          status: MessageStatus.values.firstWhere((e) => e.index == statusInt, orElse: () => MessageStatus.normal),
          seqId: int.tryParse(json['seqId']?.toString() ?? '0') ?? 0,
        );
      }).toList();

      // 对新的消息按seqId升序排序（旧在前、新在后）确保 UI 表现正常
      newMessages.sort((a, b) => a.seqId.compareTo(b.seqId));

      if (mounted) {
        setState(() {
          // 更新对方已读进度（私聊）
          final extra = data['extra'];
          if (extra != null) {
            final type = extra['type'] as int?; // 1-私聊 2-群聊
            _currentConversationMaxSeqId = extra['lastSeqId'] as int? ?? 0;
            _myLastReadSeqId = extra['myLastReadSeqId'] as int? ?? 0;

            if (type == 1 && extra['peerLastReadSeqId'] != null) {
              _peerLastReadSeqId = extra['peerLastReadSeqId'] as int? ?? 0;
              // 同步给 ChatService 缓存
              _chatService.updatePeerLastReadSeqId(widget.conversation.id, _peerLastReadSeqId);
            }

            if (type == 2) {
              _unreadCount = extra['unreadCount'] as int? ?? 0;
            }

            _logger.d(
              '同步会话状态: 会话最大Seq=$_currentConversationMaxSeqId, 我已读Seq=$_myLastReadSeqId, 对方已读Seq=$_peerLastReadSeqId',
            );

            // 如果我是首次进入，且当前列表已经有消息，尝试标记一次已读
            if (_messages.isNotEmpty && _lastMarkedReadSeqId == 0) {
              _updateMyReadStatus();
            }
          }

          // 去重合并新消息
          for (final message in newMessages) {
            if (!_messages.any((m) => m.id == message.id)) {
              _messages.add(message);
            }
          }
          // 重新排序所有消息（按seqId排序）
          _messages.sort((a, b) => a.seqId.compareTo(b.seqId));
        });
      }
    }
  }

  /// 处理消息删除后的本地数据库更新（与收消息人删除逻辑保持一致）
  /// 1. 将本地数据库消息表 messages 中的对应消息的 status 设置为已删除(2)
  /// 2. 如果删除的消息是会话的最后一条消息，则更新会话表中的 last_message_id, last_message_at, last_message_preview, last_sender_id 为最新消息信息
  Future<void> _handleMessageDeleted(String messageId, String conversationId) async {
    if (messageId.isEmpty || conversationId.isEmpty) return;

    try {
      final dbService = DatabaseService();
      final db = await dbService.database;

      // 1. 将本地数据库消息表 messages 中的对应消息的 status 设置为已删除(2)
      await db.update(
        ConversationMessageEntity.tableName,
        {ConversationMessageEntity.status: 2},
        where: '${ConversationMessageEntity.id} = ?',
        whereArgs: [messageId],
      );

      // 2. 查询会话表，获取当前会话信息
      final conversationResult = await db.query(
        ConversationEntity.tableName,
        where: '${ConversationEntity.id} = ?',
        whereArgs: [conversationId],
      );

      // 如果会话存在
      if (conversationResult.isNotEmpty) {
        final conversation = conversationResult.first;
        final lastMessageId = conversation[ConversationEntity.lastMessageId] as String?;

        // 判断删除的消息是否为会话的最后一条消息
        if (lastMessageId == messageId) {
          // 查询该会话中未删除的最新一条消息
          final latestMessages = await db.query(
            ConversationMessageEntity.tableName,
            where: '${ConversationMessageEntity.conversationId} = ? AND ${ConversationMessageEntity.status} != 2',
            whereArgs: [conversationId],
            orderBy: '${ConversationMessageEntity.id} DESC',
            limit: 1,
          );

          // 如果还有未删除的消息，则更新会话的最后一条消息信息
          if (latestMessages.isNotEmpty) {
            final latestMessage = latestMessages.first;
            final newLastMessageId = latestMessage[ConversationMessageEntity.id] as String;
            final newLastMessageAt = latestMessage[ConversationMessageEntity.createdAt] as String;
            final newLastMessagePreview = _truncate(
              latestMessage[ConversationMessageEntity.content] as String? ?? '',
              50,
            );
            final newLastSenderId = latestMessage[ConversationMessageEntity.senderId] as String;

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
              whereArgs: [conversationId],
            );
          } else {
            // 如果该会话所有消息都已删除，则将会话的最后一条消息信息置空
            await db.update(
              ConversationEntity.tableName,
              {
                ConversationEntity.lastMessageId: '',
                ConversationEntity.lastMessageAt: '',
                ConversationEntity.lastMessagePreview: '',
                ConversationEntity.lastSenderId: '',
                ConversationEntity.updatedAt: DateTime.now().toUtc().toString(),
              },
              where: '${ConversationEntity.id} = ?',
              whereArgs: [conversationId],
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          // 顶部显示未读消息提醒（仅群聊且未读数大于0时）
          if (widget.conversation.isGroup && _unreadCount > 0)
            GestureDetector(
              onTap: () {
                // 跳转到第一条未读消息或清空未读
                setState(() => _unreadCount = 0);
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                color: AppTheme.badgeColor.withValues(alpha: 0.1),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: AppTheme.badgeColor),
                    const SizedBox(width: 8),
                    Text(
                      '有 $_unreadCount 条新消息',
                      style: TextStyle(color: AppTheme.badgeColor, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                    const Spacer(),
                    Icon(Icons.close, size: 16, color: AppTheme.badgeColor),
                  ],
                ),
              ),
            ),
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
        decoration: AppTheme.getAppBarDecoration(context),
        child: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: (Theme.of(context).appBarTheme.foregroundColor ?? Colors.white).withValues(alpha: 0.2),
                backgroundImage: widget.conversation.avatar.isNotEmpty
                    ? NetworkImage(widget.conversation.avatar)
                    : null,
                child: widget.conversation.avatar.isEmpty ? Icon(Icons.group, size: 20, color: Colors.white) : null,
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      _currentTitle,
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
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
            //   icon: Icon(Icons.phone_outlined, size: 22, color: Theme.of(context).appBarTheme.foregroundColor ?? Colors.white),
            //   onPressed: () {},
            // ),
            IconButton(
              icon: Icon(Icons.more_horiz_rounded, size: 22, color: Colors.white),
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
                  index == 0 ||
                  (_messages[index].createdAt ?? DateTime.now())
                          .difference(_messages[index - 1].createdAt ?? DateTime.now())
                          .inMinutes >
                      1;

              // 群通知消息（系统消息/加入群，退出群）居中显示
              if (widget.conversation.isGroup && message.type == MessageType.groupNotify) {
                return Column(
                  children: [
                    if (showTime) _buildTimeLabel(message.createdAt ?? DateTime.now()),
                    _buildGroupNotifyMessage(message),
                  ],
                );
              }

              return Column(
                children: [
                  if (showTime) _buildTimeLabel(message.createdAt ?? DateTime.now()),
                  _buildMessageBubble(message, isMe),
                ],
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
        child: Text(
          TimeUtil.formatMessageTime(time.toLocal()),
          style: const TextStyle(fontSize: 11, color: AppTheme.textHint),
        ),
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
    // 图片消息不需要背景色，其他消息类型需要背景色
    final hasBackground = message.type != MessageType.image;

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
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 对方消息显示头像（群聊和单聊）
          if (!isMe)
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onLongPress: () => _showMentionMenu(
                widget.conversation.isGroup ? (message.senderNickname ?? '未知用户'.tr()) : widget.conversation.title,
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(0, 0, 4, 4),
                child: AvatarWidget(
                  avatar: widget.conversation.isGroup ? (message.senderAvatar ?? '') : widget.conversation.avatar,
                  size: 36,
                ),
              ),
            ),
          if (!isMe) const SizedBox(width: 8),
          // 消息内容区域
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 群聊时显示发送者昵称，放在气泡顶部
                if (!isMe && widget.conversation.isGroup)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      message.senderNickname?.isNotEmpty == true ? message.senderNickname! : '未知用户'.tr(),
                      style: TextStyle(fontSize: 12, color: AppTheme.primaryColor, fontWeight: FontWeight.w500),
                    ),
                  ),
                // 消息气泡
                GestureDetector(
                  key: key,
                  onLongPress: () => _showMessageMenu(message, isMe, key),
                  child: CustomPaint(
                    painter: (!isMe && hasBackground && !isDeleted)
                        ? BubbleTailPainter(color: Colors.white, tailDirection: TailDirection.left)
                        : null,
                    child: Container(
                      padding: hasBackground
                          ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8)
                          : EdgeInsets.zero,
                      decoration: hasBackground
                          ? BoxDecoration(
                              gradient: isMe && !isDeleted ? AppTheme.headerGradient : null,
                              color: isDeleted ? Colors.grey[300] : (isMe ? null : Colors.white),
                              borderRadius: BorderRadius.all(Radius.circular(6)), // 消息气泡圆角
                              boxShadow: [
                                BoxShadow(
                                  color: (isMe ? AppTheme.primaryColor : Colors.black).withValues(alpha: 0.06),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            )
                          : null,
                      child: Column(
                        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
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
                                      _buildImageMessage(
                                        quotedMessage.content,
                                        isDeleted: quotedMessage.status == MessageStatus.deleted,
                                      )
                                    else if (quotedMessage.type == MessageType.file)
                                      _buildFileMessage(
                                        quotedMessage.content,
                                        isMe: isMe,
                                        isDeleted: quotedMessage.status == MessageStatus.deleted,
                                      )
                                    else
                                      Text(
                                        quotedMessage.status == MessageStatus.deleted
                                            ? '消息已被删除'.tr()
                                            : quotedMessage.content,
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
                            _buildImageMessage(message.content, isDeleted: isDeleted)
                          else if (message.type == MessageType.file)
                            _buildFileMessage(message.content, isMe: isMe, isDeleted: isDeleted)
                          else if (message.type == MessageType.audio)
                            _buildVoiceMessage(message, isMe, isDeleted: isDeleted)
                          else
                            Text(
                              isDeleted ? '消息已被删除'.tr() : message.content,
                              style: TextStyle(
                                fontSize: 15,
                                color: isDeleted ? Colors.grey[500] : (isMe ? Colors.white : AppTheme.textPrimary),
                                height: 1.4,
                              ),
                            ),
                          // 显示已读回执（仅限自己发送的消息且非群聊且非删除消息）
                          if (isMe && !isDeleted && !widget.conversation.isGroup)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Icon(
                                message.seqId <= _peerLastReadSeqId ? Icons.done_all_rounded : Icons.done_rounded,
                                size: 14,
                                color: message.seqId <= _peerLastReadSeqId
                                    ? Colors.white.withValues(alpha: 0.9)
                                    : Colors.white.withValues(alpha: 0.6),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 自己消息显示头像
          if (isMe) const SizedBox(width: 8),
          if (isMe)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 0, 4),
              child: AvatarWidget(avatar: _accountService.currentUser?.avatar ?? '', size: 36),
            ),
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
                    label: '引用'.tr(),
                    onTap: () {
                      Navigator.pop(context);
                      _quoteMessage(message);
                    },
                  ),
                  _buildMenuButton(
                    icon: Icons.copy_sharp,
                    label: '复制'.tr(),
                    onTap: () {
                      Navigator.pop(context);
                      Clipboard.setData(ClipboardData(text: message.content));
                      if (mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text('已复制到剪贴板'.tr()), backgroundColor: AppTheme.onlineColor));
                      }
                    },
                  ),
                  if (isMe)
                    _buildMenuButton(
                      icon: Icons.delete_sharp,
                      label: '删除'.tr(),
                      labelColor: Colors.red,
                      iconColor: Colors.red,
                      onTap: () async {
                        // 在异步操作前获取 ScaffoldMessenger，避免 context 跨异步 gap 使用
                        final scaffoldMessenger = ScaffoldMessenger.of(context);
                        Navigator.pop(context);
                        final success = await MessageService().delete(message.id);
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
                          scaffoldMessenger.showSnackBar(SnackBar(content: Text('消息已删除'.tr())));
                        } else if (mounted) {
                          scaffoldMessenger.showSnackBar(SnackBar(content: Text('删除失败，请稍后重试'.tr())));
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

  /// 获取引用消息的发送者名称
  String _getQuotedSenderName(Message message) {
    if (message.senderId == _accountService.currentUser?.id) {
      return '你'.tr();
    } else if (widget.conversation.isGroup) {
      return message.senderNickname?.isNotEmpty == true ? message.senderNickname! : '未知用户'.tr();
    } else {
      return widget.conversation.title;
    }
  }

  /// 获取引用消息的内容显示文本
  String _getQuotedContentDisplay(Message message) {
    if (message.status == MessageStatus.deleted) {
      return '消息已被删除'.tr();
    }

    switch (message.type) {
      case MessageType.audio:
        return '[语音]'.tr();
      case MessageType.image:
        return '[图片]'.tr();
      case MessageType.file:
        return '[文件]'.tr();
      case MessageType.groupNotify:
        return '[群通知]'.tr();
      default:
        return message.content;
    }
  }

  /// 构建图片消息样式
  Widget _buildImageMessage(String content, {bool isDeleted = false}) {
    if (isDeleted) {
      return Text('消息已被删除'.tr(), style: TextStyle(fontSize: 15, color: Colors.grey[500]));
    }

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

  /// 构建文件消息样式
  Widget _buildFileMessage(String content, {bool isMe = false, bool isDeleted = false}) {
    if (isDeleted) {
      return Text('消息已被删除'.tr(), style: TextStyle(fontSize: 15, color: Colors.grey[500]));
    }

    try {
      final data = jsonDecode(content);
      final name = data['name'] as String? ?? '未知文件'.tr();
      final size = data['size'] as int? ?? 0;
      final url = data['url'] as String?;

      if (url == null) {
        return Text(content, style: TextStyle(fontSize: 13, color: Colors.grey[700]));
      }

      // 根据发送方/接收方设置不同的颜色
      final iconColor = isMe ? Colors.white : AppTheme.primaryColor;
      final textColor = isMe ? Colors.white : AppTheme.textPrimary;
      final subtextColor = isMe ? Colors.white.withValues(alpha: 0.7) : AppTheme.textSecondary;
      final iconBgColor = isMe ? Colors.white.withValues(alpha: 0.2) : AppTheme.primaryColor.withValues(alpha: 0.1);

      return GestureDetector(
        onTap: () => _downloadFile(url, name),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 220),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: iconBgColor, borderRadius: BorderRadius.circular(8)),
                child: Icon(_getFileIconData(name), color: iconColor, size: 24),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: textColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(_formatFileSize(size), style: TextStyle(fontSize: 12, color: subtextColor)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: iconBgColor, borderRadius: BorderRadius.circular(16)),
                child: Icon(Icons.download, color: iconColor, size: 20),
              ),
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
      'm4a': Icons.video_file,
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

  /// 构建语音消息样式
  Widget _buildVoiceMessage(Message message, bool isMe, {bool isDeleted = false}) {
    if (isDeleted) {
      return Text('消息已被删除'.tr(), style: TextStyle(fontSize: 15, color: Colors.grey[500]));
    }

    try {
      final data = jsonDecode(message.content);
      final url = data['url'] as String?;
      final duration = data['duration'] as int? ?? 0;
      final isPlaying = _playingVoiceId == message.id;

      if (url == null) {
        return Text(message.content, style: TextStyle(fontSize: 13, color: Colors.grey[700]));
      }

      // 计算语音消息宽度：最小 100，最大 300，根据时长比例计算
      // 60 秒对应最大宽度 300，5 秒对应最小宽度 100
      final minWidth = 60.0;
      final maxWidth = 240.0;
      final maxDuration = 60;
      final voiceWidth = minWidth + (maxWidth - minWidth) * (duration / maxDuration);

      return GestureDetector(
        onTap: () => _toggleVoicePlay(message, url),
        child: Container(
          width: voiceWidth,
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          child: Row(
            mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              if (!isMe)
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(isPlaying ? Icons.pause : Icons.play_arrow, color: AppTheme.primaryColor, size: 18),
                ),
              if (!isMe) const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$duration \'\'',
                  style: TextStyle(fontSize: 14, color: isMe ? Colors.white : AppTheme.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isMe) const SizedBox(width: 8),
              if (isMe)
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 18),
                ),
              if (!message.isRead && !isMe)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(left: 8),
                  decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                ),
            ],
          ),
        ),
      );
    } catch (e) {
      return Text(message.content, style: TextStyle(fontSize: 13, color: Colors.grey[700]));
    }
  }

  void _toggleVoicePlay(Message message, String url) async {
    final messageId = message.id;
    if (messageId.isNotEmpty && !message.isRead) {
      await DatabaseService().markMessageAsRead(messageId);
      if (mounted) {
        setState(() {
          final index = _messages.indexWhere((m) => m.id == message.id);
          if (index != -1) {
            _messages[index] = Message(
              id: message.id,
              content: message.content,
              senderId: message.senderId,
              senderNickname: message.senderNickname,
              senderAvatar: message.senderAvatar,
              type: message.type,
              createdAt: message.createdAt,
              isRead: true,
              quoteId: message.quoteId,
              status: message.status,
              seqId: message.seqId,
            );
          }
        });
      }
    }

    // 如果正在播放同一条语音，则停止播放
    if (_playingVoiceId == message.id) {
      await _voiceService.stopPlay();
      if (mounted) {
        setState(() {
          _playingVoiceId = null;
        });
      }
    } else {
      // 停止当前正在播放的语音
      if (_playingVoiceId != null) {
        await _voiceService.stopPlay();
      }
      // 开始播放新的语音
      if (mounted) {
        setState(() {
          _playingVoiceId = message.id;
        });
      }
      await _voiceService.playVoice(
        url,
        onComplete: () {
          if (mounted) {
            setState(() {
              _playingVoiceId = null;
            });
          }
        },
      );
    }
  }

  Future<void> _downloadFile(String url, String fileName) async {
    try {
      final uri = Uri.parse(url);
      final result = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!result) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('无法打开文件链接'.tr()), backgroundColor: AppTheme.badgeColor));
        }
      }
    } catch (e) {
      _logger.e('下载文件失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('下载文件失败'.tr()), backgroundColor: AppTheme.badgeColor));
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
        color: Theme.of(context).cardColor,
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
                              ? '回复你'.tr()
                              : '回复 ${_getQuotedSenderName(_quotedMessage!)}',
                          style: TextStyle(fontSize: 12, color: AppTheme.primaryColor, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _getQuotedContentDisplay(_quotedMessage!),
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
          if (_isRecording)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.mic, color: Colors.red, size: 28),
                  const SizedBox(width: 12),
                  Text(
                    '$_recordingSeconds'
                    '',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.red),
                  ),
                  const SizedBox(width: 20),
                  Text('松开发送，上滑取消'.tr(), style: TextStyle(fontSize: 14, color: Colors.grey)),
                ],
              ),
            ),
          Container(
            padding: EdgeInsets.only(left: 12, right: 12, top: 8, bottom: MediaQuery.of(context).padding.bottom + 8),
            child: Row(
              children: [
                // 语音按钮
                Listener(
                  onPointerDown: (_) {
                    _logger.d('语音按钮: 按下');
                    _startRecording();
                  },
                  onPointerUp: (_) {
                    _logger.d('语音按钮: 松开');
                    _stopRecording();
                  },
                  onPointerCancel: (_) {
                    _logger.d('语音按钮: 取消');
                    _cancelRecording();
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      _isRecording ? Icons.mic : Icons.mic_none_rounded,
                      size: 26,
                      color: _isRecording ? Colors.red : AppTheme.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // 输入框
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(color: AppTheme.surfaceBg, borderRadius: BorderRadius.circular(20)),
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        hintText: '输入消息...'.tr(),
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
                  _buildMoreOption(Icons.image, '图片'.tr(), () {
                    Navigator.pop(context);
                    _sendImage();
                  }),
                  _buildMoreOption(Icons.insert_drive_file, '文件'.tr(), () {
                    Navigator.pop(context);
                    _sendFile();
                  }),
                  // _buildMoreOption(Icons.monetization_on, '红包'.tr(), () {
                  //   Navigator.pop(context);
                  //   _showRedEnvelopeDialog();
                  // }),
                  // _buildMoreOption(Icons.location_on, '位置'.tr(), () {
                  //   Navigator.pop(context);
                  //   _shareLocation();
                  // }),
                  // _buildMoreOption(Icons.contact_page, '名片'.tr(), () {
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('图片大小不能超过15MB'.tr())));
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
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '图片和视频'.tr(),
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
                      Text('预览'.tr(), style: TextStyle(color: Colors.white, fontSize: 16)),
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
                            Text('原图'.tr(), style: TextStyle(color: Colors.white, fontSize: 16)),
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
                        child: Text(
                          '发送'.tr(),
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('未登录'.tr())));
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
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('图片压缩失败'.tr())));
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
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 20),
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text('正在上传图片...'.tr(), style: TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );

    final fileName = pickedFile.name;
    final contentType = 'image/${fileName.split('.').last}';
    final uploadResult = await FileService().createUploadUrl(contentType, fileName, imageBytes.length, 'image');

    if (!mounted) return;
    Navigator.pop(context);

    if (uploadResult == null || !uploadResult.isSuccess) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('获取上传链接失败'.tr())));
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
                  Text('正在上传图片...'.tr(), style: TextStyle(fontSize: 16)),
                  const SizedBox(height: 10),
                  Text('${(progress * 100).toInt()}%', style: const TextStyle(fontSize: 14, color: Colors.grey)),
                  const SizedBox(height: 5),
                  SizedBox(width: 200, child: LinearProgressIndicator(value: progress > 0 ? progress : null)),
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: () {
                      isCancelled = true;
                      cancelToken?.cancel('用户取消上传'.tr());
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('上传已取消'.tr())));
                    },
                    child: Text('取消上传'.tr(), style: TextStyle(color: Colors.red)),
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
        ).showSnackBar(SnackBar(content: Text('上传图片失败'.tr()), duration: Duration(seconds: 5)));
      }
      return;
    }

    if (!mounted) return;
    Navigator.pop(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 20),
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text('正在发送消息...'.tr(), style: TextStyle(fontSize: 16)),
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(sendResult.message ?? '图片发送失败'.tr())));
      }
    } else {
      sendResult = await ChatService().sendPrivateMessage(
        conversationId: widget.conversation.id,
        receiverId: widget.conversation.chatUserId,
        message: imageJsonContent,
        type: 1,
      );
      if (!sendResult.isSuccess && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(sendResult.message ?? '图片发送失败'.tr())));
      }
    }

    if (sendResult.isSuccess && sendResult.messageData != null) {
      // 使用服务端返回的完整消息数据插入到本地数据库
      final messageData = sendResult.messageData!;
      _logger.d('发送图片成功，服务端返回的数据: $messageData');
      final currentUser = _accountService.currentUser;
      if (currentUser != null) {
        final messageType = messageData['type'] as int? ?? 1;
        await DatabaseService().insertMessage({
          'id': messageData['id']?.toString() ?? '',
          'conversation_id': widget.conversation.id,
          'conversation_type': widget.conversation.isGroup ? 2 : 1,
          'sender_id': messageData['senderId']?.toString() ?? currentUser.id,
          'sender_nickname': messageData['senderNickname'] ?? currentUser.nickname,
          'sender_avatar': messageData['senderAvatar'] ?? currentUser.avatar,
          'quote_id': messageData['quoteId']?.toString() ?? '',
          'content': messageData['content'] ?? imageJsonContent,
          'type': messageType,
          'status': messageData['status'] ?? 0,
          'seq_id': int.tryParse(messageData['seqId']?.toString() ?? '0') ?? 0,
          'created_at': messageData['createdAt'] ?? DateTime.now().toUtc().toIso8601String(),
        });

        // 更新会话的最后一条消息信息
        await ConversationService().updateConversationAfterSendMessage(
          conversationId: widget.conversation.id,
          senderId: messageData['senderId']?.toString() ?? currentUser.id,
          messageId: messageData['id']?.toString() ?? '0',
          messageAt: messageData['createdAt'] ?? DateTime.now().toUtc().toIso8601String(),
          messagePreview: '[图片]',
          messageType: 1,
        );

        // 重新加载消息并更新 UI
        if (mounted) {
          await _loadMessagesAndSync();
        }
      }

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
      'm4a': 'video/mp4',
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('文件大小不能超过50MB'.tr())));
      }
      return;
    }

    final currentUser = _accountService.currentUser;
    if (currentUser == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('未登录'.tr())));
      }
      return;
    }

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 20),
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text('正在获取上传链接...'.tr(), style: TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );

    final fileName = result.files.first.name;
    final extension = fileName.split('.').last.toLowerCase();
    final contentType = _getMimeType(extension);
    final fileBytes = await file.readAsBytes();
    final uploadResult = await FileService().createUploadUrl(contentType, fileName, fileBytes.length, 'file');

    if (!mounted) return;
    Navigator.pop(context);

    if (uploadResult == null || !uploadResult.isSuccess) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('获取上传链接失败'.tr())));
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
                  Text('正在上传文件...'.tr(), style: TextStyle(fontSize: 16)),
                  const SizedBox(height: 10),
                  Text('${(progress * 100).toInt()}%', style: const TextStyle(fontSize: 14, color: Colors.grey)),
                  const SizedBox(height: 5),
                  SizedBox(width: 200, child: LinearProgressIndicator(value: progress > 0 ? progress : null)),
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: () {
                      isCancelled = true;
                      cancelToken?.cancel('用户取消上传'.tr());
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('上传已取消'.tr())));
                    },
                    child: Text('取消上传'.tr(), style: TextStyle(color: Colors.red)),
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
        ).showSnackBar(SnackBar(content: Text('上传文件失败'.tr()), duration: Duration(seconds: 5)));
      }
      return;
    }

    if (!mounted) return;
    Navigator.pop(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 20),
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text('正在发送消息...'.tr(), style: TextStyle(fontSize: 16)),
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(sendResult.message ?? '文件发送失败'.tr())));
      }
    } else {
      sendResult = await ChatService().sendPrivateMessage(
        conversationId: widget.conversation.id,
        receiverId: widget.conversation.chatUserId,
        message: fileJsonContent,
        type: 4, // 文件类型
      );
      if (!sendResult.isSuccess && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(sendResult.message ?? '文件发送失败'.tr())));
      }
    }

    if (sendResult.isSuccess && sendResult.messageData != null) {
      // 使用服务端返回的完整消息数据插入到本地数据库
      final messageData = sendResult.messageData!;
      final currentUser = _accountService.currentUser;
      if (currentUser != null) {
        final messageType = messageData['type'] as int? ?? 4;
        // _logger.d('文件消息 type: $messageType, content: ${messageData['content']}');
        await DatabaseService().insertMessage({
          'id': messageData['id']?.toString() ?? '',
          'conversation_id': widget.conversation.id,
          'conversation_type': widget.conversation.isGroup ? 2 : 1,
          'sender_id': messageData['senderId']?.toString() ?? currentUser.id,
          'sender_nickname': messageData['senderNickname'] ?? currentUser.nickname,
          'sender_avatar': messageData['senderAvatar'] ?? currentUser.avatar,
          'quote_id': messageData['quoteId']?.toString() ?? '',
          'content': messageData['content'] ?? fileJsonContent,
          'type': messageType,
          'status': messageData['status'] ?? 0,
          'seq_id': int.tryParse(messageData['seqId']?.toString() ?? '0') ?? 0,
          'created_at': messageData['createdAt'] ?? DateTime.now().toUtc().toIso8601String(),
        });

        // 更新会话的最后一条消息信息
        await ConversationService().updateConversationAfterSendMessage(
          conversationId: widget.conversation.id,
          senderId: messageData['senderId']?.toString() ?? currentUser.id,
          messageId: messageData['id']?.toString() ?? '0',
          messageAt: messageData['createdAt'] ?? DateTime.now().toUtc().toIso8601String(),
          messagePreview: '[文件]',
          messageType: 4,
        );

        // 重新加载消息并更新 UI
        if (mounted) {
          await _loadMessagesAndSync();
        }
      }

      if (mounted) {
        Navigator.pop(context);
        setState(() {
          _quotedMessage = null;
        });
      }
    }
  }

  void _startRecording() async {
    if (_isRecording) return;

    setState(() {
      _isRecording = true;
      _recordingSeconds = 0;
    });

    _logger.d('开始录音...');
    final result = await _voiceService.startRecording();
    _logger.d('开始录音结果: $result');

    if (result == null) {
      setState(() {
        _isRecording = false;
      });
      return;
    }

    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _recordingSeconds = timer.tick;
      });

      if (timer.tick >= 60) {
        _stopRecording();
      }
    });
  }

  void _stopRecording() async {
    if (!_isRecording) return;

    _logger.d('停止录音: 开始处理');
    _recordingTimer?.cancel();

    final result = await _voiceService.stopRecording();

    if (mounted) {
      setState(() {
        _isRecording = false;
        _recordingSeconds = 0;
      });
    }

    _logger.d('停止录音: 结果=$result');
    if (result != null) {
      _logger.d('停止录音: 发送语音, 时长=${result['duration']}, 大小=${result['size']}');
      _sendVoice(result['path'], result['duration'], result['size']);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('录音时间太短'.tr())));
      }
    }
  }

  void _cancelRecording() async {
    if (!_isRecording) return;

    _logger.d('取消录音: 开始处理');
    _recordingTimer?.cancel();
    await _voiceService.cancelRecording();

    if (mounted) {
      setState(() {
        _isRecording = false;
        _recordingSeconds = 0;
      });
    }
    _logger.d('取消录音: 处理完成');
  }

  void _sendVoice(String filePath, int duration, int size) async {
    final currentUser = _accountService.currentUser;
    if (currentUser == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('未登录'.tr())));
      }
      return;
    }

    final fileName = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    final contentType = 'audio/mp4';

    final file = File(filePath);
    final fileBytes = await file.readAsBytes();
    final uploadResult = await FileService().createUploadUrl(contentType, fileName, fileBytes.length, 'voice');

    if (!mounted) return;

    if (uploadResult == null || !uploadResult.isSuccess) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('获取上传链接失败'.tr())));
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
                  Text('正在上传语音...'.tr(), style: TextStyle(fontSize: 16)),
                  const SizedBox(height: 10),
                  Text('${(progress * 100).toInt()}%', style: const TextStyle(fontSize: 14, color: Colors.grey)),
                  const SizedBox(height: 5),
                  SizedBox(width: 200, child: LinearProgressIndicator(value: progress > 0 ? progress : null)),
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: () {
                      isCancelled = true;
                      cancelToken?.cancel('用户取消上传'.tr());
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('上传已取消'.tr())));
                    },
                    child: Text('取消上传'.tr(), style: TextStyle(color: Colors.red)),
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
    _logger.d('上传语音到R2结果: $uploaded');
    if (!uploaded) {
      if (mounted && !isCancelled) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('上传语音失败'.tr()), duration: Duration(seconds: 5)));
      }
      return;
    }

    if (!mounted) return;
    Navigator.pop(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 20),
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text('正在发送语音...'.tr(), style: TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );

    final voiceJsonContent = jsonEncode({'url': uploadResult.fileUrl, 'duration': duration, 'size': size});

    SendMessageResult sendResult;
    if (widget.conversation.isGroup) {
      sendResult = await ChatService().sendGroupMessage(
        conversationId: widget.conversation.id,
        message: voiceJsonContent,
        type: 2,
      );
      if (!sendResult.isSuccess && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(sendResult.message ?? '语音发送失败'.tr())));
      }
    } else {
      sendResult = await ChatService().sendPrivateMessage(
        conversationId: widget.conversation.id,
        receiverId: widget.conversation.chatUserId,
        message: voiceJsonContent,
        type: 2,
      );
      if (!sendResult.isSuccess && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(sendResult.message ?? '语音发送失败'.tr())));
      }
    }

    if (!mounted) return;
    Navigator.pop(context);

    if (sendResult.isSuccess && sendResult.messageData != null) {
      // 使用服务端返回的完整消息数据插入到本地数据库
      final messageData = sendResult.messageData!;
      _logger.d('发送语音成功，服务端返回的数据: $messageData');
      final currentUser = _accountService.currentUser;
      if (currentUser != null) {
        final messageType = messageData['type'] as int? ?? 2;
        // _logger.d('语音消息 type: $messageType, content: ${messageData['content']}');
        await DatabaseService().insertMessage({
          'id': messageData['id']?.toString() ?? '',
          'conversation_id': widget.conversation.id,
          'conversation_type': widget.conversation.isGroup ? 2 : 1,
          'sender_id': messageData['senderId']?.toString() ?? currentUser.id,
          'sender_nickname': messageData['senderNickname'] ?? currentUser.nickname,
          'sender_avatar': messageData['senderAvatar'] ?? currentUser.avatar,
          'quote_id': messageData['quoteId']?.toString() ?? '',
          'content': messageData['content'] ?? voiceJsonContent,
          'type': messageType,
          'status': messageData['status'] ?? 0,
          'seq_id': int.tryParse(messageData['seqId']?.toString() ?? '0') ?? 0,
          'created_at': messageData['createdAt'] ?? DateTime.now().toUtc().toIso8601String(),
        });

        // 更新会话的最后一条消息信息
        await ConversationService().updateConversationAfterSendMessage(
          conversationId: widget.conversation.id,
          senderId: messageData['senderId']?.toString() ?? currentUser.id,
          messageId: messageData['id']?.toString() ?? '0',
          messageAt: messageData['createdAt'] ?? DateTime.now().toUtc().toIso8601String(),
          messagePreview: '[语音]',
          messageType: 2,
        );

        // 重新加载消息并更新 UI
        if (mounted) {
          await _loadMessagesAndSync();
        }
      }

      if (mounted) {
        setState(() {
          _quotedMessage = null;
        });
      }
    }
  }

  /// 发送消息
  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final currentUser = _accountService.currentUser;
    if (currentUser == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('未登录'.tr())));
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

    if (result.isSuccess && result.messageData != null) {
      // 使用服务端返回的完整消息数据插入到本地数据库
      final messageData = result.messageData!;
      await DatabaseService().insertMessage({
        'id': messageData['id']?.toString() ?? '',
        'conversation_id': widget.conversation.id,
        'conversation_type': widget.conversation.isGroup ? 2 : 1,
        'sender_id': messageData['senderId']?.toString() ?? currentUser.id,
        'sender_nickname': messageData['senderNickname'] ?? currentUser.nickname,
        'sender_avatar': messageData['senderAvatar'] ?? currentUser.avatar,
        'quote_id': messageData['quoteId']?.toString() ?? '',
        'content': messageData['content'] ?? text,
        'type': messageData['type'] ?? 0,
        'status': messageData['status'] ?? 0,
        'seq_id': int.tryParse(messageData['seqId']?.toString() ?? '0') ?? 0,
        'created_at': messageData['createdAt'] ?? DateTime.now().toUtc().toIso8601String(),
      });

      // 更新会话的最后一条消息信息
      await ConversationService().updateConversationAfterSendMessage(
        conversationId: widget.conversation.id,
        senderId: messageData['senderId']?.toString() ?? currentUser.id,
        messageId: messageData['id']?.toString() ?? '0',
        messageAt: messageData['createdAt'] ?? DateTime.now().toUtc().toIso8601String(),
        messagePreview: messageData['content'] ?? text,
        messageType: messageData['type'] ?? 0,
      );

      // 增量更新 UI
      if (mounted) {
        setState(() {
          final newMessage = Message(
            id: messageData['id']?.toString() ?? '',
            senderId: messageData['senderId']?.toString() ?? currentUser.id,
            senderNickname: messageData['senderNickname'] ?? currentUser.nickname,
            senderAvatar: messageData['senderAvatar'] ?? currentUser.avatar,
            content: messageData['content'] ?? text,
            type: MessageType.values.firstWhere(
              (e) => e.index == (messageData['type'] ?? 0),
              orElse: () => MessageType.text,
            ),
            createdAt: TimeUtil.parseUtcTime(messageData['createdAt']?.toString()) ?? DateTime.now().toUtc(),
            isRead: true,
            quoteId: messageData['quoteId']?.toString() != '0' ? messageData['quoteId']?.toString() : null,
            status: MessageStatus.normal,
            seqId: int.tryParse(messageData['seqId']?.toString() ?? '0') ?? 0,
          );

          // 去重并添加
          if (!_messages.any((m) => m.id == newMessage.id)) {
            _messages.add(newMessage);
            // 排序
            _messages.sort((a, b) => a.seqId.compareTo(b.seqId));
          }

          _messageController.clear();
          _quotedMessage = null;
        });

        // 滚动到底部
        _scrollToBottom(true);
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result.message ?? '消息发送失败'.tr()), backgroundColor: AppTheme.badgeColor));
      }
    }
  }
}
