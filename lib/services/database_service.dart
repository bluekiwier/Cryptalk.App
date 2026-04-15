import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../utils/logger_util.dart';
import '../models/db/conversation_entity.dart';
import '../models/db/conversation_message_entity.dart';

/// 本地 sqflite 数据库服务
class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Database? _database;
  final _logger = Log.logger;
  String? _currentUserId;

  /// 截断字符串到指定长度
  String _truncate(String text, int maxLength) {
    if (text.length <= maxLength) {
      return text;
    }
    return text.substring(0, maxLength);
  }

  /// 获取数据库实例（懒初始化）
  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  /// 初始化数据库
  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final dbName = _currentUserId != null ? 'cryptalk_$_currentUserId.db' : 'cryptalk.db';
    final path = join(dbPath, dbName);

    final db = await openDatabase(path, version: 2, onCreate: _onCreate, onUpgrade: _onUpgrade);

    // _logger.i('sqflite 数据库初始化成功: $path');
    return db;
  }

  /// 为指定用户初始化数据库（登录时调用）
  Future<void> initForUser(String userId) async {
    await close();
    _currentUserId = userId;
    _database = await _initDatabase();
    // _logger.i('已为用户初始化独立数据库: $_currentUserId');
  }

  /// 清理当前用户数据库（登出时调用）
  /// 只关闭连接，保留数据库文件，以便用户切换账号后再回来时数据仍在
  Future<void> clearForCurrentUser() async {
    await close();

    // final dbPath = await getDatabasesPath();
    // final dbName = 'cryptalk_$_currentUserId.db';
    // final path = join(dbPath, dbName);

    // try {
    //   await deleteDatabase(path);
    //   _logger.i('已删除用户数据库: $path');
    // } catch (e) {
    //   _logger.w('删除数据库失败: $e');
    // }

    _currentUserId = null;
  }

  /// 创建表
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE ${ConversationEntity.tableName} (
        ${ConversationEntity.id} TEXT PRIMARY KEY,
        ${ConversationEntity.type} INTEGER NOT NULL,
        ${ConversationEntity.chatUserId} TEXT NOT NULL,
        ${ConversationEntity.title} TEXT NOT NULL,
        ${ConversationEntity.avatar} TEXT NOT NULL,
        ${ConversationEntity.lastSeqId} INTEGER NOT NULL DEFAULT 0,
        ${ConversationEntity.lastSenderId} TEXT NOT NULL,
        ${ConversationEntity.lastMessageId} TEXT NOT NULL,
        ${ConversationEntity.lastMessageAt} TEXT,
        ${ConversationEntity.lastMessagePreview} TEXT,
        ${ConversationEntity.unreadCount} INTEGER NOT NULL DEFAULT 0,
        ${ConversationEntity.isPinned} INTEGER NOT NULL DEFAULT 0,
        ${ConversationEntity.isMuted} INTEGER NOT NULL DEFAULT 0,
        ${ConversationEntity.updatedAt} TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE ${ConversationMessageEntity.tableName} (
        ${ConversationMessageEntity.id} TEXT PRIMARY KEY,
        ${ConversationMessageEntity.conversationId} TEXT NOT NULL,
        ${ConversationMessageEntity.conversationType} INTEGER,
        ${ConversationMessageEntity.seqId} INTEGER NOT NULL,
        ${ConversationMessageEntity.senderId} TEXT NOT NULL,
        ${ConversationMessageEntity.senderNickname} TEXT,
        ${ConversationMessageEntity.senderAvatar} TEXT,
        ${ConversationMessageEntity.quoteId} TEXT NOT NULL DEFAULT '',
        ${ConversationMessageEntity.content} TEXT NOT NULL,
        ${ConversationMessageEntity.type} INTEGER NOT NULL DEFAULT 0,
        ${ConversationMessageEntity.status} INTEGER NOT NULL DEFAULT 0,
        ${ConversationMessageEntity.isRead} INTEGER NOT NULL DEFAULT 0,
        ${ConversationMessageEntity.createdAt} TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_conversation_is_pinned ON ${ConversationEntity.tableName} (${ConversationEntity.isPinned} DESC)
    ''');

    await db.execute('''
      CREATE INDEX idx_conversation_last_message_at ON ${ConversationEntity.tableName} (${ConversationEntity.lastMessageAt} DESC)
    ''');

    await db.execute('''
      CREATE INDEX idx_message_conversation_id ON ${ConversationMessageEntity.tableName} (${ConversationMessageEntity.conversationId})
    ''');

    await db.execute('''
      CREATE TABLE configs (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    _logger.i('数据库表创建成功');
  }

  /// 数据库版本升级
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    _logger.i('数据库升级：$oldVersion -> $newVersion');
    if (oldVersion < 2) {
      // 由于多个核心 ID 字段从 INTEGER 改为 TEXT，最安全简单的方法是删除并重建表
      // 如果需要保留数据，则需要复杂的 ALTER TABLE + 临时表数据迁移逻辑
      await db.execute('DROP TABLE IF EXISTS ${ConversationEntity.tableName}');
      await db.execute('DROP TABLE IF EXISTS ${ConversationMessageEntity.tableName}');
      await _onCreate(db, newVersion);
      _logger.i('数据库版本升级到 2：已重置会话和消息表');
    }
  }

  // ─────────────────────────────────────────────
  // 会话表操作
  // ─────────────────────────────────────────────

  /// 批量 upsert 会话（插入或更新，保留本地 unread_count）
  /// 支持两种数据格式：本地格式 和 API 同步格式
  Future<void> upsertConversations(List<Map<String, dynamic>> rows) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final row in rows) {
        final conversationId = row['id'];
        if (conversationId == null) continue;

        final existing = await txn.query(
          ConversationEntity.tableName,
          where: '${ConversationEntity.id} = ?',
          whereArgs: [conversationId],
        );

        final data = <String, dynamic>{};

        // 处理 type 字段（API 可能不返回，使用默认值1）
        if (row.containsKey('type') && row['type'] != null) {
          data[ConversationEntity.type] = row['type'];
        } else if (existing.isEmpty) {
          data[ConversationEntity.type] = 1;
        }

        // 处理 chat_user_id 字段
        final chatUserId = row['chat_user_id'] ?? row['chatUserId'];
        if (chatUserId != null) {
          data[ConversationEntity.chatUserId] = chatUserId;
        } else if (existing.isEmpty) {
          data[ConversationEntity.chatUserId] = 0;
        }

        // 处理 title 字段
        if (row.containsKey('title') && row['title'] != null) {
          data[ConversationEntity.title] = row['title'];
        } else if (existing.isNotEmpty) {
          data[ConversationEntity.title] = existing.first[ConversationEntity.title];
        }

        // 处理 avatar 字段
        if (row.containsKey('avatar') && row['avatar'] != null) {
          data[ConversationEntity.avatar] = row['avatar'];
        } else if (existing.isNotEmpty) {
          data[ConversationEntity.avatar] = existing.first[ConversationEntity.avatar];
        }

        // 处理 lastSeqId / last_seq_id 字段
        final lastSeqId = row['last_seq_id'] ?? row['lastSeqId'];
        if (lastSeqId != null) {
          data[ConversationEntity.lastSeqId] = lastSeqId;
        } else if (existing.isNotEmpty) {
          data[ConversationEntity.lastSeqId] = existing.first[ConversationEntity.lastSeqId];
        }

        // 处理 lastSenderId / last_sender_id 字段
        final lastSenderId = row['last_sender_id'] ?? row['lastSenderId'];
        if (lastSenderId != null) {
          data[ConversationEntity.lastSenderId] = lastSenderId;
        } else if (existing.isNotEmpty) {
          data[ConversationEntity.lastSenderId] = existing.first[ConversationEntity.lastSenderId];
        }

        // 处理 lastMessageId / last_message_id 字段
        final lastMessageId = row['last_message_id'] ?? row['lastMessageId'];
        if (lastMessageId != null) {
          data[ConversationEntity.lastMessageId] = lastMessageId;
        } else if (existing.isNotEmpty) {
          data[ConversationEntity.lastMessageId] = existing.first[ConversationEntity.lastMessageId];
        }

        // 处理 lastMessageAt / last_message_at 字段
        final lastMessageAt = row['last_message_at'] ?? row['lastMessageAt'];
        if (lastMessageAt != null) {
          data[ConversationEntity.lastMessageAt] = lastMessageAt;
        } else if (existing.isNotEmpty) {
          data[ConversationEntity.lastMessageAt] = existing.first[ConversationEntity.lastMessageAt];
        }

        // 处理 lastMessagePreview / last_message_preview 字段
        final lastMessagePreview = row['last_message_preview'] ?? row['lastMessagePreview'];
        if (lastMessagePreview != null) {
          data[ConversationEntity.lastMessagePreview] = _truncate(lastMessagePreview.toString(), 50);
        } else if (existing.isNotEmpty) {
          data[ConversationEntity.lastMessagePreview] = existing.first[ConversationEntity.lastMessagePreview];
        }

        // 保留本地的 unread_count、is_pinned、is_muted
        if (existing.isNotEmpty) {
          data[ConversationEntity.unreadCount] = existing.first[ConversationEntity.unreadCount];
          data[ConversationEntity.isPinned] = existing.first[ConversationEntity.isPinned];
          data[ConversationEntity.isMuted] = existing.first[ConversationEntity.isMuted];
        } else {
          data[ConversationEntity.unreadCount] = row['unread_count'] ?? 0;
          data[ConversationEntity.isPinned] = (row['is_pinned'] ?? 0) == 1 ? 1 : 0;
          data[ConversationEntity.isMuted] = (row['is_muted'] ?? 0) == 1 ? 1 : 0;
        }

        data[ConversationEntity.updatedAt] = DateTime.now().toUtc().toIso8601String();

        if (existing.isNotEmpty) {
          await txn.update(
            ConversationEntity.tableName,
            data,
            where: '${ConversationEntity.id} = ?',
            whereArgs: [conversationId],
          );
        } else {
          data[ConversationEntity.id] = conversationId;
          await txn.insert(ConversationEntity.tableName, data);
        }
      }
    });
  }

  /// 更新单条会话（收到新消息时调用）
  Future<void> updateConversationFromMessage({
    required String conversationId,
    required String senderId,
    required String messageId,
    required String messageAt,
    required String messagePreview,
    required int messageType,
    bool updateUnreadCount = true,
  }) async {
    final db = await database;
    final truncatedPreview = _truncate(messagePreview, 50);
    final sql = updateUnreadCount
        ? 'UPDATE ${ConversationEntity.tableName} SET ${ConversationEntity.lastSenderId} = ?, ${ConversationEntity.lastMessageId} = ?, ${ConversationEntity.lastMessageAt} = ?, ${ConversationEntity.lastMessagePreview} = ?, ${ConversationEntity.unreadCount} = ${ConversationEntity.unreadCount} + 1, ${ConversationEntity.updatedAt} = ? WHERE ${ConversationEntity.id} = ?'
        : 'UPDATE ${ConversationEntity.tableName} SET ${ConversationEntity.lastSenderId} = ?, ${ConversationEntity.lastMessageId} = ?, ${ConversationEntity.lastMessageAt} = ?, ${ConversationEntity.lastMessagePreview} = ?, ${ConversationEntity.updatedAt} = ? WHERE ${ConversationEntity.id} = ?';
    final params = updateUnreadCount
        ? [senderId, messageId, messageAt, truncatedPreview, DateTime.now().toUtc().toString(), conversationId]
        : [senderId, messageId, messageAt, truncatedPreview, DateTime.now().toUtc().toString(), conversationId];
    await db.rawUpdate(sql, params);
  }

  /// 更新群名称（收到WebSocket事件或手动修改时调用）
  Future<void> updateConversationTitle(String conversationId, String title) async {
    final db = await database;
    await db.update(
      ConversationEntity.tableName,
      {ConversationEntity.title: title, ConversationEntity.updatedAt: DateTime.now().toUtc().toString()},
      where: '${ConversationEntity.id} = ?',
      whereArgs: [conversationId],
    );
  }

  /// 批量更新会话信息（用于数据同步）
  Future<void> batchUpdateConversations(List<Map<String, dynamic>> conversations) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final item in conversations) {
        final conversationId = item['id'];
        if (conversationId == null) continue;

        final existing = await txn.query(
          ConversationEntity.tableName,
          where: '${ConversationEntity.id} = ?',
          whereArgs: [conversationId],
        );

        if (existing.isEmpty) continue;

        final data = <String, dynamic>{};
        if (item.containsKey('title')) {
          data[ConversationEntity.title] = item['title'];
        }
        if (item.containsKey('avatar')) {
          data[ConversationEntity.avatar] = item['avatar'];
        }
        if (item.containsKey('lastSenderId')) {
          data[ConversationEntity.lastSenderId] = item['lastSenderId'];
        }
        if (item.containsKey('lastMessageId')) {
          data[ConversationEntity.lastMessageId] = item['lastMessageId'];
        }
        if (item.containsKey('lastMessageAt')) {
          data[ConversationEntity.lastMessageAt] = item['lastMessageAt'];
        }
        if (item.containsKey('lastMessagePreview')) {
          data[ConversationEntity.lastMessagePreview] = _truncate(item['lastMessagePreview'] ?? '', 50);
        }
        data[ConversationEntity.updatedAt] = DateTime.now().toUtc().toString();

        await txn.update(
          ConversationEntity.tableName,
          data,
          where: '${ConversationEntity.id} = ?',
          whereArgs: [conversationId],
        );
      }
    });
  }

  /// 获取配置值
  Future<String?> getConfig(String key) async {
    final db = await database;
    final result = await db.query('configs', where: 'key = ?', whereArgs: [key]);
    if (result.isNotEmpty) {
      return result.first['value'] as String?;
    }
    return null;
  }

  /// 设置配置值
  Future<void> setConfig(String key, String value) async {
    final db = await database;
    await db.insert('configs', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 获取指定会话的消息
  Future<List<Map<String, dynamic>>> getLocalMessages(
    String conversationId, {
    int limit = 20,
    String? minMessageId,
  }) async {
    final db = await database;
    final sql = minMessageId != null && minMessageId.isNotEmpty
        ? 'SELECT * FROM ${ConversationMessageEntity.tableName} WHERE ${ConversationMessageEntity.conversationId} = ? AND ${ConversationMessageEntity.id} < ? ORDER BY ${ConversationMessageEntity.seqId} DESC, ${ConversationMessageEntity.createdAt} DESC LIMIT ?'
        : 'SELECT * FROM ${ConversationMessageEntity.tableName} WHERE ${ConversationMessageEntity.conversationId} = ? ORDER BY ${ConversationMessageEntity.seqId} DESC, ${ConversationMessageEntity.createdAt} DESC LIMIT ?';
    final params = minMessageId != null && minMessageId.isNotEmpty ? [conversationId, minMessageId, limit] : [conversationId, limit];
    final results = await db.rawQuery(sql, params);
    return results;
  }

  /// 如果会话不存在则插入（用于初始化）
  Future<void> insertConversationIfAbsent(Map<String, dynamic> row) async {
    final db = await database;
    final exists = await db.query(
      ConversationEntity.tableName,
      where: '${ConversationEntity.id} = ?',
      whereArgs: [row['id']],
    );

    if (exists.isEmpty) {
      await db.insert(ConversationEntity.tableName, {
        ConversationEntity.id: row['id'],
        ConversationEntity.type: row['type'],
        ConversationEntity.chatUserId: row['chat_user_id'],
        ConversationEntity.title: row['title'],
        ConversationEntity.avatar: row['avatar'],
        ConversationEntity.lastSenderId: row['last_sender_id'],
        ConversationEntity.lastMessageId: row['last_message_id'],
        ConversationEntity.lastMessageAt: row['last_message_at'],
        ConversationEntity.lastMessagePreview: row['last_message_preview'] != null
            ? _truncate(row['last_message_preview'] as String, 50)
            : null,
        ConversationEntity.unreadCount: row['unread_count'] ?? 0,
        ConversationEntity.isPinned: (row['is_pinned'] ?? 0) == 1 ? 1 : 0,
        ConversationEntity.isMuted: (row['is_muted'] ?? 0) == 1 ? 1 : 0,
        ConversationEntity.updatedAt: DateTime.now().toUtc().toString(),
      });
    }
  }

  /// 将指定会话的未读数清零
  Future<void> clearUnreadCount(String conversationId) async {
    final db = await database;
    await db.update(
      ConversationEntity.tableName,
      {ConversationEntity.unreadCount: 0},
      where: '${ConversationEntity.id} = ?',
      whereArgs: [conversationId],
    );
  }

  /// 分页查询本地会话列表（按置顶 + 最新消息时间降序）
  Future<List<Map<String, dynamic>>> queryConversations({int limit = 20, int offset = 0}) async {
    final db = await database;
    final results = await db.query(
      ConversationEntity.tableName,
      orderBy:
          '${ConversationEntity.isPinned} DESC, CASE WHEN ${ConversationEntity.lastMessageAt} IS NULL THEN 0 ELSE 1 END DESC, COALESCE(${ConversationEntity.lastMessageAt}, ${ConversationEntity.updatedAt}) DESC',
      limit: limit,
      offset: offset,
    );
    return results.map((e) => e).toList();
  }

  /// 获取单个会话
  Future<Map<String, dynamic>?> getConversation(String id) async {
    final db = await database;
    final result = await db.query(ConversationEntity.tableName, where: '${ConversationEntity.id} = ?', whereArgs: [id]);
    return result.isNotEmpty ? result.first : null;
  }

  /// 查询本地会话总数
  Future<int> conversationCount() async {
    final db = await database;
    final count = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM ${ConversationEntity.tableName}'));
    return count ?? 0;
  }

  /// 检查会话是否存在本地
  Future<bool> conversationExists(String conversationId) async {
    final db = await database;
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM ${ConversationEntity.tableName} WHERE ${ConversationEntity.id} = ?', [
        conversationId,
      ]),
    );
    return (count ?? 0) > 0;
  }

  // ─────────────────────────────────────────────
  // 消息表操作
  // ─────────────────────────────────────────────

  /// 插入一条消息（忽略重复）
  Future<void> insertMessage(Map<String, dynamic> row) async {
    final db = await database;
    await db.insert(ConversationMessageEntity.tableName, {
      ConversationMessageEntity.id: row['id'],
      ConversationMessageEntity.conversationId: row['conversation_id'],
      ConversationMessageEntity.conversationType: row['conversation_type'] ?? 1,
      ConversationMessageEntity.seqId: row['seq_id'] ?? 0,
      ConversationMessageEntity.senderId: row['sender_id'],
      ConversationMessageEntity.senderNickname: row['sender_nickname'],
      ConversationMessageEntity.senderAvatar: row['sender_avatar'],
      ConversationMessageEntity.quoteId: row['quote_id'] ?? 0,
      ConversationMessageEntity.content: row['content'],
      ConversationMessageEntity.type: row['type'] ?? 0,
      ConversationMessageEntity.status: row['status'] ?? 0,
      ConversationMessageEntity.isRead: row['is_read'] ?? 0,
      ConversationMessageEntity.createdAt: row['created_at'],
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 批量插入消息
  Future<void> insertMessages(List<Map<String, dynamic>> rows) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final row in rows) {
        await txn.insert(ConversationMessageEntity.tableName, {
          ConversationMessageEntity.id: row['id'],
          ConversationMessageEntity.conversationId: row['conversation_id'],
          ConversationMessageEntity.conversationType: row['conversation_type'] ?? 1,
          ConversationMessageEntity.senderId: row['sender_id'],
          ConversationMessageEntity.senderNickname: row['sender_nickname'],
          ConversationMessageEntity.senderAvatar: row['sender_avatar'],
          ConversationMessageEntity.quoteId: row['quote_id']?.toString() ?? '',
          ConversationMessageEntity.content: row['content'],
          ConversationMessageEntity.type: row['type'] ?? 0,
          ConversationMessageEntity.status: row['status'] ?? 0,
          ConversationMessageEntity.isRead: row['is_read'] ?? 0,
          ConversationMessageEntity.seqId: row['seq_id'] ?? 0,
          ConversationMessageEntity.createdAt: row['created_at'],
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  /// 分页查询某会话的消息（按 seq_id 和 created_at 降序，翻页用 cursor）
  Future<List<Map<String, dynamic>>> queryMessages({
    required String conversationId,
    int pageSize = 20,
    String? beforeId,
  }) async {
    final db = await database;

    List<Map<String, dynamic>> results;
    if (beforeId != null && beforeId.isNotEmpty) {
      results = await db.query(
        ConversationMessageEntity.tableName,
        where: '${ConversationMessageEntity.conversationId} = ? AND ${ConversationMessageEntity.id} < ?',
        whereArgs: [conversationId, beforeId],
        orderBy: '${ConversationMessageEntity.seqId} DESC, ${ConversationMessageEntity.createdAt} DESC',
        limit: pageSize,
      );
    } else {
      results = await db.query(
        ConversationMessageEntity.tableName,
        where: '${ConversationMessageEntity.conversationId} = ?',
        whereArgs: [conversationId],
        orderBy: '${ConversationMessageEntity.seqId} DESC, ${ConversationMessageEntity.createdAt} DESC',
        limit: pageSize,
      );
    }

    return results.map((e) => e).toList();
  }

  /// 标记消息为已读
  Future<void> markMessageAsRead(String messageId) async {
    final db = await database;
    await db.update(
      ConversationMessageEntity.tableName,
      {ConversationMessageEntity.isRead: 1},
      where: '${ConversationMessageEntity.id} = ?',
      whereArgs: [messageId],
    );
  }

  /// 标记某会话的所有消息为已读
  Future<void> markConversationMessagesAsRead(String conversationId) async {
    final db = await database;
    await db.update(
      ConversationMessageEntity.tableName,
      {ConversationMessageEntity.isRead: 1},
      where: '${ConversationMessageEntity.conversationId} = ?',
      whereArgs: [conversationId],
    );
  }

  /// 清除所有本地聊天记录
  /// 在清除前需要将各个会话的最新 seq_id 更新到 conversation 表中的 last_seq_id 上
  Future<void> clearAllChatHistory() async {
    final db = await database;
    await db.transaction((txn) async {
      // 1. 对于每个会话，找到其目前本地最大的 seq_id
      // 并更新到 conversation 表的 last_seq_id
      await txn.execute('''
        UPDATE ${ConversationEntity.tableName}
        SET ${ConversationEntity.lastSeqId} = COALESCE(
          (SELECT MAX(${ConversationMessageEntity.seqId}) 
           FROM ${ConversationMessageEntity.tableName} 
           WHERE ${ConversationMessageEntity.tableName}.${ConversationMessageEntity.conversationId} = ${ConversationEntity.tableName}.${ConversationEntity.id}),
          ${ConversationEntity.lastSeqId}
        ),
        ${ConversationEntity.lastMessageId} = '',
        ${ConversationEntity.lastMessagePreview} = '',
        ${ConversationEntity.lastMessageAt} = NULL,
        ${ConversationEntity.unreadCount} = 0
      ''');

      // 2. 删除所有消息记录
      await txn.delete(ConversationMessageEntity.tableName);
    });
  }

  /// 关闭数据库
  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
