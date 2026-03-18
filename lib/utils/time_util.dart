class TimeUtil {
  /// 星期几映射
  static const _weekDays = {1: '星期一', 2: '星期二', 3: '星期三', 4: '星期四', 5: '星期五', 6: '星期六', 7: '星期日'};

  /// 解析UTC时间
  /// 将字符串格式的时间解析为 DateTime 对象
  /// @param timeStr 时间字符串（UTC格式）
  /// @return 解析后的 DateTime 对象
  static DateTime? parseUtcTime(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return null;
    var str = timeStr;
    if (!str.endsWith('Z') && !str.contains('+') && str.length > 10) {
      if (str.contains(' ')) str = str.replaceAll(' ', 'T');
      str = '${str}Z';
    }
    return DateTime.tryParse(str);
  }

  /// 格式化消息时间
  /// 根据当前时间与消息时间的差值，返回不同的时间显示格式
  /// @param time 消息发送时间（DateTime 对象）
  /// @return 格式化后的时间字符串
  static String formatMessageTime(DateTime time) {
    // 获取当前时间
    final now = DateTime.now();
    // 获取今天的日期（忽略时间部分）
    final today = DateTime(now.year, now.month, now.day);
    // 获取消息发送日期（忽略时间部分）
    final messageDate = DateTime(time.year, time.month, time.day);
    // 计算消息日期与今天相差的天数
    final dateDiff = today.difference(messageDate).inDays;
    // 将小时格式化为两位数，不足两位前面补0
    final hour = time.hour.toString().padLeft(2, '0');
    // 将分钟格式化为两位数，不足两位前面补0
    final minute = time.minute.toString().padLeft(2, '0');
    // 组合成时间字符串（HH:mm格式）
    final timeStr = '$hour:$minute';
    // 根据日期差值返回不同的格式
    if (dateDiff == 0) {
      // 如果是今天，返回"今天 HH:mm"
      return '今天 $timeStr';
    } else if (dateDiff == 1) {
      // 如果是昨天，返回"昨天 HH:mm"
      return '昨天 $timeStr';
    } else if (dateDiff <= 7 && dateDiff > 0) {
      // 如果是一周内，返回"星期几 HH:mm"
      return '${_weekDays[time.weekday]} $timeStr';
    } else {
      // 如果超过一周，返回"年-月-日 HH:mm"格式
      return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} $timeStr';
    }
  }

  /// 格式化时间
  /// 根据当前时间与消息时间的差值，返回不同的时间显示格式
  /// @param time 消息发送时间（DateTime 对象）
  /// @return 格式化后的时间字符串
  static String formatTime(DateTime? time) {
    if (time == null) return '';
    final localTime = time.toLocal();
    final now = DateTime.now();
    final diff = now.difference(localTime);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) {
      return '${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}';
    }
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${localTime.month}/${localTime.day}';
  }
}
