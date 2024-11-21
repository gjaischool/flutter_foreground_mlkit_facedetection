// import 'dart:io'; // 파일 및 플랫폼 관련 기능 사용
// import 'package:camera/camera.dart'; // 카메라 기능 사용
// import 'package:flutter/material.dart'; // Flutter 머티리얼 디자인 위젯
// import 'package:flutter/services.dart'; // 플랫폼 서비스 관련 기능

// import 'package:google_mlkit_commons/google_mlkit_commons.dart'; // ML Kit 공통 기능

// class CameraView extends StatefulWidget {
//   const CameraView(
//       {super.key,
//       required this.onImage, // 이미지 처리 콜백
//       required this.initialCameraLensDirection // 초기 카메라 렌즈 방향
//       });

//   // 클래스 멤버 변수들 정의
//   final Function(InputImage inputImage) onImage;
//   final CameraLensDirection initialCameraLensDirection;
//   @override
//   State<CameraView> createState() => _CameraViewState();
// }

// // CameraView의 상태 관리 클래스
// class _CameraViewState extends State<CameraView> {
//   static List<CameraDescription> _cameras = []; // 사용 가능한 카메라 목록
//   CameraController? _controller; // 카메라 컨트롤러
//   int _cameraIndex = -1; // 현재 사용 중인 카메라 인덱스

//   @override
//   void initState() {
//     super.initState();
//     _initializeCamera(); // 카메라 초기화
//   }

//   // 카메라 초기화 함수
//   void _initializeCamera() async {
//     if (_cameras.isEmpty) {
//       _cameras = await availableCameras(); // 사용 가능한 카메라 목록 가져오기
//     }

//     // 전면 카메라 찾기
//     for (var i = 0; i < _cameras.length; i++) {
//       if (_cameras[i].lensDirection == widget.initialCameraLensDirection) {
//         _cameraIndex = i;
//         break;
//       }
//     }
//     if (_cameraIndex != -1) {
//       _startCamera(); // 라이브 피드 시작
//     }
//   }

//   Future<void> _startCamera() async {
//     try {
//       final camera = _cameras[_cameraIndex];
//       _controller = CameraController(
//         camera,
//         ResolutionPreset.medium, // low에서 medium으로 변경
//         enableAudio: false,
//         imageFormatGroup: Platform.isAndroid
//             ? ImageFormatGroup.nv21
//             : ImageFormatGroup.bgra8888,
//       );

//       await _controller?.initialize();
//       if (!mounted) return;

//       debugPrint('카메라 초기화 완료: ${camera.lensDirection}');
//       await _controller?.startImageStream(_processImage);
//       setState(() {});
//     } catch (e) {
//       debugPrint('카메라 시작 에러: $e');
//     }
//   }

//   void _processImage(CameraImage image) {
//     if (_controller == null) return;

//     try {
//       final inputImage = _inputImageFromCameraImage(image);
//       if (inputImage == null) return;

//       // debugPrint('이미지 처리 중: ${image.width}x${image.height}');

//       widget.onImage(inputImage);
//     } catch (e) {
//       debugPrint('이미지 처리 에러: $e');
//     }
//   }

//   @override
//   void dispose() {
//     _controller?.stopImageStream();
//     _controller?.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       body: Container(
//         color: Colors.black, // 배경색을 검정으로 설정
//       ),
//     );
//   }

//   // 디바이스 방향별 회전 각도 매핑
//   final _orientations = {
//     DeviceOrientation.portraitUp: 0, // 세로 정방향 (기본)
//     DeviceOrientation.landscapeLeft: 90, // 왼쪽으로 90도 회전 (가로)
//     DeviceOrientation.portraitDown: 180, // 거꾸로 뒤집힘
//     DeviceOrientation.landscapeRight: 270, // 오른쪽으로 90도 회전 (가로)
//   };

//   // 카메라 이미지를 InputImage로 변환하는 함수
//   InputImage? _inputImageFromCameraImage(CameraImage image) {
//     if (_controller == null) return null;

//     try {
//       // 플랫폼별 이미지 회전 처리
//       final camera = _cameras[_cameraIndex];
//       final sensorOrientation = camera.sensorOrientation;
//       InputImageRotation? rotation;

//       // 플랫폼별 이미지 회전 처리
//       if (Platform.isIOS) {
//         rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
//       } else if (Platform.isAndroid) {
//         // 현재 디바이스 방향에 따른 회전 각도 가져오기
//         var rotationCompensation =
//             _orientations[_controller!.value.deviceOrientation];
//         if (rotationCompensation == null) return null;
//         if (camera.lensDirection == CameraLensDirection.front) {
//           // 전면 카메라일 경우의 회전 보정
//           rotationCompensation =
//               (sensorOrientation + rotationCompensation) % 360;
//         } else {
//           // 후면 카메라일 경우의 회전 보정
//           rotationCompensation =
//               (sensorOrientation - rotationCompensation + 360) % 360;
//         }
//         rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
//       }
//       if (rotation == null) return null;

//       // 이미지 포맷 검증 및 변환
//       final format = InputImageFormatValue.fromRawValue(image.format.raw);
//       if (format == null ||
//           (Platform.isAndroid && format != InputImageFormat.nv21) ||
//           (Platform.isIOS && format != InputImageFormat.bgra8888)) return null;

//       if (image.planes.length != 1) return null;
//       // 이미지 평면 데이터 처리
//       final plane = image.planes.first;
//       final bytes = plane.bytes;

//       //debugPrint('이미지 변환: ${image.width}x${image.height}, 회전: ${rotation.rawValue}');

//       // 최종 InputImage 생성 및 반환
//       return InputImage.fromBytes(
//         bytes: bytes,
//         metadata: InputImageMetadata(
//           size: Size(image.width.toDouble(), image.height.toDouble()),
//           rotation: rotation, // used only in Android
//           format: format, // used only in iOS
//           bytesPerRow: plane.bytesPerRow, // used only in iOS
//         ),
//       );
//     } catch (e) {
//       debugPrint('이미지 변환 에러: $e');
//       return null;
//     }
//   }
// }
