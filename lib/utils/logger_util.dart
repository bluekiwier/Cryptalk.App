import 'package:logger/logger.dart';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';

/// 自定义日志输出，解决打印不完整的问题
class DeepLogOutput extends LogOutput {
  @override
  void output(OutputEvent event) {
    for (var line in event.lines) {
      Log.chunkedPrint(line);
    }
  }
}

/// 全局日志工具
class Log {
  static final Logger logger = Logger(
    printer: PrettyPrinter(
      methodCount: 2, // 显示方法调用栈层级
      errorMethodCount: 8, // 错误消息的方法调用栈层级
      lineLength: 160, // 每行长度
      colors: true, // 是否显示颜色
      printEmojis: true, // 是否显示 Emoji
      dateTimeFormat: DateTimeFormat.dateAndTime, // 时间格式
    ),
    output: DeepLogOutput(), // 使用自定义输出
  );

  /// 分段打印逻辑，确保在所有终端中完整显示
  static void chunkedPrint(String message, {String? name}) {
    // 方式 1: 直接使用 developer.log (双重保险，且支持分类名称)
    developer.log(message, name: name ?? 'LOG');

    // 方式 2: 手动分段打印。应对某些环境下 developer.log 依然被截断的情况。
    // 每段 800 个字符
    const int step = 1000;
    if (message.length <= step) {
      debugPrint(message);
      return;
    }

    String remaining = message;
    while (remaining.length > step) {
      debugPrint(remaining.substring(0, step));
      remaining = remaining.substring(step);
    }
    debugPrint(remaining);
  }

  /// 给 Dio LogInterceptor 使用的打印函数
  static void dioPrint(Object object) {
    chunkedPrint(object.toString(), name: 'DIO');
  }

  static void t(dynamic message, [dynamic error, StackTrace? stackTrace]) =>
      logger.t(message, error: error, stackTrace: stackTrace);
  static void v(dynamic message, [dynamic error, StackTrace? stackTrace]) =>
      logger.t(message, error: error, stackTrace: stackTrace);
  static void d(dynamic message, [dynamic error, StackTrace? stackTrace]) =>
      logger.d(message, error: error, stackTrace: stackTrace);
  static void i(dynamic message, [dynamic error, StackTrace? stackTrace]) =>
      logger.i(message, error: error, stackTrace: stackTrace);
  static void w(dynamic message, [dynamic error, StackTrace? stackTrace]) =>
      logger.w(message, error: error, stackTrace: stackTrace);
  static void e(dynamic message, [dynamic error, StackTrace? stackTrace]) =>
      logger.e(message, error: error, stackTrace: stackTrace);
  static void f(dynamic message, [dynamic error, StackTrace? stackTrace]) =>
      logger.f(message, error: error, stackTrace: stackTrace);
}
