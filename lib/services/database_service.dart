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
    final path = join(dbPath, 'cryptalk.db');

    final db = await openDatabase(path, version: 1, onCreate: _onCreate);

    _logger.i('sqflite 数据库初始化成功: $path');
    return db;
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

    _logger.i('数据库表创建成功');
  }

  // ─────────────────────────────────────────────
  // 会话表操作
  // ─────────────────────────────────────────────

  /// 批量 upsert 会话（插入或更新，保留本地 unread_count）
  Future<void> upsertConversations(List<Map<String, dynamic>> rows) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final row in rows) {
        final existing = await txn.query(
          ConversationEntity.tableName,
          where: '${ConversationEntity.id} = ?',
          whereArgs: [row['id']],
        );

        final data = {
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
          ConversationEntity.unreadCount: existing.isNotEmpty
              ? existing[0][ConversationEntity.unreadCount]
              : (row['unread_count'] ?? 0),
          ConversationEntity.isPinned: (row['is_pinned'] ?? 0) == 1 ? 1 : 0,
          ConversationEntity.isMuted: (row['is_muted'] ?? 0) == 1 ? 1 : 0,
          ConversationEntity.updatedAt: DateTime.now().toIso8601String(),
        };

        if (existing.isNotEmpty) {
          await txn.update(
            ConversationEntity.tableName,
            data,
            where: '${ConversationEntity.id} = ?',
            whereArgs: [row['id']],
          );
        } else {
          data[ConversationEntity.id] = row['id'];
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
