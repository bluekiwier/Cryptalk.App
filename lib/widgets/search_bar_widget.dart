import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// 自定义搜索栏组件
/// 带有圆角和微交互动画
class CustomSearchBar extends StatelessWidget {
  final String hintText;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;
  final ValueChanged<String>? onSubmitted;
  final bool readOnly;

  const CustomSearchBar({
    super.key,
    this.hintText = '搜索',
    this.controller,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.readOnly = true,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.dividerColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(Icons.search_rounded, color: AppTheme.textHint, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: readOnly
                  ? Text(
                      hintText,
                      style: TextStyle(color: AppTheme.textHint, fontSize: 14),
                    )
                  : TextField(
                      controller: controller,
                      autofocus: !readOnly,
                      onChanged: onChanged,
                      onSubmitted: onSubmitted,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: hintText,
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        filled: false,
                      ),
                      style: const TextStyle(fontSize: 14),
                    ),
            ),
            if (!readOnly && onSubmitted != null) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  if (controller != null) {
                    onSubmitted!(controller!.text);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    '搜索',
                    style: TextStyle(
                      color: AppTheme.primaryColor,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
