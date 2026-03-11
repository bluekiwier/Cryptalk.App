import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:logger/logger.dart';
import '../models/db/conversation_entity.dart';
import '../models/db/conversation_message_entity.dart';

/// 本地 sqflite 数据库服务
class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Database? _database;
  final _logger = Logger();
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

    final db = await openDatabase(path, version: 1, onCreate: _onCreate);

    _logger.i('sqflite 数据库初始化成功: $path');
    return db;
  }

  /// 为指定用户初始化数据库（登录时调用）
  Future<void> initForUser(String userId) async {
    await close();
    _currentUserId = userId;
    _database = await _initDatabase();
    _logger.i('已为用户初始化独立数据库: $_currentUserId');
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
        ${ConversationEntity.id} INTEGER PRIMARY KEY,
        ${ConversationEntity.type} INTEGER NOT NULL,
        ${ConversationEntity.chatUserId} INTEGER NOT NULL,
        ${ConversationEntity.title} TEXT NOT NULL,
        ${ConversationEntity.avatar} TEXT NOT NULL,
        ${ConversationEntity.lastSenderId} INTEGER NOT NULL,
        ${ConversationEntity.lastMessageId} INTEGER NOT NULL,
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
        ${ConversationMessageEntity.id} INTEGER PRIMARY KEY,
        ${ConversationMessageEntity.conversationId} INTEGER NOT NULL,
        ${ConversationMessageEntity.conversationType} INTEGER,
        ${ConversationMessageEntity.senderId} INTEGER NOT NULL,
        ${ConversationMessageEntity.senderNickname} TEXT,
        ${ConversationMessageEntity.senderAvatar} TEXT,
        ${ConversationMessageEntity.quoteId} INTEGER NOT NULL DEFAULT 0,
        ${ConversationMessageEntity.content} TEXT NOT NULL,
        ${ConversationMessageEntity.type} INTEGER NOT NULL DEFAULT 0,
        ${ConversationMessageEntity.status} INTEGER NOT NULL DEFAULT 0,
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
        if (row.containsKey('chat_user_id') && row['chat_user_id'] != null) {
          data[ConversationEntity.chatUserId] = row['chat_user_id'];
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

        // 处理 lastSenderId / last_sender_id 字段
        final lastSenderId = row['lastSenderId'] ?? row['last_sender_id'];
        if (lastSenderId != null) {
          data[ConversationEntity.lastSenderId] = lastSenderId;
        } else if (existing.isNotEmpty) {
          data[ConversationEntity.lastSenderId] = existing.first[ConversationEntity.lastSenderId];
        }

        // 处理 lastMessageId / last_message_id 字段
        final lastMessageId = row['lastMessageId'] ?? row['last_message_id'];
        if (lastMessageId != null) {
          data[ConversationEntity.lastMessageId] = lastMessageId;
        } else if (existing.isNotEmpty) {
          data[ConversationEntity.lastMessageId] = existing.first[ConversationEntity.lastMessageId];
        }

        // 处理 lastMessageAt / last_message_at 字段
        final lastMessageAt = row['lastMessageAt'] ?? row['last_message_at'];
        if (lastMessageAt != null) {
          data[ConversationEntity.lastMessageAt] = lastMessageAt;
        } else if (existing.isNotEmpty) {
          data[ConversationEntity.lastMessageAt] = existing.first[ConversationEntity.lastMessageAt];
        }

        // 处理 lastMessagePreview / last_message_preview 字段
        final lastMessagePreview = row['lastMessagePreview'] ?? row['last_message_preview'];
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

        data[ConversationEntity.updatedAt] = DateTime.now().toIso8601String();

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
    required int conversationId,
    required int senderId,
    required int messageId,
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
  Future<void> updateConversationTitle(int conversationId, String title) async {
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
  Future<List<Map<String, dynamic>>> getMessages(int conversationId, {int limit = 20, int minMessageId = 0}) async {
    final db = await database;
    final sql = minMessageId > 0
        ? 'SELECT * FROM ${ConversationMessageEntity.tableName} WHERE ${ConversationMessageEntity.conversationId} = ? AND ${ConversationMessageEntity.id} < ? ORDER BY ${ConversationMessageEntity.id} DESC LIMIT ?'
        : 'SELECT * FROM ${ConversationMessageEntity.tableName} WHERE ${ConversationMessageEntity.conversationId} = ? ORDER BY ${ConversationMessageEntity.id} DESC LIMIT ?';
    final params = minMessageId > 0 ? [conversationId, minMessageId, limit] : [conversationId, limit];
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
  Future<void> clearUnreadCount(int conversationId) async {
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
      orderBy: '${ConversationEntity.isPinned} DESC, ${ConversationEntity.lastMessageAt} DESC',
      limit: limit,
      offset: offset,
    );
    return results.map((e) => e).toList();
  }

  /// 查询本地会话总数
  Future<int> conversationCount() async {
    final db = await database;
    final count = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM ${ConversationEntity.tableName}'));
    return count ?? 0;
  }

  /// 检查会话是否存在本地
  Future<bool> conversationExists(int conversationId) async {
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
      ConversationMessageEntity.senderId: row['sender_id'],
      ConversationMessageEntity.senderNickname: row['sender_nickname'],
      ConversationMessageEntity.senderAvatar: row['sender_avatar'],
      ConversationMessageEntity.quoteId: row['quote_id'] ?? 0,
      ConversationMessageEntity.content: row['content'],
      ConversationMessageEntity.type: row['type'] ?? 0,
      ConversationMessageEntity.status: row['status'] ?? 0,
      ConversationMessageEntity.createdAt: row['created_at'],
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
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
          ConversationMessageEntity.quoteId: row['quote_id'] ?? 0,
          ConversationMessageEntity.content: row['content'],
          ConversationMessageEntity.type: row['type'] ?? 0,
          ConversationMessageEntity.status: row['status'] ?? 0,
          ConversationMessageEntity.createdAt: row['created_at'],
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }

  /// 分页查询某会话的消息（按 id 降序，翻页用 cursor）
  Future<List<Map<String, dynamic>>> queryMessages({
    required int conversationId,
    int pageSize = 20,
    int? beforeId,
  }) async {
    final db = await database;

    List<Map<String, dynamic>> results;
    if (beforeId != null && beforeId > 0) {
      results = await db.query(
        ConversationMessageEntity.tableName,
        where: '${ConversationMessageEntity.conversationId} = ? AND ${ConversationMessageEntity.id} < ?',
        whereArgs: [conversationId, beforeId],
        orderBy: '${ConversationMessageEntity.id} DESC',
        limit: pageSize,
      );
    } else {
      results = await db.query(
        ConversationMessageEntity.tableName,
        where: '${ConversationMessageEntity.conversationId} = ?',
        whereArgs: [conversationId],
        orderBy: '${ConversationMessageEntity.id} DESC',
        limit: pageSize,
      );
    }

    return results.map((e) => e).toList();
  }

  /// 关闭数据库
  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
