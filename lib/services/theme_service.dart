import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 主题服务 - 管理应用的深色/浅色模式
class ThemeService extends ChangeNotifier {
  static final ThemeService _instance = ThemeService._internal();
  factory ThemeService() => _instance;
  ThemeService._internal() {
    _loadThemeMode();
    _loadTextScale();
  }

  static const String _themeModeKey = 'themeMode';
  static const String _textScaleKey = 'textScale';

  ThemeMode _themeMode = ThemeMode.light;
  double _textScale = 1.0;

  /// 获取当前主题模式
  ThemeMode get themeMode => _themeMode;
  
  /// 获取当前字体缩放比例
  double get textScale => _textScale;

  /// 是否为深色模式
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  /// 切换主题模式
  Future<void> toggleTheme(bool isOn) async {
    _themeMode = isOn ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
    await _saveThemeMode();
  }

  /// 设置字体缩放比例
  Future<void> setTextScale(double scale) async {
    _textScale = scale;
    notifyListeners();
    await _saveTextScale();
  }

  /// 从本地加载主题设置
  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final modeIndex = prefs.getInt(_themeModeKey);
    if (modeIndex != null) {
      _themeMode = ThemeMode.values[modeIndex];
      notifyListeners();
    }
  }

  /// 保存主题设置到本地
  Future<void> _saveThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeModeKey, _themeMode.index);
  }

  /// 从本地加载字体缩放比例
  Future<void> _loadTextScale() async {
    final prefs = await SharedPreferences.getInstance();
    final scale = prefs.getDouble(_textScaleKey);
    if (scale != null) {
      _textScale = scale;
      notifyListeners();
    }
  }

  /// 保存字体缩放比例到本地
  Future<void> _saveTextScale() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_textScaleKey, _textScale);
  }
}
