import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import '../../theme/app_theme.dart';
import '../../services/user_service.dart';
import '../../models/user.dart';
import '../../widgets/search_bar_widget.dart';
import 'user_detail_page.dart';

/// 添加好友页面 - 搜索用户
class AddFriendPage extends StatefulWidget {
  const AddFriendPage({super.key});

  @override
  State<AddFriendPage> createState() => _AddFriendPageState();
}

class _AddFriendPageState extends State<AddFriendPage> {
  final TextEditingController _searchController = TextEditingController();
  final UserService _userService = UserService();
  final _logger = Logger();
  bool _isLoading = false;
  String? _errorMessage;

  /// 执行搜索
  Future<void> _handleSearch(String keyword) async {
    final key = keyword.trim();
    if (key.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await _userService.searchUser(key);
      _logger.d('搜索结果: $results');
      if (!mounted) return;

      if (results != null && results.isNotEmpty) {
        final userData = results.first;
        final user = User.fromJson(userData);

        Navigator.push(context, MaterialPageRoute(builder: (context) => UserDetailPage(user: user)));
      } else {
        setState(() {
          _errorMessage = '该用户不存在';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = '搜索异常，请稍后重试';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: CustomScrollView(
        slivers: [
          // 顶部渐变 AppBar
          SliverAppBar(
            pinned: true,
            elevation: 0,
            scrolledUnderElevation: 0,
            backgroundColor: Colors.transparent,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text(
              '添加好友',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            centerTitle: true,
            flexibleSpace: Container(
              decoration: AppTheme.getAppBarDecoration(context),
            ),
          ),

          // 搜索栏
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: CustomSearchBar(
                controller: _searchController,
                hintText: '搜索 ID / 账号 / 手机号',
                readOnly: false,
                onChanged: (_) {},
                onSubmitted: _handleSearch,
              ),
            ),
          ),

          // 搜索状态或错误提示
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: _isLoading
                  ? const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                          ),
                        ),
                        SizedBox(height: 16),
                        Text('正在搜索...', style: TextStyle(color: AppTheme.textHint)),
                      ],
                    )
                  : _errorMessage != null
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_off_rounded, size: 64, color: AppTheme.primaryColor.withValues(alpha: 0.2)),
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage!,
                          style: const TextStyle(fontSize: 16, color: AppTheme.textHint, fontWeight: FontWeight.w500),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.person_search_rounded,
                          size: 80,
                          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
                        ),
                        const SizedBox(height: 16),
                        const Text('搜索对方账号即可添加', style: TextStyle(color: AppTheme.textHint)),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
