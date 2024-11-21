import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart'; // 플랫폼 서비스 관련 기능
import 'package:haptic_feedback/haptic_feedback.dart';
import 'package:volume_controller/volume_controller.dart';

// 포그라운드 서비스 콜백
@pragma('vm:entry-point')
void startCallback() {
  debugPrint('Starting Sleep Detection Service...');
  FlutterForegroundTask.setTaskHandler(SleepDetectionHandler());
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort(); // 포그라운드 서비스 통신 초기화
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: WithForegroundTask(child: const FaceDetectorView()),
    );
  }
}

// 졸음 감지 서비스 핸들러
class SleepDetectionHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {}

  @override
  void onReceiveData(Object? data) {}
}

class FaceDetectorView extends StatefulWidget {
  const FaceDetectorView({super.key});

  @override
  State<FaceDetectorView> createState() => _FaceDetectorViewState();
}

class _FaceDetectorViewState extends State<FaceDetectorView> {
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
    ),
  );
  final AudioPlayer _audioPlayer = AudioPlayer();
  final _isSleepingNotifier = ValueNotifier<bool>(false);

  static const double _closedEyeThreshold = 0.5;
  static const int _drowsinessFrameThreshold = 8;
  int _closedEyeFrameCount = 0;
  bool _isAlarmPlaying = false;
  bool _canProcess = true;
  bool _isBusy = false;

  OverlayEntry? _overlayEntry;
  static Offset _overlayPosition = const Offset(20, 100);
  bool _isInitialized = false;

  static const int _alertInterval = 3; // 알림 간격 (초)
  DateTime? _lastAlertTime;
  bool _isVibratingPlaying = false; // 진동 상태 추가

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _initializeVolume();
  }

  Future<void> _initializeVolume() async {
    try {
      // 초기 볼륨을 최대로 설정하고 시스템 UI는 표시하지 않음
      VolumeController().showSystemUI = false; // 시스템 UI 숨기기
      VolumeController().maxVolume(); // 최대 볼륨으로 설정

      // 볼륨 변경 리스너 설정
      VolumeController().listener((volume) {
        debugPrint('System volume changed: $volume');
      });
    } catch (e) {
      debugPrint('볼륨 초기화 에러: $e');
    }
  }

  Future<void> _initializeServices() async {
    try {
      if (Platform.isAndroid) {
        // 권한들을 순차적으로 요청
        await _requestPermissionsSequentially();

        // 모든 권한이 허용된 후에만 서비스 초기화 진행
        await _initializeForegroundService();
      }

      // 모든 초기화가 완료된 후에 상태 업데이트
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });

        // 상태 업데이트 후 약간의 지연을 두고 오버레이 생성
        Future.delayed(
          const Duration(milliseconds: 100),
          () {
            if (mounted) {
              _overlayEntry?.remove(); // 기존 오버레이 제거
              _createOverlay();
              _showOverlay(false);
            }
          },
        );
      }
    } catch (e) {
      debugPrint('Service initialization error: $e');
      if (mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('권한 필요'),
            content: const Text('앱 실행을 위해 모든 권한이 필요합니다.\n설정에서 권한을 허용해주세요.'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  openAppSettings();
                },
                child: const Text('설정으로 이동'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _initializeServices(); // 재시도
                },
                child: const Text('재시도'),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _requestPermissionsSequentially() async {
    if (Platform.isAndroid) {
      // 한번에 여러 권한 요청
      Map<Permission, PermissionStatus> statuses = await [
        Permission.camera,
        Permission.audio,
        Permission.notification,
      ].request();

      // 권한 결과 확인
      if (statuses.values.any((status) => status.isDenied)) {
        throw Exception('Required permissions not granted');
      }

      // 시스템 오버레이 권한 요청
      if (!await FlutterForegroundTask.canDrawOverlays) {
        await FlutterForegroundTask.openSystemAlertWindowSettings();
        // 사용자가 설정을 변경할 때까지 대기
        while (!await FlutterForegroundTask.canDrawOverlays) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      // 배터리 최적화 무시 권한 요청
      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
        while (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      // 오디오 설정 권한 요청 추가
      final audioStatus = await Permission.audio.request();
      if (audioStatus.isDenied) {
        throw Exception('Audio settings permission denied');
      }

      final cameraStatus = await Permission.camera.request();
      if (cameraStatus.isDenied) {
        throw Exception('Camera permission denied');
      }

      // 모든 권한이 허용되었는지 최종 확인
      if (await FlutterForegroundTask.checkNotificationPermission() !=
              NotificationPermission.granted ||
          !await FlutterForegroundTask.canDrawOverlays ||
          !await FlutterForegroundTask.isIgnoringBatteryOptimizations ||
          !await Permission.camera.isGranted ||
          !await Permission.audio.isGranted) {
        throw Exception('Required permissions not granted');
      }
    }
  }

  Future<void> _initializeForegroundService() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'sleep_detection',
        channelName: '졸음 감지 서비스',
        channelDescription: '졸음 감지 서비스가 실행 중입니다.',
        visibility: NotificationVisibility.VISIBILITY_PUBLIC,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: true,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: true,
        allowWakeLock: true,
      ),
    );

    if (!(await FlutterForegroundTask.isRunningService)) {
      await FlutterForegroundTask.startService(
        serviceId: 123,
        notificationTitle: '졸음 감지 서비스',
        notificationText: '졸음 감지를 시작합니다.',
        callback: startCallback,
      );
    }
  }

  void _createOverlay() {
    debugPrint('Creating overlay...');
    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: _overlayPosition.dx,
        top: _overlayPosition.dy,
        child: Material(
          color: Colors.transparent,
          child: GestureDetector(
            onPanUpdate: (details) {
              _overlayPosition += details.delta;
              _overlayEntry?.markNeedsBuild();
            },
            child: ValueListenableBuilder<bool>(
              valueListenable: _isSleepingNotifier,
              builder: (context, isSleeping, _) => Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isSleeping
                      ? Colors.red.withOpacity(0.9)
                      : Colors.blue.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Text(
                  isSleeping ? '졸음이 감지됨!' : '졸음 감지중...',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold, // 글자를 더 진하게
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // Navigator.of(context)를 사용하여 현재 context의 overlay에 접근
    final overlay = Navigator.of(context).overlay;
    if (overlay != null) {
      debugPrint('Inserting overlay...');
      overlay.insert(_overlayEntry!);
    } else {
      debugPrint('Overlay is null!');
    }
  }

  void _showOverlay(bool isSleeping) {
    _isSleepingNotifier.value = isSleeping;
  }

  Future<void> _processImage(InputImage inputImage) async {
    if (!_canProcess || _isBusy) return;
    _isBusy = true;

    try {
      final faces = await _faceDetector.processImage(inputImage);
      if (faces.isNotEmpty) {
        final face = faces.first;
        final leftEyeOpenProbability = face.leftEyeOpenProbability;
        final rightEyeOpenProbability = face.rightEyeOpenProbability;

        if (leftEyeOpenProbability != null && rightEyeOpenProbability != null) {
          _detectDrowsiness(leftEyeOpenProbability, rightEyeOpenProbability);
        }
      } else {
        _resetState();
      }
    } catch (e) {
      debugPrint('이미지 처리 에러: $e');
    } finally {
      _isBusy = false;
    }
  }

  void _detectDrowsiness(double leftEyeOpenProb, double rightEyeOpenProb) {
    final now = DateTime.now();
    final isNightTime = now.hour >= 22 || now.hour <= 5;

    // 밤시간대는 더 민감하게 감지
    final threshold =
        isNightTime ? _closedEyeThreshold * 1.2 : _closedEyeThreshold;

    if (leftEyeOpenProb < threshold && rightEyeOpenProb < threshold) {
      _closedEyeFrameCount++;

      if (_closedEyeFrameCount >= _drowsinessFrameThreshold) {
        // 알림 간격 체크
        if (_lastAlertTime == null ||
            now.difference(_lastAlertTime!).inSeconds >= _alertInterval) {
          _triggerAlert(isNightTime);
          _lastAlertTime = now;
        }
      }
    } else {
      _resetState();
    }
  }

  void _resetState() {
    _closedEyeFrameCount = 0;
    _stopAlarm();
    _stopVibration();
    _showOverlay(false);
  }

  // 상황별 알림 트리거
  Future<void> _triggerAlert(bool isNightTime) async {
    _showOverlay(true);

    try {
      // 볼륨 설정
      final volume = isNightTime ? 1.0 : 0.7;
      VolumeController().setVolume(volume, showSystemUI: false);

      // 볼륨 설정이 적용되도록 짧은 딜레이 추가
      await Future.delayed(const Duration(milliseconds: 100));

      await _triggerAlarm(); // 알람 시작
      _triggerVibration(); // 진동 시작
    } catch (e) {
      debugPrint('알림 트리거 에러: $e');
    }
    //밤시간대는 더 큰 소리로 알림
    // 볼륨 설정
    // try {
    //   final volume = isNightTime ? 1.0 : 0.7;
    //   await _audioPlayer.setVolume(volume);

    //   // 진동과 알람을 동시에 실행
    //   await Future.wait([
    //     _triggerVibration(),
    //     _triggerAlarm(),
    //   ]);
    // } catch (e) {
    //   debugPrint('알림 트리거 에러: $e');
    // }
  }

  // 진동 시작 함수
  Future<void> _triggerVibration() async {
    if (!_isVibratingPlaying) {
      _isVibratingPlaying = true;
      while (_isVibratingPlaying) {
        await Haptics.vibrate(HapticsType.heavy);
        // 진동 간격 설정
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }
  }

  // 진동 중지 함수
  void _stopVibration() {
    _isVibratingPlaying = false;
  }

  Future<void> _triggerAlarm() async {
    if (!_isAlarmPlaying) {
      _isAlarmPlaying = true;
      try {
        await _audioPlayer.play(AssetSource('alarm.wav'));

        // 반복 재생을 위한 완료 리스너
        _audioPlayer.onPlayerComplete.listen((_) {
          if (_isAlarmPlaying) {
            _audioPlayer.play(AssetSource('alarm.wav'));
          }
        });
      } catch (e) {
        debugPrint('알람 재생 에러: $e');
        _isAlarmPlaying = false;
      }
    }
  }

  Future<void> _stopAlarm() async {
    if (_isAlarmPlaying) {
      try {
        _isAlarmPlaying = false;
        await _audioPlayer.stop();
      } catch (e) {
        debugPrint('알람 중지 에러: $e');
      }
    }
  }

  @override
  void dispose() {
    _canProcess = false;
    _isSleepingNotifier.dispose();
    _faceDetector.close();
    _audioPlayer.dispose();
    _overlayEntry?.remove();
    _stopVibration();
    VolumeController().removeListener();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraView(
            onImage: _processImage,
            initialCameraLensDirection: CameraLensDirection.front,
          ),
        ],
      ),
    );
  }
}

class CameraView extends StatefulWidget {
  const CameraView({
    super.key,
    required this.onImage,
    required this.initialCameraLensDirection,
  });

  final Function(InputImage inputImage) onImage;
  final CameraLensDirection initialCameraLensDirection;

  @override
  State<CameraView> createState() => _CameraViewState();
}

// CameraView의 상태 관리 클래스
class _CameraViewState extends State<CameraView> {
  static List<CameraDescription> _cameras = []; // 사용 가능한 카메라 목록
  CameraController? _controller; // 카메라 컨트롤러
  int _cameraIndex = -1; // 현재 사용 중인 카메라 인덱스

  @override
  void initState() {
    super.initState();
    _initializeCamera(); // 카메라 초기화
  }

  // 카메라 초기화 함수
  void _initializeCamera() async {
    if (_cameras.isEmpty) {
      _cameras = await availableCameras(); // 사용 가능한 카메라 목록 가져오기
    }

    // 전면 카메라 찾기
    for (var i = 0; i < _cameras.length; i++) {
      if (_cameras[i].lensDirection == widget.initialCameraLensDirection) {
        _cameraIndex = i;
        break;
      }
    }
    if (_cameraIndex != -1) {
      _startCamera(); // 라이브 피드 시작
    }
  }

  Future<void> _startCamera() async {
    try {
      final camera = _cameras[_cameraIndex];
      _controller = CameraController(
        camera,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );

      await _controller?.initialize();
      if (!mounted) return;

      debugPrint('카메라 초기화 완료: ${camera.lensDirection}');
      await _controller?.startImageStream(_processImage);
      setState(() {});
    } catch (e) {
      debugPrint('카메라 시작 에러: $e');
    }
  }

  void _processImage(CameraImage image) {
    if (_controller == null) return;

    try {
      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage == null) return;

      // debugPrint('이미지 처리 중: ${image.width}x${image.height}');

      widget.onImage(inputImage);
    } catch (e) {
      debugPrint('이미지 처리 에러: $e');
    }
  }

  @override
  void dispose() {
    _controller?.stopImageStream();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
          // color: Colors.black, // 배경색을 검정으로 설정
          ),
    );
  }

  // 디바이스 방향별 회전 각도 매핑
  final _orientations = {
    DeviceOrientation.portraitUp: 0, // 세로 정방향 (기본)
    DeviceOrientation.landscapeLeft: 90, // 왼쪽으로 90도 회전 (가로)
    DeviceOrientation.portraitDown: 180, // 거꾸로 뒤집힘
    DeviceOrientation.landscapeRight: 270, // 오른쪽으로 90도 회전 (가로)
  };

  // 카메라 이미지를 InputImage로 변환하는 함수
  InputImage? _inputImageFromCameraImage(CameraImage image) {
    if (_controller == null) return null;

    try {
      // 플랫폼별 이미지 회전 처리
      final camera = _cameras[_cameraIndex];
      final sensorOrientation = camera.sensorOrientation;
      InputImageRotation? rotation;

      // 플랫폼별 이미지 회전 처리
      if (Platform.isIOS) {
        rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
      } else if (Platform.isAndroid) {
        // 현재 디바이스 방향에 따른 회전 각도 가져오기
        var rotationCompensation =
            _orientations[_controller!.value.deviceOrientation];
        if (rotationCompensation == null) return null;
        if (camera.lensDirection == CameraLensDirection.front) {
          // 전면 카메라일 경우의 회전 보정
          rotationCompensation =
              (sensorOrientation + rotationCompensation) % 360;
        } else {
          // 후면 카메라일 경우의 회전 보정
          rotationCompensation =
              (sensorOrientation - rotationCompensation + 360) % 360;
        }
        rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
      }
      if (rotation == null) return null;

      // 이미지 포맷 검증 및 변환
      final format = InputImageFormatValue.fromRawValue(image.format.raw);
      if (format == null ||
          (Platform.isAndroid && format != InputImageFormat.nv21) ||
          (Platform.isIOS && format != InputImageFormat.bgra8888)) return null;

      if (image.planes.length != 1) return null;
      // 이미지 평면 데이터 처리
      final plane = image.planes.first;
      final bytes = plane.bytes;

      //debugPrint('이미지 변환: ${image.width}x${image.height}, 회전: ${rotation.rawValue}');

      // 최종 InputImage 생성 및 반환
      return InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation, // used only in Android
          format: format, // used only in iOS
          bytesPerRow: plane.bytesPerRow, // used only in iOS
        ),
      );
    } catch (e) {
      debugPrint('이미지 변환 에러: $e');
      return null;
    }
  }
}
