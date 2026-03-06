import '../models/user.dart';
import '../models/message.dart';
import '../models/conversation.dart';

/// 模拟数据生成器
/// 提供测试用的用户、消息和会话数据
class MockData {
  /// 当前登录用户
  static const User currentUser = User(
    id: 'user_0',
    account: 'user_0',
    nickname: '我',
    avatar: '😎',
    mobile: '138****8888',
    email: 'me@chatter.com',
    signature: '生活不止眼前的代码，还有诗和远方',
    isOnline: true,
  );

  /// 联系人列表
  static final List<User> contacts = [
    const User(
      id: 'user_1',
      account: 'user_1',
      nickname: '张三',
      avatar: '👨💻',
      mobile: '139****1234',
      email: 'zhangsan@email.com',
      signature: '代码改变世界',
      isOnline: true,
    ),
    const User(
      id: 'user_2',
      account: 'user_2',
      nickname: '李四',
      avatar: '👩🎨',
      mobile: '136****5678',
      email: 'lisi@email.com',
      signature: '设计让生活更美好',
      isOnline: true,
    ),
    const User(
      id: 'user_3',
      account: 'user_3',
      nickname: '王五',
      avatar: '🧑🔬',
      mobile: '137****9012',
      email: 'wangwu@email.com',
      signature: '探索未知的世界',
      isOnline: false,
      lastSeen: null,
    ),
    const User(
      id: 'user_4',
      account: 'user_4',
      nickname: '赵六',
      avatar: '👨🍳',
      mobile: '135****3456',
      email: 'zhaoliu@email.com',
      signature: '吃货的日常',
      isOnline: false,
    ),
    const User(
      id: 'user_5',
      account: 'user_5',
      nickname: '钱七',
      avatar: '🧑🚀',
      mobile: '133****7890',
      email: 'qianqi@email.com',
      signature: '仰望星空，脚踏实地',
      isOnline: true,
    ),
    const User(
      id: 'user_6',
      account: 'user_6',
      nickname: '孙八',
      avatar: '👩⚕️',
      mobile: '131****2345',
      email: 'sunba@email.com',
      signature: '健康是最大的财富',
      isOnline: false,
    ),
    const User(
      id: 'user_7',
      account: 'user_7',
      nickname: '周九',
      avatar: '🧑🏫',
      mobile: '132****6789',
      email: 'zhoujiu@email.com',
      signature: '教育改变未来',
      isOnline: true,
    ),
    const User(
      id: 'user_8',
      account: 'user_8',
      nickname: '吴十',
      avatar: '👨🎤',
      mobile: '130****0123',
      email: 'wushi@email.com',
      signature: '音乐是灵魂的语言',
      isOnline: false,
    ),
    const User(
      id: 'user_9',
      account: 'user_9',
      nickname: '郑十一',
      avatar: '🧑💼',
      mobile: '134****4567',
      email: 'zheng11@email.com',
      signature: '商业创造价值',
      isOnline: true,
    ),
    const User(
      id: 'user_10',
      account: 'user_10',
      nickname: '冯十二',
      avatar: '👩🔧',
      mobile: '138****8901',
      email: 'feng12@email.com',
      signature: '动手创造美好',
      isOnline: false,
    ),
  ];

  /// 会话列表
  static final List<Conversation> conversations = [
    Conversation(
      id: 'conv_1',
      chatUserId: 'user_1',
      title: '张三',
      avatar: '👨‍💻',
      lastMessage: Message(
        id: 'msg_1',
        senderId: 'user_1',
        content: '明天下午一起喝咖啡吗？',
        createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
      ),
      unreadCount: 2,
      isPinned: true,
    ),
    Conversation(
      id: 'conv_2',
      chatUserId: 'user_2',
      title: '李四',
      avatar: '👩‍🎨',
      lastMessage: Message(
        id: 'msg_2',
        senderId: 'user_2',
        content: '新设计稿我发你邮箱了，看看怎么样',
        createdAt: DateTime.now().subtract(const Duration(minutes: 15)),
      ),
      unreadCount: 1,
    ),
    Conversation(
      id: 'conv_3',
      chatUserId: 'user_3',
      title: '技术交流群',
      avatar: '💻',
      isGroup: true,
      lastMessage: Message(
        id: 'msg_3',
        senderId: 'user_3',
        content: '王五: Flutter 3.0 新功能太棒了！',
        createdAt: DateTime.now().subtract(const Duration(minutes: 30)),
      ),
      unreadCount: 15,
      isPinned: true,
      members: [contacts[0], contacts[1], contacts[2], contacts[4]],
    ),
    Conversation(
      id: 'conv_4',
      chatUserId: 'user_4',
      title: '赵六',
      avatar: '👨‍🍳',
      lastMessage: Message(
        id: 'msg_4',
        senderId: 'user_0',
        content: '好的，周末见！',
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
        isRead: true,
      ),
      unreadCount: 0,
    ),
    Conversation(
      id: 'conv_5',
      chatUserId: 'user_5',
      title: '钱七',
      avatar: '🧑‍🚀',
      lastMessage: Message(
        id: 'msg_5',
        senderId: 'user_5',
        content: '航天纪录片看了吗？推荐给你',
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      ),
      unreadCount: 3,
    ),
    Conversation(
      id: 'conv_6',
      chatUserId: 'user_6',
      title: '项目组',
      avatar: '🏢',
      isGroup: true,
      lastMessage: Message(
        id: 'msg_6',
        senderId: 'user_7',
        content: '周九: 本周迭代目标已更新，请查看',
        createdAt: DateTime.now().subtract(const Duration(hours: 3)),
      ),
      unreadCount: 8,
      members: [contacts[0], contacts[2], contacts[4], contacts[6], contacts[8]],
    ),
    Conversation(
      id: 'conv_7',
      chatUserId: 'user_7',
      title: '孙八',
      avatar: '👩‍⚕️',
      lastMessage: Message(
        id: 'msg_7',
        senderId: 'user_6',
        content: '记得按时吃药哦 💊',
        createdAt: DateTime.now().subtract(const Duration(hours: 5)),
        isRead: true,
      ),
      unreadCount: 0,
      isMuted: true,
    ),
    Conversation(
      id: 'conv_8',
      chatUserId: 'user_8',
      title: '周九',
      avatar: '🧑‍🏫',
      lastMessage: Message(
        id: 'msg_8',
        senderId: 'user_7',
        content: '课程资料我整理好了，晚上发你',
        createdAt: DateTime.now().subtract(const Duration(hours: 8)),
      ),
      unreadCount: 0,
    ),
    Conversation(
      id: 'conv_9',
      chatUserId: 'user_9',
      title: '美食分享群',
      avatar: '🍜',
      isGroup: true,
      lastMessage: Message(
        id: 'msg_9',
        senderId: 'user_4',
        content: '赵六: [图片] 今天做的红烧肉',
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
      unreadCount: 0,
      members: [contacts[3], contacts[5], contacts[7], contacts[9]],
    ),
    Conversation(
      id: 'conv_10',
      chatUserId: 'user_10',
      title: '郑十一',
      avatar: '🧑‍💼',
      lastMessage: Message(
        id: 'msg_10',
        senderId: 'user_9',
        content: '合同条款已修改，请确认',
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
      unreadCount: 1,
    ),
  ];

  /// 聊天详情消息列表（模拟与张三的对话）
  static List<Message> getChatMessages(String conversationId) {
    return [
      Message(
        id: 'dm_1',
        senderId: 'user_1',
        content: '嘿，最近忙什么呢？',
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      ),
      Message(
        id: 'dm_2',
        senderId: 'user_0',
        content: '在做一个 Flutter 项目，很有意思！',
        createdAt: DateTime.now().subtract(const Duration(hours: 1, minutes: 55)),
        isRead: true,
      ),
      Message(
        id: 'dm_3',
        senderId: 'user_1',
        content: '哦？什么项目？',
        createdAt: DateTime.now().subtract(const Duration(hours: 1, minutes: 50)),
      ),
      Message(
        id: 'dm_4',
        senderId: 'user_0',
        content: '一个聊天 App，叫「闲聊」，支持 Android、iOS 和 Web 三端！',
        createdAt: DateTime.now().subtract(const Duration(hours: 1, minutes: 45)),
        isRead: true,
      ),
      Message(
        id: 'dm_5',
        senderId: 'user_1',
        content: '听起来很酷啊！用的什么技术栈？',
        createdAt: DateTime.now().subtract(const Duration(hours: 1, minutes: 40)),
      ),
      Message(
        id: 'dm_6',
        senderId: 'user_0',
        content: 'Flutter + Dart，一套代码搞定三个平台 🚀',
        createdAt: DateTime.now().subtract(const Duration(hours: 1, minutes: 35)),
        isRead: true,
      ),
      Message(
        id: 'dm_7',
        senderId: 'user_1',
        content: '太厉害了，改天教教我吧',
        createdAt: DateTime.now().subtract(const Duration(hours: 1, minutes: 30)),
      ),
      Message(
        id: 'dm_8',
        senderId: 'user_0',
        content: '没问题！随时都可以 😄',
        createdAt: DateTime.now().subtract(const Duration(hours: 1, minutes: 25)),
        isRead: true,
      ),
      Message(
        id: 'dm_9',
        senderId: 'user_1',
        content: '对了，明天下午一起喝咖啡吗？',
        createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
      ),
      Message(
        id: 'dm_10',
        senderId: 'user_1',
        content: '上次去的那家店还不错',
        createdAt: DateTime.now().subtract(const Duration(minutes: 3)),
      ),
    ];
  }

  /// 按拼音首字母分组的联系人索引
  static final Map<String, List<User>> groupedContacts = {
    'F': [contacts[9]], // 冯十二
    'L': [contacts[1]], // 李四
    'Q': [contacts[4]], // 钱七
    'S': [contacts[5]], // 孙八
    'W': [contacts[2], contacts[7]], // 王五, 吴十
    'Z': [contacts[0], contacts[3], contacts[6], contacts[8]], // 张三, 赵六, 周九, 郑十一
  };
}
