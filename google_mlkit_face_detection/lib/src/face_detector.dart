import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' as services;
import 'package:google_mlkit_commons/google_mlkit_commons.dart';

/// A face detector that detects faces in a given [InputImage].
class FaceDetector {
  static const services.MethodChannel _channel =
      services.MethodChannel('google_mlkit_face_detector');

  /// 얼굴 감지기 옵션 설정
  final FaceDetectorOptions options;

  /// 각 감지기 인스턴스의 고유 ID (현재 시간의 마이크로초)
  final id = DateTime.now().microsecondsSinceEpoch.toString();

  FaceDetector({required this.options});

  /// 이미지에서 얼굴을 감지하는 메서드
  Future<List<Face>> processImage(InputImage inputImage) async {
    // Native 코드로 얼굴 감지 요청
    final result = await _channel.invokeListMethod<dynamic>(
        'vision#startFaceDetector', <String, dynamic>{
      'options': options.toJson(),
      'id': id,
      'imageData': inputImage.toJson(),
    });

    // 감지된 얼굴들을 Face 객체 리스트로 변환
    final List<Face> faces = <Face>[];
    for (final dynamic json in result!) {
      faces.add(Face.fromJson(json));
    }

    return faces;
  }

  Future<void> close() =>
      _channel.invokeMethod<void>('vision#closeFaceDetector', {'id': id});
}

/// 얼굴 감지기 설정 옵션 클래스
class FaceDetectorOptions {
  FaceDetectorOptions({
    this.enableClassification = false,

    /// 얼굴 특징 분류 활성화 (눈 뜸/감김, 웃음 등)
    this.enableLandmarks = false,

    /// 얼굴 특징점 감지 활성화 (눈, 코, 입 등의 위치)
    this.enableContours = false,

    /// 얼굴 윤곽선 감지 활성화
    this.enableTracking = false,

    /// 얼굴 추적 기능 활성화 must be between 0.0 and 1.0, inclusive.
    this.minFaceSize = 0.1,

    /// 최소 감지 얼굴 크기 (전체 이미지 대비 비율)
    this.performanceMode = FaceDetectorMode.fast,

    /// 성능 모드 설정
  })  : assert(minFaceSize >= 0.0),
        assert(minFaceSize <= 1.0);

  final bool enableClassification;
  final bool enableLandmarks;
  final bool enableContours;
  final bool enableTracking;
  final double minFaceSize;
  final FaceDetectorMode performanceMode;

  /// 옵션을 JSON 형태로 변환
  Map<String, dynamic> toJson() => {
        'enableClassification': enableClassification,
        'enableLandmarks': enableLandmarks,
        'enableContours': enableContours,
        'enableTracking': enableTracking,
        'minFaceSize': minFaceSize,
        'mode': performanceMode.name,
      };
}

/// 감지된 얼굴 정보를 담는 클래스
class Face {
  /// 얼굴이 위치한 사각형 영역
  final Rect boundingBox;

  /// 얼굴의 회전 각도 (X축: 상하 고개 움직임)
  final double? headEulerAngleX;

  /// 얼굴의 회전 각도 (Y축: 좌우 고개 움직임)
  final double? headEulerAngleY;

  /// 얼굴의 회전 각도 (Z축: 목 기울임)
  final double? headEulerAngleZ;

  /// 왼쪽 눈 뜬 정도 (0.0 ~ 1.0)
  final double? leftEyeOpenProbability;

  /// 오른쪽 눈 뜬 정도 (0.0 ~ 1.0)
  final double? rightEyeOpenProbability;

  /// 웃고 있는 정도 (0.0 ~ 1.0)
  final double? smilingProbability;

  /// 얼굴 추적 ID (추적 기능 활성화시)
  final int? trackingId;

  /// 얼굴 특징점 정보 (눈, 코, 입 등의 위치)
  final Map<FaceLandmarkType, FaceLandmark?> landmarks;

  /// 얼굴 윤곽선 정보
  final Map<FaceContourType, FaceContour?> contours;

  Face({
    required this.boundingBox,
    required this.landmarks,
    required this.contours,
    this.headEulerAngleX,
    this.headEulerAngleY,
    this.headEulerAngleZ,
    this.leftEyeOpenProbability,
    this.rightEyeOpenProbability,
    this.smilingProbability,
    this.trackingId,
  });

  /// JSON 데이터로부터 Face 객체 생성
  factory Face.fromJson(Map<dynamic, dynamic> json) => Face(
        boundingBox: RectJson.fromJson(json['rect']),
        headEulerAngleX: json['headEulerAngleX'],
        headEulerAngleY: json['headEulerAngleY'],
        headEulerAngleZ: json['headEulerAngleZ'],
        leftEyeOpenProbability: json['leftEyeOpenProbability'],
        rightEyeOpenProbability: json['rightEyeOpenProbability'],
        smilingProbability: json['smilingProbability'],
        trackingId: json['trackingId'],
        landmarks: Map<FaceLandmarkType, FaceLandmark?>.fromIterables(
            FaceLandmarkType.values,
            FaceLandmarkType.values.map((FaceLandmarkType type) {
          final List<dynamic>? pos = json['landmarks'][type.name];
          return (pos == null)
              ? null
              : FaceLandmark(
                  type: type,
                  position: Point<int>(pos[0].toInt(), pos[1].toInt()),
                );
        })),
        contours: Map<FaceContourType, FaceContour?>.fromIterables(
            FaceContourType.values,
            FaceContourType.values.map((FaceContourType type) {
          /// added empty map to pass the tests
          final List<dynamic>? arr =
              (json['contours'] ?? <String, dynamic>{})[type.name];
          return (arr == null)
              ? null
              : FaceContour(
                  type: type,
                  points: arr
                      .map<Point<int>>((dynamic pos) =>
                          Point<int>(pos[0].toInt(), pos[1].toInt()))
                      .toList(),
                );
        })),
      );
}

/// 얼굴의 특정 부위 위치 정보
class FaceLandmark {
  /// 특징점 종류 (눈, 코, 입 등)
  final FaceLandmarkType type;

  /// 특징점의 2D 좌표
  final Point<int> position;

  FaceLandmark({required this.type, required this.position});
}

/// 얼굴 윤곽선 정보
class FaceContour {
  /// 윤곽선 종류
  final FaceContourType type;

  /// 윤곽선을 구성하는 점들의 좌표 목록
  final List<Point<int>> points;

  FaceContour({required this.type, required this.points});
}

/// 얼굴 감지 성능 모드
enum FaceDetectorMode {
  accurate, // 정확도 우선
  fast, // 속도 우선
}

/// Available face landmarks detected by [FaceDetector].
enum FaceLandmarkType {
  bottomMouth,
  rightMouth,
  leftMouth,
  rightEye,
  leftEye,
  rightEar,
  leftEar,
  rightCheek,
  leftCheek,
  noseBase,
}

/// Available face contour types detected by [FaceDetector].
enum FaceContourType {
  face,
  leftEyebrowTop,
  leftEyebrowBottom,
  rightEyebrowTop,
  rightEyebrowBottom,
  leftEye,
  rightEye,
  upperLipTop,
  upperLipBottom,
  lowerLipTop,
  lowerLipBottom,
  noseBridge,
  noseBottom,
  leftCheek,
  rightCheek
}
