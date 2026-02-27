import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'pages/home_page.dart';
import 'pages/account/login_page.dart';
import 'pages/account/register_page.dart';
import 'services/account_service.dart';
import 'services/theme_service.dart';

/// 应用根组件
/// 根据登录状态决定初始页面，并配置命名路由
class CryptalkApp extends StatelessWidget {
  const CryptalkApp({super.key});

  @override
  Widget build(BuildContext context) {
    final accountService = AccountService();
    final themeService = ThemeService();

    return ListenableBuilder(
      listenable: Listenable.merge([accountService, themeService]),
      builder: (context, _) {
        return MaterialApp(
          title: 'Cryptalk',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeService.themeMode,
          // 初始页面：未登录显示登录页，已登录显示首页
          home: accountService.isLoggedIn
              ? const HomePage()
              : const LoginPage(),
          // 命名路由表
          routes: {
            '/login': (context) => const LoginPage(),
            '/register': (context) => const RegisterPage(),
            '/home': (context) => const HomePage(),
          },
          // 全局路由拦截
          onGenerateRoute: (settings) {
            // 1. 定义白名单（允许未登录访问的页面）
            final bool isWhiteList =
                settings.name == '/login' || settings.name == '/register';

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
