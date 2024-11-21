# foreground_mlkit_camera

A new Flutter project.



1. 앱 실행 초기 순서:
    main() → 권한 요청 → 포그라운드 서비스 시작 → 카메라 초기화
2. 포그라운드 서비스 시작:
    startCallback() → SleepDetectionHandler 생성
        - onStart(): 서비스 시작 초기화
3. 반복적으로 실행되는 핵심 부분:
    // 1. 카메라 스트림에서 지속적으로 이미지 캡처
        CameraView._processImage()
        ↓
    // 2. 얼굴 감지 및 눈 상태 분석
        _FaceDetectorViewState._processImage()
        ↓
    // 3. 졸음 상태 확인
        _detectDrowsiness()
        ↓
    // 4. 졸음 감지시:
        _showOverlay(true) 
            → FlutterForegroundTask.sendDataToTask() // UI에서 서비스로 상태 전송
            → SleepDetectionHandler.onRepeatEvent() // 서비스에서 주기적으로 상태 체크
            → FlutterForegroundTask.sendDataToMain() // 서비스에서 UI로 알림 요청
            → _triggerAlert() // 알람/진동 실행

//----------------------------------------------------------------------------------------
1. 앱 시작 및 초기화
    main() → MyApp → FaceDetectorView → _FaceDetectorViewState.initState()
        main()에서 가장 먼저 실행되는 작업:
            WidgetsFlutterBinding.ensureInitialized(): Flutter 엔진 초기화
            FlutterForegroundTask.init(): 포그라운드 서비스 설정 초기화
            FlutterForegroundTask.initCommunicationPort(): UI와 서비스 간 통신 채널 설정
        FaceDetectorView 생성 시:
            _initializeServices() 호출
            _initializeVolume() 호출
            _initializeServiceCommunication() 호출

2. 권한 요청 프로세스
    _initializeServices() → _requestPermissionsSequentially()
    필요한 권한들: 카메라 권한, 오디오 권한, 알림 권한, 시스템 오버레이 권한, 배터리 최적화 제외 권한

3. 포그라운드 서비스 시작
    _initializeForegroundService() → FlutterForegroundTask.startService() → startCallback() → SleepDetectionHandler
        서비스 시작 시:
            startCallback()이 새로운 isolate에서 실행됨
            SleepDetectionHandler 인스턴스 생성
            onStart() 메서드 호출
        SleepDetectionHandler 상태:
            _isServiceRunning: 서비스 실행 상태
            _isDrowsinessDetected: 졸음 감지 상태
            _lastAlertTime: 마지막 알림 시간

4. UI와 서비스 간 통신 설정
    _initializeServiceCommunication() → FlutterForegroundTask.addTaskDataCallback()
        양방향 통신:
            UI → 서비스: FlutterForegroundTask.sendDataToTask()
            서비스 → UI: FlutterForegroundTask.sendDataToMain()

5. 졸음 감지 프로세스
    CameraView._processImage() → _FaceDetectorViewState._processImage() → _detectDrowsiness() → _showOverlay()/_triggerAlert()
        졸음 감지 시:
            _showOverlay(true) 호출
            UI에 상태 표시
            서비스에 상태 전달 (sendDataToTask)
        서비스에서 알림 트리거:
            onRepeatEvent()에서 상태 체크
            조건 만족 시 UI에 알림 요청 (sendDataToMain)

6. 알림 처리
    SleepDetectionHandler.onRepeatEvent() → UI._triggerAlert() → _triggerAlarm() + _triggerVibration()
        서비스에서 UI로 알림 요청 시:
            시간대 확인 (주간/야간)
            알림 간격 확인
            볼륨, 진동, 알람 처리