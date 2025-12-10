import UIKit
import AVFoundation
import Vision

final class CameraViewController: UIViewController {

    // MARK: - UI

    private let gestureLabel: UILabel = {
        let label = UILabel()
        label.text = "准备中..."
        label.textColor = .white
        label.font = .systemFont(ofSize: 22, weight: .bold)
        label.textAlignment = .center
        label.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        label.layer.cornerRadius = 8
        label.layer.masksToBounds = true
        return label
    }()

    /// 调试信息显示Label（多行）
    private let debugLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        label.layer.cornerRadius = 8
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "等待识别..."
        return label
    }()
    
    /// 模式切换控件
    private let modeSegmentedControl: UISegmentedControl = {
        let control = UISegmentedControl(items: ["手势识别", "人脸跟随", "目标跟踪"])
        control.selectedSegmentIndex = 0
        control.backgroundColor = UIColor.white.withAlphaComponent(0.3)
        control.selectedSegmentTintColor = .systemYellow
        return control
    }()

    /// Debug开关状态
    private var isDebugEnabled = true

    // MARK: - Camera & Vision

    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private let videoQueue = DispatchQueue(label: "camera.video.queue")

    private lazy var handPoseRequest: VNDetectHumanHandPoseRequest = {
        let request = VNDetectHumanHandPoseRequest(completionHandler: self.handleHandPose)
        request.maximumHandCount = 1
        return request
    }()

    /// 检测模式枚举
    enum DetectionMode: Int {
        case handGesture = 0
        case faceTracking = 1
        case objectTracking = 2
    }

    private var currentMode: DetectionMode = .handGesture {
        didSet {
            // 先重置所有追踪器，防止旧模式的回调干扰
            resetTrackers()
            // 再更新UI并启动新模式所需的追踪器
            updateUIForMode()
        }
    }

    // MARK: - Detectors
    
    private var classifier = HandGestureClassifier()
    private let faceDetector = FaceDetector()
    private let objectTracker = ObjectTracker()
    
    // MARK: - Tracking UI
    
    private let trackingView = TrackingView(frame: .zero)
    
    // MARK: - 调参模式
    
    /// 调参模式开关
    private let isTuningModeEnabled = false // 默认关闭，让出空间给模式切换

    /// 统计管理器
    private let statsManager = HandGestureStatsManager()

    /// 是否正在采集样本
    private var isCollectingSamples = false

    /// 当前真实手势（用户在UI上选择的）
    private var currentGroundTruthGesture: HandGestureType = .unknown

    /// 统计更新计数器（用于控制UI更新频率）
    private var statsUpdateCounter = 0

    // MARK: - 调参UI组件

    /// 真实手势选择控件
    private let groundTruthSegmentedControl: UISegmentedControl = {
        let control = UISegmentedControl(items: ["未知", "V", "OK", "手掌", "拳头", "食指"])
        control.selectedSegmentIndex = 0
        control.backgroundColor = UIColor.white.withAlphaComponent(0.3)
        control.selectedSegmentTintColor = .systemBlue
        return control
    }()

    /// 开始/停止采集按钮
    private let collectButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("开始采集", for: .normal)
        button.backgroundColor = .systemGreen
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 8
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        return button
    }()

    /// 重置统计按钮
    private let resetButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("重置统计", for: .normal)
        button.backgroundColor = .systemOrange
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 8
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        return button
    }()

    /// 导出统计按钮
    private let exportButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("导出统计", for: .normal)
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 8
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        return button
    }()

    /// 统计展示文本区域
    private let statsTextView: UITextView = {
        let textView = UITextView()
        textView.isEditable = false
        textView.isScrollEnabled = true
        textView.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        textView.textColor = .white
        textView.font = .systemFont(ofSize: 12)
        textView.layer.cornerRadius = 8
        textView.text = "等待采集数据..."
        return textView
    }()

    /// 底部调参面板容器
    private let tuningPanelStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 12
        stackView.alignment = .fill
        stackView.distribution = .fill
        stackView.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        stackView.layer.cornerRadius = 12
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.layoutMargins = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        return stackView
    }()

    // MARK: - 时间平滑（多帧投票）

    /// 最近 N 帧的手势识别结果历史
    private var gestureHistory: [HandGestureType] = []

    /// 历史窗口大小（帧数）
    private let gestureHistoryLimit = 5

    /// 当前稳定的手势类型（经过时间平滑后的结果）
    private var stableGestureType: HandGestureType? {
        didSet {
            updateGestureLabel()
        }
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupPreviewLayer()
        setupGestureLabel()
        setupModeControl()
        setupTrackingView()
        setupDebugUI()
        setupDebugLogging()
        setupDetectors()
        
        if isTuningModeEnabled {
            setupTuningPanel()
        }
        checkCameraAuthorizationAndStart()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        trackingView.frame = view.bounds
        
        let topSafe = view.safeAreaInsets.top
        
        // 模式切换控件
        modeSegmentedControl.frame = CGRect(
            x: 16,
            y: topSafe + 10,
            width: view.bounds.width - 32,
            height: 32
        )
        
        gestureLabel.frame = CGRect(
            x: 16,
            y: modeSegmentedControl.frame.maxY + 16,
            width: view.bounds.width - 32,
            height: 44
        )
        
        // 布局debugLabel（在gestureLabel下方）
        if isDebugEnabled {
            debugLabel.frame = CGRect(
                x: 16,
                y: gestureLabel.frame.maxY + 8,
                width: view.bounds.width - 32,
                height: min(120, view.bounds.height - gestureLabel.frame.maxY - 200)
            )
        }
        
        if isTuningModeEnabled {
            layoutTuningPanel()
        }
    }
    
    private func setupModeControl() {
        view.addSubview(modeSegmentedControl)
        modeSegmentedControl.addTarget(self, action: #selector(modeChanged(_:)), for: .valueChanged)
    }
    
    private func setupTrackingView() {
        view.addSubview(trackingView)
    }
    
    private func setupDetectors() {
        // 配置人脸检测回调
        faceDetector.onFaceDetected = { [weak self] normalizedRect in
            guard let self = self else { return }
            // print("Face detected at: \(normalizedRect)")
            DispatchQueue.main.async {
                // 使用 previewLayer 将归一化坐标转换为视图坐标
                // 这能自动处理 videoGravity (如 .resizeAspectFill) 带来的裁剪和缩放偏移
                let convertedRect = self.previewLayer.layerRectConverted(fromMetadataOutputRect: normalizedRect)
                
                // 人脸跟随使用黄色虚线框
                self.trackingView.updateTrackingRect(convertedRect, color: .yellow, isDashed: true, isNormalized: false)
                self.gestureLabel.text = "检测到人脸"
            }
        }
        
        faceDetector.onNoFaceDetected = { [weak self] in
            // print("No face detected")
            DispatchQueue.main.async {
                // 未检测到人脸时，显示红色中心框（搜索状态）
                let centerRect = CGRect(x: 0.25, y: 0.35, width: 0.5, height: 0.3)
                self?.trackingView.updateTrackingRect(centerRect, color: .red, isDashed: false)
                self?.gestureLabel.text = "未检测到人脸"
            }
        }
        
        // 配置目标跟踪回调
        objectTracker.onTrackingUpdate = { [weak self] rect in
            guard let self = self else { return }
            DispatchQueue.main.async {
                // rect：0~1 的归一化元数据坐标（原点左上）
                // 使用 previewLayer 转成视图坐标，自动处理裁剪/比例
                let convertedRect = self.previewLayer.layerRectConverted(fromMetadataOutputRect: rect)
                self.trackingView.updateTrackingRect(convertedRect,
                                                     color: .green,
                                                     isDashed: false,
                                                     isNormalized: false)
                self.gestureLabel.text = "正在跟踪目标"
            }
        }
        
        objectTracker.onTrackingLost = { [weak self] in
            DispatchQueue.main.async {
                self?.trackingView.clear()
                self?.gestureLabel.text = "目标丢失或未选择 (点击屏幕选择)"
            }
        }
    }
    
    @objc private func modeChanged(_ sender: UISegmentedControl) {
        guard let mode = DetectionMode(rawValue: sender.selectedSegmentIndex) else { return }
        print("Mode Changed to: \(mode)")
        currentMode = mode
    }
    
    private func updateUIForMode() {
        print("Updating UI for mode: \(currentMode)")
        trackingView.clear()
        
        switch currentMode {
        case .handGesture:
            gestureLabel.text = "请把手伸到镜头前"
            gestureLabel.isHidden = false
            debugLabel.isHidden = !isDebugEnabled
            if isTuningModeEnabled { tuningPanelStackView.isHidden = false }
            
        case .faceTracking:
            gestureLabel.text = "正在初始化人脸检测..."
            gestureLabel.isHidden = false
            debugLabel.isHidden = true
            if isTuningModeEnabled { tuningPanelStackView.isHidden = true }
            print("Starting face detector...")
            faceDetector.start()
            
        case .objectTracking:
            gestureLabel.text = "请点击屏幕选择跟踪目标"
            gestureLabel.isHidden = false
            debugLabel.isHidden = true
            if isTuningModeEnabled { tuningPanelStackView.isHidden = true }
        }
    }
    
    private func resetTrackers() {
        faceDetector.stop()
        objectTracker.stop()
    }
    
    // MARK: - Touch Handling
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard currentMode == .objectTracking, let touch = touches.first else { return }

        let location = touch.location(in: view)

        // 在视图坐标系中，以点击点为中心创建一个 100x100 的正方形框
        let boxSize: CGFloat = 100
        let boxRectInView = CGRect(
            x: location.x - boxSize / 2,
            y: location.y - boxSize / 2,
            width: boxSize,
            height: boxSize
        )

        // 通过 previewLayer 转成 0~1 的元数据坐标，供 Vision 跟踪使用
        let metadataRect = previewLayer.metadataOutputRectConverted(fromLayerRect: boxRectInView)

        // 用元数据坐标启动目标跟踪
        objectTracker.initializeTracking(with: metadataRect)

        // 在屏幕上立即画出用户选中的正方形框（这里使用的是视图坐标，所以 isNormalized = false）
        trackingView.updateTrackingRect(boxRectInView,
                                        color: .green,
                                        isDashed: false,
                                        isNormalized: false)
        gestureLabel.text = "目标已选择，开始跟踪"
    }

    // MARK: - Setup UI

    private func setupPreviewLayer() {
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.insertSublayer(previewLayer, at: 0)
    }

    private func setupGestureLabel() {
        view.addSubview(gestureLabel)
    }

    /// 设置调试UI
    private func setupDebugUI() {
        view.addSubview(debugLabel)
        debugLabel.isHidden = !isDebugEnabled

        // 添加Debug开关按钮（右上角）
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Debug",
            style: .plain,
            target: self,
            action: #selector(toggleDebug)
        )
    }

    /// 设置调参面板UI
    private func setupTuningPanel() {
        view.addSubview(tuningPanelStackView)

        // 添加手势选择控件
        tuningPanelStackView.addArrangedSubview(groundTruthSegmentedControl)
        groundTruthSegmentedControl.addTarget(self, action: #selector(groundTruthChanged(_:)), for: .valueChanged)

        // 添加按钮容器
        let buttonStackView = UIStackView()
        buttonStackView.axis = .horizontal
        buttonStackView.spacing = 8
        buttonStackView.distribution = .fillEqually

        buttonStackView.addArrangedSubview(collectButton)
        buttonStackView.addArrangedSubview(resetButton)
        buttonStackView.addArrangedSubview(exportButton)

        collectButton.addTarget(self, action: #selector(collectButtonTapped), for: .touchUpInside)
        resetButton.addTarget(self, action: #selector(resetButtonTapped), for: .touchUpInside)
        exportButton.addTarget(self, action: #selector(exportButtonTapped), for: .touchUpInside)

        tuningPanelStackView.addArrangedSubview(buttonStackView)

        // 添加统计文本区域
        tuningPanelStackView.addArrangedSubview(statsTextView)
        statsTextView.heightAnchor.constraint(equalToConstant: 150).isActive = true
    }

    /// 布局调参面板
    private func layoutTuningPanel() {
        let bottomSafe = view.safeAreaInsets.bottom
        let panelHeight: CGFloat = 280
        tuningPanelStackView.frame = CGRect(
            x: 16,
            y: view.bounds.height - panelHeight - bottomSafe - 16,
            width: view.bounds.width - 32,
            height: panelHeight
        )
    }

    // MARK: - Debug 设置

    /// 设置调试日志输出（仅在 DEBUG 模式下启用）
    private func setupDebugLogging() {
        #if DEBUG
        classifier.debugLogHandler = { message in
            print("[HandGestureDebug]", message)
        }
        #endif

        // 设置调试信息回调，用于UI显示
        classifier.debugInfoHandler = { [weak self] info in
            DispatchQueue.main.async {
                self?.updateDebugUI(with: info)
            }
        }
    }

    /// 切换Debug显示
    @objc private func toggleDebug() {
        isDebugEnabled.toggle()
        debugLabel.isHidden = !isDebugEnabled

        if isDebugEnabled {
            classifier.debugInfoHandler = { [weak self] info in
                DispatchQueue.main.async {
                    self?.updateDebugUI(with: info)
                }
            }
        } else {
            classifier.debugInfoHandler = nil
        }
    }

    /// 更新调试UI显示
    private func updateDebugUI(with info: HandGestureClassifier.HandGestureDebugInfo) {
        guard isDebugEnabled else { return }

        var lines: [String] = []
        lines.append("Gesture: \(info.gesture.rawValue)")
        lines.append("Scores: V/OK/Palm/Fist/Idx = \(info.scoreV)/\(info.scoreOK)/\(info.scorePalm)/\(info.scoreFist)/\(info.scoreIndexFinger)")
        lines.append("gaps: thumb-idx=\(String(format: "%.3f", info.gapThumbIndex)), idx-mid=\(String(format: "%.3f", info.gapIndexMiddle))")
        lines.append("ratios: idx/mid=\(String(format: "%.2f", info.indexToMiddleRatio)), ring/mid=\(String(format: "%.2f", info.ringToMiddleRatio))")
        lines.append("straightCount = \(info.straightCount)")

        debugLabel.text = lines.joined(separator: "\n")
    }

    // MARK: - Camera

    private func checkCameraAuthorizationAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCaptureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.setupCaptureSession()
                    } else {
                        self.gestureLabel.text = "相机权限被拒绝"
                    }
                }
            }
        default:
            gestureLabel.text = "无相机权限，请在设置中开启"
        }
    }

    private func setupCaptureSession() {
        captureSession.beginConfiguration()

        // 分辨率你也可以换成 .hd1280x720 保持性能
        if captureSession.canSetSessionPreset(.high) {
            captureSession.sessionPreset = .high
        }

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                 for: .video,
                                                 position: .front),
            let input = try? AVCaptureDeviceInput(device: device),
            captureSession.canAddInput(input)
        else {
            gestureLabel.text = "无法打开相机"
            captureSession.commitConfiguration()
            return
        }
        captureSession.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: videoQueue)

        if captureSession.canAddOutput(output) {
            captureSession.addOutput(output)
        }

        if let conn = output.connection(with: .video) {
            if conn.isVideoOrientationSupported {
                conn.videoOrientation = .portrait
            }
            // 不要在这里设置 isVideoMirrored，让 Vision 处理原始数据
            // if conn.isVideoMirroringSupported {
            //    conn.isVideoMirrored = true
            // }
        }

        captureSession.commitConfiguration()

        // startRunning 应该在后台线程执行，避免阻塞主线程
        videoQueue.async { [weak self] in
            self?.captureSession.startRunning()
        }
    }

    // MARK: - Vision 处理
    
    private func processSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        switch currentMode {
        case .handGesture:
            let handler = VNImageRequestHandler(
                cvPixelBuffer: pixelBuffer,
                orientation: .upMirrored,    // 前置 + 镜像
                options: [:]
            )
            do {
                try handler.perform([handPoseRequest])
            } catch {
                print("Vision perform error: \(error)")
            }
            
        case .faceTracking:
            // 使用 .leftMirrored 方向，适配前置摄像头竖屏的常见方向
             if Int.random(in: 0...60) == 0 { print("Processing face detection frame...") }
            faceDetector.detectFaces(in: pixelBuffer, orientation: .leftMirrored)
            
        case .objectTracking:
            objectTracker.trackObject(in: pixelBuffer)
        }
    }

    private func handleHandPose(request: VNRequest, error: Error?) {
        if let error = error {
            print("Hand pose request error: \(error)")
            return
        }

        guard let results = request.results as? [VNHumanHandPoseObservation],
              let observation = results.first
        else {
            // 连续多帧没有检测到手，清空历史并重置稳定手势
            clearGestureHistory()
            return
        }

        // 优先使用 classifyWithFeatures 获取完整结果（包含特征向量）
        guard let result = classifier.classifyWithFeatures(from: observation) else {
            clearGestureHistory()
            return
        }

        // 原有UI显示逻辑使用预测结果
        updateStableGesture(with: result.predicted)

        // 如果满足采集条件，记录样本
        if isTuningModeEnabled && isCollectingSamples && currentGroundTruthGesture != .unknown {
            statsManager.recordSample(
                groundTruth: currentGroundTruthGesture,
                predicted: result.predicted,
                features: result.features
            )

            // 每30帧更新一次统计文本（避免UI抖动）
            statsUpdateCounter += 1
            if statsUpdateCounter >= 30 {
                statsUpdateCounter = 0
                DispatchQueue.main.async { [weak self] in
                    self?.refreshStatsText()
                }
            }
        }
    }

    // MARK: - 手势平滑 & UI

    /// 更新稳定手势（基于滑动窗口的众数统计）
    /// - Parameter newGesture: 新识别到的手势
    private func updateStableGesture(with newGesture: HandGestureType) {
        // 将新手势添加到历史窗口
        gestureHistory.append(newGesture)

        // 保持历史窗口大小
        if gestureHistory.count > gestureHistoryLimit {
            gestureHistory.removeFirst()
        }

        // 统计众数（出现次数最多的手势）
        let counts = Dictionary(grouping: gestureHistory, by: { $0 })
            .mapValues { $0.count }

        guard let (mostFrequentGesture, count) = counts.max(by: { $0.value < $1.value }) else {
            stableGestureType = .unknown
            return
        }

        // 计算该手势在历史窗口中的占比
        let ratio = Double(count) / Double(gestureHistory.count)

        // 根据手势类型应用不同的稳定性阈值
        // OK 手势要求更严格（90%），其他手势相对宽松（75%）
        let threshold: Double
        switch mostFrequentGesture {
        case .okSign:
            threshold = 0.9  // OK 手势需要 90% 的帧一致才算稳定
        case .vSign, .palm:
            threshold = 0.75  // V 手势和张开手掌需要 75% 的帧一致
        case .fist, .indexFinger:
            threshold = 0.75  // 拳头和食指需要 75% 的帧一致
        default:
            threshold = 0.0  // unknown 或其他未处理手势
        }

        // 只有当占比超过阈值时，才认为手势稳定
        if ratio >= threshold {
            stableGestureType = mostFrequentGesture
        } else {
            stableGestureType = .unknown
        }
    }

    /// 清空手势历史（当连续多帧检测不到手时调用）
    private func clearGestureHistory() {
        gestureHistory.removeAll()
        stableGestureType = .unknown
    }

    /// 更新 UI 显示（在主线程执行）
    private func updateGestureLabel() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            switch self.stableGestureType {
            case .vSign:
                self.gestureLabel.text = "识别到：✌️ V 手势"
            case .okSign:
                self.gestureLabel.text = "识别到：👌 OK 手势"
            case .palm:
                self.gestureLabel.text = "识别到：🖐 手掌张开"
            case .fist:
                self.gestureLabel.text = "识别到：✊ 拳头"
            case .indexFinger:
                self.gestureLabel.text = "识别到：☝️ 食指"
            default:
                self.gestureLabel.text = "请把手伸到镜头前"
            }
        }
    }

    // MARK: - 调参UI事件处理

    /// 真实手势选择改变
    @objc private func groundTruthChanged(_ sender: UISegmentedControl) {
        switch sender.selectedSegmentIndex {
        case 0:
            currentGroundTruthGesture = .unknown
        case 1:
            currentGroundTruthGesture = .vSign
        case 2:
            currentGroundTruthGesture = .okSign
        case 3:
            currentGroundTruthGesture = .palm
        case 4:
            currentGroundTruthGesture = .fist
        case 5:
            currentGroundTruthGesture = .indexFinger
        default:
            currentGroundTruthGesture = .unknown
        }
        refreshStatsText()
    }

    /// 采集按钮点击
    @objc private func collectButtonTapped() {
        isCollectingSamples.toggle()
        if isCollectingSamples {
            collectButton.setTitle("停止采集", for: .normal)
            collectButton.backgroundColor = .systemRed
            statsUpdateCounter = 0
        } else {
            collectButton.setTitle("开始采集", for: .normal)
            collectButton.backgroundColor = .systemGreen
            refreshStatsText()
        }
    }

    /// 重置按钮点击
    @objc private func resetButtonTapped() {
        statsManager.reset()
        statsUpdateCounter = 0
        refreshStatsText()
    }

    /// 导出按钮点击
    @objc private func exportButtonTapped() {
        let summary = statsManager.debugSummaryText()
        print("\n" + summary + "\n")
        refreshStatsText()
    }

    /// 刷新统计文本显示
    private func refreshStatsText() {
        guard currentGroundTruthGesture != .unknown else {
            statsTextView.text = "请先选择真实手势类型"
            return
        }

        let count = statsManager.sampleCount(for: currentGroundTruthGesture)
        guard count > 0 else {
            statsTextView.text = "当前手势：\(currentGroundTruthGesture.rawValue)\n样本帧数：0\n\n等待采集数据..."
            return
        }

        var lines: [String] = []
        lines.append("当前手势：\(currentGroundTruthGesture.rawValue)")
        lines.append("样本帧数：\(count)")
        lines.append("")

        // 显示关键特征的统计（3-5个最重要的）
        let keyFeatures: [(String, KeyPath<HandGestureClassifier.HandGestureFeatureVector, CGFloat>)] = [
            ("thumbIndexGap", \HandGestureClassifier.HandGestureFeatureVector.thumbIndexGap),
            ("indexMiddleGap", \HandGestureClassifier.HandGestureFeatureVector.indexMiddleGap),
            ("lenIndex", \HandGestureClassifier.HandGestureFeatureVector.lenIndex),
            ("lenMiddle", \HandGestureClassifier.HandGestureFeatureVector.lenMiddle),
            ("thumbIndexGapNorm", \HandGestureClassifier.HandGestureFeatureVector.thumbIndexGapNorm)
        ]

        for (name, keyPath) in keyFeatures {
            if let stats = statsManager.stats(for: currentGroundTruthGesture, feature: keyPath) {
                lines.append("\(name):")
                lines.append("  mean=\(String(format: "%.3f", stats.mean))")
                lines.append("  min=\(String(format: "%.3f", stats.min))")
                lines.append("  max=\(String(format: "%.3f", stats.max))")
                lines.append("")
            }
        }

        statsTextView.text = lines.joined(separator: "\n")
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        processSampleBuffer(sampleBuffer)
    }
}
