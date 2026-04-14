import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../theme/app_theme.dart';
import '../../services/account_service.dart';

/// 注册页面
/// 包含手机号、昵称、密码、确认密码输入，以及用户协议勾选
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _nameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _invitationCodeController = TextEditingController();
  final _accountService = AccountService();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _agreeToTerms = false;
  bool _isLoading = false;

  // 动画控制器
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnimation = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _fadeController.forward();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _nameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _invitationCodeController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  /// 执行注册
  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_agreeToTerms) {
      _showErrorSnackBar('请先同意用户协议和隐私政策'.tr());
      return;
    }

    setState(() => _isLoading = true);

    final success = await _accountService.register(
      phone: _phoneController.text.trim(),
      password: _passwordController.text,
      name: _nameController.text.trim(),
      invitationCode: _invitationCodeController.text.trim(),
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      // 注册成功，直接跳转首页
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
    } else {
      _showErrorSnackBar(_accountService.errorMessage ?? '注册失败'.tr());
    }
  }

  /// 显示错误提示
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
          child: Column(
            children: [
              // 顶部导航栏
              _buildAppBar(),
              // 表单内容
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: Column(
                        children: [
                          const SizedBox(height: 16),
                          _buildHeader(),
                          const SizedBox(height: 32),
                          _buildFormCard(),
                          const SizedBox(height: 24),
                          _buildLoginLink(),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建顶部导航栏
  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 22),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  /// 构建头部标题
  Widget _buildHeader() {
    return Column(
      children: [
        const SizedBox(height: 16),
        Text(
          '创建新账号'.tr(),
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 2),
        ),
        const SizedBox(height: 8),
        Text('加入闲聊，开始聊天之旅'.tr(), style: TextStyle(fontSize: 15, color: Colors.white.withValues(alpha: 0.85))),
      ],
    );
  }

  /// 构建表单卡片
  Widget _buildFormCard() {
    return Container(
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
            // 手机号
            _buildInputLabel('手机号'.tr()),
            const SizedBox(height: 8),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)],
              style: const TextStyle(fontSize: 16, color: AppTheme.textPrimary),
              decoration: _buildInputDecoration(hintText: '请输入手机号'.tr(), prefixIcon: Icons.phone_android_rounded),
              validator: (value) {
                if (value == null || value.isEmpty) return '请输入手机号'.tr();
                if (value.length != 11) return '请输入11位手机号'.tr();
                return null;
              },
            ),
            const SizedBox(height: 18),

            // 昵称
            _buildInputLabel('昵称'.tr()),
            const SizedBox(height: 8),
            TextFormField(
              controller: _nameController,
              style: const TextStyle(fontSize: 16, color: AppTheme.textPrimary),
              decoration: _buildInputDecoration(hintText: '给自己取个名字吧'.tr(), prefixIcon: Icons.face_rounded),
              validator: (value) {
                if (value == null || value.isEmpty) return '请输入昵称'.tr();
                if (value.length > 20) return '昵称不能超过20个字符'.tr();
                return null;
              },
            ),
            const SizedBox(height: 18),

            // 密码
            _buildInputLabel('密码'.tr()),
            const SizedBox(height: 8),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              style: const TextStyle(fontSize: 16, color: AppTheme.textPrimary),
              decoration: _buildInputDecoration(
                hintText: '设置6位以上密码'.tr(),
                prefixIcon: Icons.lock_rounded,
                suffixIcon: IconButton(
                  onPressed: () {
                    setState(() => _obscurePassword = !_obscurePassword);
                  },
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                    color: AppTheme.textHint,
                    size: 20,
                  ),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) return '请输入密码'.tr();
                if (value.length < 6) return '密码长度不能少于6位'.tr();
                return null;
              },
            ),
            const SizedBox(height: 18),

            // 确认密码
            _buildInputLabel('确认密码'.tr()),
            const SizedBox(height: 8),
            TextFormField(
              controller: _confirmPasswordController,
              obscureText: _obscureConfirmPassword,
              style: const TextStyle(fontSize: 16, color: AppTheme.textPrimary),
              decoration: _buildInputDecoration(
                hintText: '再次输入密码'.tr(),
                prefixIcon: Icons.lock_outline_rounded,
                suffixIcon: IconButton(
                  onPressed: () {
                    setState(() => _obscureConfirmPassword = !_obscureConfirmPassword);
                  },
                  icon: Icon(
                    _obscureConfirmPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                    color: AppTheme.textHint,
                    size: 20,
                  ),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) return '请再次输入密码'.tr();
                if (value != _passwordController.text) return '两次输入的密码不一致'.tr();
                return null;
              },
            ),
            const SizedBox(height: 18),

            // 邀请码
            _buildInputLabel('邀请码 (选填)'.tr()),
            const SizedBox(height: 8),
            TextFormField(
              controller: _invitationCodeController,
              style: const TextStyle(fontSize: 16, color: AppTheme.textPrimary),
              decoration: _buildInputDecoration(hintText: '请输入邀请码'.tr(), prefixIcon: Icons.card_giftcard_rounded),
            ),
            const SizedBox(height: 20),

            // 用户协议
            _buildAgreement(),
            const SizedBox(height: 24),

            // 注册按钮
            _buildRegisterButton(),
          ],
        ),
      ),
    );
  }

  /// 构建输入框标签
  Widget _buildInputLabel(String label) {
    return Text(
      label,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
    );
  }

  /// 构建输入框装饰
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

  /// 构建用户协议勾选
  Widget _buildAgreement() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 22,
          height: 22,
          child: Checkbox(
            value: _agreeToTerms,
            onChanged: (value) {
              setState(() => _agreeToTerms = value ?? false);
            },
            activeColor: AppTheme.primaryColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
            side: BorderSide(color: _agreeToTerms ? AppTheme.primaryColor : AppTheme.textHint, width: 1.5),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: () {
              setState(() => _agreeToTerms = !_agreeToTerms);
            },
            child: RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.5),
                children: [
                  TextSpan(text: '我已阅读并同意 '.tr()),
                  TextSpan(
                    text: '《用户协议》'.tr(),
                    style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.w500),
                  ),
                  TextSpan(text: ' 和 '.tr()),
                  TextSpan(
                    text: '《隐私政策》'.tr(),
                    style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 构建注册按钮
  Widget _buildRegisterButton() {
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
          onPressed: _isLoading ? null : _handleRegister,
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
              : Text(
                  '注册'.tr(),
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white, letterSpacing: 2),
                ),
        ),
      ),
    );
  }

  /// 构建登录链接
  Widget _buildLoginLink() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('已有账号？'.tr(), style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 14)),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            minimumSize: const Size(0, 36),
          ),
          child: Text(
            '返回登录'.tr(),
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              decoration: TextDecoration.underline,
              decorationColor: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}
