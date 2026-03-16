import 'dart:io';
import 'dart:async';
import 'package:record/record.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:permission_handler/permission_handler.dart';

class VoiceService {
  static final VoiceService _instance = VoiceService._internal();
  factory VoiceService() => _instance;
  VoiceService._internal();

  final Logger _logger = Logger();
  AudioRecorder? _recorder;
  AudioPlayer? _audioPlayer;
  StreamSubscription? _playerCompleteSubscription;
  String? _recordingPath;
  DateTime? _recordingStartTime;
  bool _isRecording = false;
  bool _isInitialized = false;
  bool _isDisposed = false;

  void Function(String)? onError;

  String? get recordingPath => _recordingPath;
  bool get isRecording => _isRecording;

  bool get isMobilePlatform {
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  }

  bool get isDesktopPlatform {
    return Platform.isWindows || Platform.isLinux;
  }

  bool get isPlatformSupported {
    return isMobilePlatform || isDesktopPlatform;
  }

  Future<void> _ensureAudioPlayer() async {
    if (!_isInitialized) {
      await initialize();
    }
    if (_audioPlayer == null) {
      _audioPlayer = AudioPlayer();
      _logger.d('重新创建音频播放器');
    }
  }

  Future<void> initialize() async {
    if (_isInitialized && !_isDisposed) return;

    if (_isDisposed) {
      await _cleanup();
    }

    _isDisposed = false;
    _audioPlayer = AudioPlayer();
    _recorder = AudioRecorder();

    try {
      final hasPermission = await _recorder!.hasPermission();
      if (hasPermission) {
        _logger.d('语音服务已初始化（支持录音）');
      } else {
        onError?.call('没有录音权限，请开启麦克风权限');
      }
    } catch (e) {
      _logger.w('检查录音权限失败: $e');
      onError?.call('检查录音权限失败');
    }

    _isInitialized = true;
  }

  Future<void> _cleanup() async {
    try {
      await _playerCompleteSubscription?.cancel();
    } catch (e) {
      _logger.w('取消播放器订阅失败: $e');
    }
    _playerCompleteSubscription = null;

    if (_audioPlayer != null) {
      try {
        await _audioPlayer!.stop();
      } catch (e) {
        _logger.w('停止播放器失败: $e');
      }
      try {
        await _audioPlayer!.dispose();
      } catch (e) {
        _logger.w('释放音频播放器失败: $e');
      }
      _audioPlayer = null;
    }

    if (_recorder != null) {
      try {
        if (await _recorder!.isRecording()) {
          await _recorder!.stop();
        }
      } catch (e) {
        _logger.w('停止录音失败: $e');
      }
      try {
        await _recorder!.dispose();
      } catch (e) {
        _logger.w('释放录音器失败: $e');
      }
      _recorder = null;
    }

    _isRecording = false;
    _isInitialized = false;
    _recordingPath = null;
    _recordingStartTime = null;
  }

  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;

    if (!_isInitialized) return;

    await _cleanup();

    _logger.d('语音服务已释放');
  }

  Future<bool> requestPermissions() async {
    if (isDesktopPlatform) {
      _logger.d('桌面平台不需要麦克风权限申请');
      return true;
    }

    final microphoneStatus = await Permission.microphone.request();
    if (microphoneStatus.isDenied || microphoneStatus.isPermanentlyDenied) {
      _logger.e('麦克风权限被拒绝');
      return false;
    }
    _logger.d('麦克风权限已获取');
    return true;
  }

  Future<String?> startRecording() async {
    if (!isPlatformSupported) {
      _logger.e('当前平台不支持录音');
      return null;
    }

    if (_isDisposed) {
      _logger.e('语音服务已释放，不能录音');
      return null;
    }

    try {
      if (!_isInitialized) {
        await initialize();
      }

      final hasPermission = await requestPermissions();
      if (!hasPermission) {
        onError?.call('没有麦克风权限');
        return null;
      }

      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _recordingPath = '${tempDir.path}/voice_$timestamp.m4a';
      _recordingStartTime = DateTime.now();
      _isRecording = true;

      _logger.d('开始录音: $_recordingPath');

      await _recorder!.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000, sampleRate: 44100),
        path: _recordingPath!,
      );

      _logger.d('录音已开始');
      return _recordingPath;
    } catch (e) {
      _logger.e('开始录音失败: $e');
      _isRecording = false;
      return null;
    }
  }

  Future<Map<String, dynamic>?> stopRecording() async {
    if (!isPlatformSupported) {
      _logger.e('当前平台不支持录音');
      return null;
    }

    try {
      _logger.d('stopRecording: _isRecording=$_isRecording');
      if (!_isRecording) {
        _logger.w('stopRecording: 录音未开始');
        return null;
      }

      final path = await _recorder!.stop();
      _isRecording = false;

      _logger.d('stopRecording: 录音已停止, path=$path, _recordingPath=$_recordingPath');

      final recordPath = path ?? _recordingPath;
      if (recordPath == null || _recordingStartTime == null) {
        _logger.w('stopRecording: 路径或时间为空');
        return null;
      }

      final file = File(recordPath);
      if (!await file.exists()) {
        _logger.e('stopRecording: 录音文件不存在');
        return null;
      }

      final fileSize = await file.length();
      final duration = DateTime.now().difference(_recordingStartTime!).inSeconds;

      _logger.d('stopRecording: 录音时长=$duration秒, 文件大小=$fileSize');

      if (duration < 1) {
        _logger.w('录音时长太短，删除文件');
        await file.delete();
        return null;
      }

      if (duration > 60) {
        _logger.w('录音时长超过60秒，删除文件');
        await file.delete();
        return null;
      }

      _logger.d('停止录音成功: 路径=$recordPath, 时长=$duration秒, 大小=$fileSize');
      return {'path': recordPath, 'duration': duration, 'size': fileSize};
    } catch (e) {
      _logger.e('停止录音失败: $e');
      _isRecording = false;
      return null;
    }
  }

  Future<void> cancelRecording() async {
    if (!isPlatformSupported) {
      return;
    }

    if (_isDisposed) {
      return;
    }

    try {
      if (!_isRecording) {
        return;
      }

      await _recorder?.stop();
      _isRecording = false;

      if (_recordingPath != null) {
        final file = File(_recordingPath!);
        if (await file.exists()) {
          await file.delete();
          _logger.d('已取消录音并删除文件');
        }
      }
    } catch (e) {
      _logger.e('取消录音失败: $e');
      _isRecording = false;
    }
  }

  Future<void> playVoice(String url, {void Function()? onComplete}) async {
    try {
      await _ensureAudioPlayer();
      if (_audioPlayer == null) {
        _logger.e('音频播放器为空');
        return;
      }

      _logger.d('开始播放语音: $url');

      await _playerCompleteSubscription?.cancel();

      _playerCompleteSubscription = _audioPlayer!.onPlayerComplete.listen((event) {
        _logger.d('语音播放完成');
        onComplete?.call();
      });

      await _audioPlayer!.setSourceUrl(url);
      await _audioPlayer!.resume();
    } catch (e) {
      _logger.e('播放语音失败: $e');
    }
  }

  Future<void> stopPlay() async {
    try {
      await _ensureAudioPlayer();
      if (_audioPlayer == null) {
        _logger.e('音频播放器为空');
        return;
      }

      await _audioPlayer!.stop();
      _logger.d('停止播放语音');
    } catch (e) {
      _logger.e('停止播放语音失败：$e');
    }
  }

  Future<void> pausePlay() async {
    try {
      await _ensureAudioPlayer();
      if (_audioPlayer == null) {
        _logger.e('音频播放器为空');
        return;
      }

      await _audioPlayer!.pause();
      _logger.d('暂停播放语音');
    } catch (e) {
      _logger.e('暂停播放语音失败: $e');
    }
  }

  Future<void> resumePlay() async {
    try {
      await _ensureAudioPlayer();
      if (_audioPlayer == null) {
        _logger.e('音频播放器为空');
        return;
      }

      await _audioPlayer!.resume();
      _logger.d('恢复播放语音');
    } catch (e) {
      _logger.e('恢复播放语音失败: $e');
    }
  }
}
