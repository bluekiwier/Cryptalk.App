# chatter

用 Flutter 创建「闲聊」聊天 App，支持 Android/iOS/Web 三端。

Chatter/lib/
├── main.dart # 应用入口
├── app.dart # MaterialApp 配置
├── theme/
│ └── app_theme.dart # 主题系统（蓝紫渐变色系）
├── models/ # 数据模型
│ ├── user.dart # 用户模型
│ ├── message.dart # 消息模型
│ └── conversation.dart # 会话模型
├── data/
│ └── mock_data.dart # 模拟数据（10个联系人、10个会话）
├── pages/
│ ├── home_page.dart # 首页（带动画底部导航栏）
│ ├── chat/
│ │ ├── chat_list_page.dart # 聊天列表页
│ │ └── chat_detail_page.dart # 聊天详情页（消息气泡+输入栏）
│ ├── contacts/
│ │ ├── contacts_page.dart # 通讯录页（按字母分组）
│ │ └── contact_detail_page.dart # 联系人详情页
│ └── profile/
│ ├── profile_page.dart # 个人中心页
│ ├── settings_page.dart # 设置页
│ └── change_password_page.dart # 修改密码页
└── widgets/
├── avatar_widget.dart # 头像组件（在线状态指示）
└── search_bar_widget.dart # 搜索栏组件

🎨 设计亮点
特性 说明
主色调 蓝紫渐变（#6C63FF → #897CFF），搭配绿松石强调色 #00D9A6
渐变 AppBar 顶部使用紫色渐变，视觉层次分明
消息气泡 自己发的消息使用渐变色，对方为白色卡片
动画导航栏 Tab 切换带动画，图标有选中态背景
在线状态指示 绿色圆点 + 发光阴影
卡片圆角设计 全局 16px 圆角 + 微阴影
🚀 三大核心功能
聊天 — 会话列表（置顶、静音、未读角标）→ 点击进入聊天详情 → 可发送消息
通讯录 — 按拼音首字母分组 → 快捷入口（新朋友/群聊/标签）→ 联系人详情页
我的 — 个人信息展示 → 设置（通知/隐私/通用）→ 修改密码（含表单校验）

# 消息推送流程：

服务器推送消息
↓
WebSocket 接收 (stream.listen)
↓
\_handleMessage() 解析
↓
handleChatEvent() 分发
↓
\_handleChatMessage() 处理（存内存、写DB、更新会话）
↓
notifyListeners() 通知
↓
\_onChatServiceUpdated() UI 更新

### 支持的文件类型

- 文档类 ：PDF, DOC, DOCX, XLS, XLSX, PPT, PPTX, TXT, RTF
- 压缩类 ：ZIP, RAR, 7Z
- 音频类 ：MP3, WAV
- 视频类 ：MP4, AVI, MOV
- 图片类 ：JPG, JPEG, PNG, GIF, WEBP, SVG
- 其他 ：默认返回 application/octet-stream

### 录音与播放

- 录音 : 使用 record 插件（支持 Windows、Linux、Android、iOS、macOS）
- 播放 : 使用 audioplayers 插件（支持 Windows、Linux、Android、iOS、macOS）

📱 运行方式
Flutter Web 服务器已在后台运行，你可以在浏览器访问：

http://localhost:8080

如需在手机上运行：

bash

# Android

flutter run -d android

# iOS

flutter run -d ios

# 构建命令

根据目标平台和模式，使用以下命令：

## 1. 构建 Android APK
Debug 模式： 
flutter build apk --debug

Release 模式： 
flutter build apk --release

输出文件路径：build/app/outputs/flutter-apk/app-release.apk

## 2. 构建 iOS 应用
Release 模式： 
flutter build ios --release

构建完成后需使用 Xcode 打包签名。

## 3. 构建 Web 应用
Release 模式： 
flutter build web --release

输出文件路径：build/web

## 4. 构建桌面应用

### Windows: 
flutter build windows --release

### macOS: 
flutter build macos --release

### Linux: 
flutter build linux --release
