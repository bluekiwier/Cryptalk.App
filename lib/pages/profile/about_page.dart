import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../theme/app_theme.dart';
import '../../config/app_config.dart';

/// 关于页面
/// 介绍 APP 的核心功能和安全特性
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Container(
          decoration: AppTheme.getAppBarDecoration(context),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              '关于'.tr(),
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1),
            ),
            centerTitle: true,
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 40),
            // APP Logo 区域
            Center(
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryColor.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: const Icon(Icons.lock_rounded, size: 50, color: Colors.white),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              AppConfig.appName,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snapshot) {
                return Text(
                  '${'Version'.tr()} ${snapshot.data?.version ?? "0.1.0"}',
                  style: const TextStyle(fontSize: 14, color: AppTheme.textHint),
                );
              },
            ),
            const SizedBox(height: 40),

            // 核心简介
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                '关于应用简介'.tr(),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: AppTheme.textSecondary, height: 1.6),
              ),
            ),

            const SizedBox(height: 40),

            // 特性展示
            _buildFeatureItem(
              context: context,
              icon: Icons.security_rounded,
              title: '端到端加密 (E2EE)'.tr(),
              description: '所有通信内容在设备端加密，云端仅作为中转，不存储任何解密密钥及通信明文。'.tr(),
            ),
            // _buildFeatureItem(
            //   context: context,
            //   icon: Icons.timer_outlined,
            //   title: '阅后即焚',
            //   description: '支持发送阅后即焚消息，消息被阅读后将在双方设备中自动粉碎，不留痕迹。',
            // ),
            _buildFeatureItem(
              context: context,
              icon: Icons.verified_user_outlined,
              title: '零知识存储'.tr(),
              description: '我们不收集您的通讯录、地理位置或任何个人身份信息，真正做到“零知识”运营。'.tr(),
            ),
            _buildFeatureItem(
              context: context,
              icon: Icons.shutter_speed_rounded,
              title: '极速体验'.tr(),
              description: '采用自研加密传输协议，在保证全量加密的前提下，依然拥有毫秒级的即时通讯体验。'.tr(),
            ),

            const SizedBox(height: 40),

            // 底部协议
            Padding(
              padding: EdgeInsets.only(bottom: 40),
              child: Column(
                children: [
                  Text(
                    '© 2026 Cryptalk Team. All Rights Reserved.',
                    style: TextStyle(fontSize: 12, color: AppTheme.textHint),
                  ),
                  SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('服务协议'.tr(), style: TextStyle(fontSize: 12, color: AppTheme.primaryColor)),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('|', style: TextStyle(fontSize: 12, color: AppTheme.textHint)),
                      ),
                      Text('隐私政策'.tr(), style: TextStyle(fontSize: 12, color: AppTheme.primaryColor)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppTheme.primaryColor, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(description, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
