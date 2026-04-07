import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'theme/app_theme.dart';
import 'pages/home_page.dart';
import 'pages/account/login_page.dart';
import 'pages/account/register_page.dart';
import 'services/account_service.dart';
import 'services/theme_service.dart';
import 'services/chat_service.dart';

/// 应用根组件
/// 根据登录状态决定初始页面，并配置命名路由
class CryptalkApp extends StatefulWidget {
  const CryptalkApp({super.key});

  /// 全局 NavigatorKey，用于在没有 Context 的地方（如通知回调）进行跳转
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  State<CryptalkApp> createState() => _CryptalkAppState();
}

class _CryptalkAppState extends State<CryptalkApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    // 监听应用进入后台/暂停/不活跃状态，并通知 ChatService
    if (state == AppLifecycleState.hidden || 
        state == AppLifecycleState.paused || 
        state == AppLifecycleState.inactive) {
      ChatService().setAppLifecycleState(true);
      return;
    }

    // 当 App 回到前台（Resumed）且用户已登录时，检查并重连 WebSocket
    if (state == AppLifecycleState.resumed) {
      // 首先通知 ChatService 已回到前台，让其能继续之后的重连
      ChatService().setAppLifecycleState(false);
      
      if (AccountService().isLoggedIn) {
        _handleAppResume();
      }
    }
  }

  /// 处理 APP 从后台恢复的逻辑
  Future<void> _handleAppResume() async {
    try {
      // 检查网络连接状态
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult.contains(ConnectivityResult.none)) {
        // 没有网络连接，延迟 3 秒后重试
        await Future.delayed(const Duration(seconds: 3));
        final retryResult = await Connectivity().checkConnectivity();
        if (retryResult.contains(ConnectivityResult.none)) {
          // 仍然没有网络，不进行重连
          return;
        }
      }

      // 网络可用，延迟 1 秒确保网络稳定后再重连
      await Future.delayed(const Duration(seconds: 1));
      ChatService().checkAndReconnect();
    } catch (e) {
      // 网络检查异常，不进行重连
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountService = AccountService();
    final themeService = ThemeService();

    return ListenableBuilder(
      listenable: Listenable.merge([accountService, themeService]),
      builder: (context, _) {
        return MaterialApp(
          navigatorKey: CryptalkApp.navigatorKey,
          title: '闲聊',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeService.themeMode,
          // 初始页面：未登录显示登录页，已登录显示首页
          home: accountService.isLoggedIn ? const HomePage() : const LoginPage(),
          // 命名路由表
          routes: {
            '/login': (context) => const LoginPage(),
            '/register': (context) => const RegisterPage(),
            '/home': (context) => const HomePage(),
          },
          // 全局路由拦截
          onGenerateRoute: (settings) {
            // 1. 定义白名单（允许未登录访问的页面）
            final bool isWhiteList = settings.name == '/login' || settings.name == '/register';

            // 2. 如果未登录且访问的不是白名单页面，强制跳转到登录页
            if (!accountService.isLoggedIn && !isWhiteList) {
              return MaterialPageRoute(
                builder: (context) => const LoginPage(),
                settings: const RouteSettings(name: '/login'),
              );
            }

            // 3. 如果已登录但访问登录/注册页，通常可以重定向到首页（可选）
            if (accountService.isLoggedIn && isWhiteList) {
              return MaterialPageRoute(
                builder: (context) => const HomePage(),
                settings: const RouteSettings(name: '/home'),
              );
            }

            // 让 routes 路由表处理已定义的路由
            return null;
          },
        );
      },
    );
  }
}
