import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/app_theme.dart';
import '../../config/app_config.dart';
import '../../config/api_config.dart';
import '../account/login_page.dart';

/// 加入公司服务器页面
/// 输入公司 ID 并验证
class CompanyPage extends StatefulWidget {
  const CompanyPage({super.key});

  @override
  State<CompanyPage> createState() => _CompanyPageState();
}

class _CompanyPageState extends State<CompanyPage> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _companyIdController = TextEditingController();

  bool _isLoading = false;
  List<String> _companyHistory = [];
  bool _showHistory = false;

  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<Offset> _formSlideAnimation;

  @override
  void initState() {
    super.initState();
    _loadCompanyHistory();

    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _fadeAnimation = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);

    _slideController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic));
    _formSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic));

    _fadeController.forward();
    _slideController.forward();
  }

  /// 加载公司历史记录
  Future<void> _loadCompanyHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyList = prefs.getStringList('companyIdHistory');
    if (historyList != null) {
      setState(() {
        _companyHistory = historyList;
      });
    }
  }

  /// 保存公司到历史记录
  Future<void> _saveToHistory(String companyId) async {
    final prefs = await SharedPreferences.getInstance();
    if (!_companyHistory.contains(companyId)) {
      setState(() {
        _companyHistory.insert(0, companyId);
        if (_companyHistory.length > 10) {
          _companyHistory = _companyHistory.sublist(0, 10);
        }
      });
      await prefs.setStringList('companyIdHistory', _companyHistory);
    }
  }

  @override
  void dispose() {
    _companyIdController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  /// 验证公司 ID
  Future<void> _validateCompanyId() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final dio = Dio(
        BaseOptions(
          baseUrl: ApiConfig.baseUrl,
          connectTimeout: const Duration(milliseconds: ApiConfig.timeout),
          receiveTimeout: const Duration(milliseconds: ApiConfig.timeout),
          sendTimeout: const Duration(milliseconds: ApiConfig.timeout),
        ),
      );

      final response = await dio.post('/api/company/validate', data: {'companyId': _companyIdController.text.trim()});

      final responseData = response.data;
      if (responseData != null && responseData['success'] == true) {
        final companyId = _companyIdController.text.trim();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('companyId', companyId);
        await _saveToHistory(companyId);

        if (!mounted) return;
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (context) => const LoginPage()));
      } else {
        if (!mounted) return;
        _showErrorSnackBar(responseData?['message'] ?? '验证失败');
      }
    } on DioException catch (e) {
      if (!mounted) return;
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        _showErrorSnackBar('连接超时，请检查网络');
      } else if (e.type == DioExceptionType.connectionError) {
        _showErrorSnackBar('网络连接失败');
      } else {
        _showErrorSnackBar('验证失败：${e.message}');
      }
    } catch (e) {
      if (!mounted) return;
      _showErrorSnackBar('验证失败：$e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// 选择历史记录中的公司
  void _selectCompany(String companyId) {
    _companyIdController.text = companyId;
    setState(() => _showHistory = false);
  }

  /// 删除历史记录
  Future<void> _deleteFromHistory(String companyId) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _companyHistory.remove(companyId);
    });
    if (_companyHistory.isEmpty) {
      await prefs.remove('companyIdHistory');
    } else {
      await prefs.setStringList('companyIdHistory', _companyHistory);
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppTheme.badgeColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF6C63FF), Color(0xFF897CFF), Color(0xFFB4AEFF)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight:
                    MediaQuery.of(context).size.height -
                    MediaQuery.of(context).padding.top -
                    MediaQuery.of(context).padding.bottom,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildBrandSection(),
                    const SizedBox(height: 24),
                    _buildFormSection(),
                    if (_showHistory && _companyHistory.isNotEmpty) _buildHistorySection(),
                    const SizedBox(height: 48),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBrandSection() {
    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Column(
          children: [
            const Text(
              '闲聊',
              style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 4),
            ),
            const SizedBox(height: 8),
            Text(
              '欢迎加入${AppConfig.appName},服务器由购买方自主运营',
              style: TextStyle(fontSize: 16, color: Colors.white.withValues(alpha: 0.85), letterSpacing: 1),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormSection() {
    return SlideTransition(
      position: _formSlideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 40, offset: const Offset(0, 16)),
            ],
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    TextFormField(
                      controller: _companyIdController,
                      style: const TextStyle(fontSize: 16, color: AppTheme.textPrimary),
                      decoration: _buildInputDecoration(hintText: '请输入服务器 ID', prefixIcon: Icons.business_rounded),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return '请输入服务器 ID';
                        }
                        return null;
                      },
                    ),
                    if (_companyHistory.isNotEmpty)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: IconButton(
                          icon: Icon(
                            _showHistory ? Icons.expand_less : Icons.expand_more,
                            color: AppTheme.primaryColor,
                          ),
                          onPressed: () {
                            setState(() => _showHistory = !_showHistory);
                          },
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 24),

                _buildJoinButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHistorySection() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '历史记录',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ..._companyHistory.asMap().entries.map((entry) {
            final index = entry.key;
            final companyId = entry.value;
            return Column(
              children: [
                ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: Icon(Icons.history, color: AppTheme.primaryColor.withValues(alpha: 0.7), size: 18),
                  title: Text(companyId, style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary)),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 18, color: AppTheme.textHint),
                    onPressed: () => _deleteFromHistory(companyId),
                  ),
                  onTap: () => _selectCompany(companyId),
                ),
                if (index < _companyHistory.length - 1) const Divider(height: 1, indent: 56),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildInputLabel(String label) {
    return Text(
      label,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
    );
  }

  InputDecoration _buildInputDecoration({required String hintText, required IconData prefixIcon, Widget? suffixIcon}) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(color: AppTheme.textHint.withValues(alpha: 0.7), fontSize: 15),
      prefixIcon: Container(
        margin: const EdgeInsets.only(left: 4, right: 8),
        child: Icon(prefixIcon, color: AppTheme.primaryColor, size: 20),
      ),
      prefixIconConstraints: const BoxConstraints(minWidth: 44),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: AppTheme.scaffoldBg,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppTheme.badgeColor, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppTheme.badgeColor, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  Widget _buildJoinButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          gradient: _isLoading
              ? LinearGradient(
                  colors: [AppTheme.primaryColor.withValues(alpha: 0.5), AppTheme.primaryDark.withValues(alpha: 0.5)],
                )
              : const LinearGradient(
                  colors: [AppTheme.primaryColor, AppTheme.primaryDark],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: _isLoading
              ? []
              : [
                  BoxShadow(
                    color: AppTheme.primaryColor.withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: ElevatedButton(
          onPressed: _isLoading ? null : _validateCompanyId,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text(
                  '加 入',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white, letterSpacing: 2),
                ),
        ),
      ),
    );
  }
}
