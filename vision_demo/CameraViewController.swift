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
    
    /// 置信度进度条
    private let confidenceProgressView: UIProgressView = {
        let progress = UIProgressView(progressViewStyle: .default)
        progress.progressTintColor = .systemGreen
        progress.trackTintColor = UIColor.white.withAlphaComponent(0.3)
        progress.progress = 0.0
        progress.layer.cornerRadius = 4
        progress.clipsToBounds = true
        return progress
    }()

    /// 调试信息容器（结构化显示）
    private let debugContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        view.layer.cornerRadius = 8
        view.layer.masksToBounds = true
        return view
    }()
    
    /// 调试信息标签组
    private let debugStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 4
        stack.alignment = .leading
        stack.distribution = .fill
        return stack
    }()
    
    /// 调试信息显示Label（多行）- 保留用于向后兼容
    private let debugLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        label.layer.cornerRadius = 8
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "等待识别..."
        label.isHidden = true  // 使用新的结构化显示
        return label
    }()
    
    /// 模式切换控件
    private let modeSegmentedControl: UISegmentedControl = {
        #if DEBUG
        let control = UISegmentedControl(items: ["手势识别", "人脸跟随", "目标跟踪", "统计标定"])
        #else
        let control = UISegmentedControl(items: ["手势识别", "人脸跟随", "目标跟踪"])
        #endif
        control.selectedSegmentIndex = 0
        control.backgroundColor = UIColor.white.withAlphaComponent(0.3)
        control.selectedSegmentTintColor = .systemYellow
        return control
    }()

    /// Debug开关状态
    #if DEBUG
    private var isDebugEnabled = true
    private let showDebugInfo = true
    #else
    private var isDebugEnabled = false
    private let showDebugInfo = false
    #endif

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
        #if DEBUG
        case calibration = 3
        #endif
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
    
    // MARK: - 标定模式UI
    
    /// 标定会话
    private var calibrationSession: CalibrationSession?
    
    /// 手势选择控件（标定模式）
    private let calibrationGestureControl: UISegmentedControl = {
        let items = ["V", "OK", "Palm", "Fist", "Index"]
        let control = UISegmentedControl(items: items)
        control.selectedSegmentIndex = 0
        control.backgroundColor = UIColor.white.withAlphaComponent(0.5)
        control.selectedSegmentTintColor = .systemBlue
        control.isHidden = true
        return control
    }()
    
    /// 采样按钮
    private let samplingButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("开始采样", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        button.backgroundColor = .systemGreen
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 8
        button.isHidden = true
        return button
    }()
    
    /// 导出数据按钮（标定模式）
    private let exportDataButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("导出数据", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 8
        button.isHidden = true
        return button
    }()
    
    /// 采样状态标签
    private let samplingStatusLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .white
        label.textAlignment = .center
        label.text = "当前：-- / 已采集：0 样本"
        label.isHidden = true
        return label
    }()
    
    /// 统计结果显示视图（改为可滚动的文本视图）
    private let statsDisplayTextView: UITextView = {
        let textView = UITextView()
        textView.isEditable = false
        textView.isScrollEnabled = true
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textColor = .white
        textView.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        textView.layer.cornerRadius = 8
        textView.layer.masksToBounds = true
        textView.text = "选择手势并开始采样..."
        textView.isHidden = true
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        return textView
    }()
    
    /// 统计结果显示视图（保留用于向后兼容）
    private let statsDisplayLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        label.layer.cornerRadius = 8
        label.layer.masksToBounds = true
        label.textAlignment = .left
        label.text = "选择手势并开始采样..."
        label.isHidden = true
        return label
    }()

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
        setupConfidenceProgressView()
        setupModeControl()
        setupTrackingView()
        setupDebugUI()
        setupDebugLogging()
        setupDetectors()
        setupCalibrationUI()
        
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
        
        // 置信度进度条布局
        confidenceProgressView.frame = CGRect(
            x: 24,
            y: gestureLabel.frame.maxY + 6,
            width: view.bounds.width - 48,
            height: 6
        )
        
        // 布局结构化调试容器（在置信度条下方）
        if isDebugEnabled {
            let debugY = confidenceProgressView.frame.maxY + 12
            let debugHeight = min(140, view.bounds.height - debugY - 200)
            
            debugContainerView.frame = CGRect(
                x: 16,
                y: debugY,
                width: view.bounds.width - 32,
                height: debugHeight
            )
            
            debugStackView.frame = debugContainerView.bounds.insetBy(dx: 12, dy: 12)
        }
        
        // 布局标定模式UI
        if currentMode == .calibration {
            let bottomSafe = view.safeAreaInsets.bottom
            
            // 手势选择控件
            calibrationGestureControl.frame = CGRect(
                x: 16,
                y: gestureLabel.frame.maxY + 16,
                width: view.bounds.width - 32,
                height: 32
            )
            
            // 按钮容器（采样按钮和导出按钮并排）
            let buttonWidth = (view.bounds.width - 48) / 2
            samplingButton.frame = CGRect(
                x: 16,
                y: calibrationGestureControl.frame.maxY + 12,
                width: buttonWidth,
                height: 44
            )
            
            exportDataButton.frame = CGRect(
                x: samplingButton.frame.maxX + 8,
                y: calibrationGestureControl.frame.maxY + 12,
                width: buttonWidth,
                height: 44
            )
            
            // 状态标签
            samplingStatusLabel.frame = CGRect(
                x: 16,
                y: samplingButton.frame.maxY + 12,
                width: view.bounds.width - 32,
                height: 24
            )
            
            // 统计显示区域（可滚动文本视图）
            let statsY = samplingStatusLabel.frame.maxY + 8
            let statsHeight = view.bounds.height - statsY - bottomSafe - 20
            statsDisplayTextView.frame = CGRect(
                x: 16,
                y: statsY,
                width: view.bounds.width - 32,
                height: max(150, statsHeight)
            )
            
            // 隐藏旧的 statsDisplayLabel
            statsDisplayLabel.isHidden = true
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
        
        // 隐藏所有模式特定的UI
        debugContainerView.isHidden = true
        confidenceProgressView.isHidden = true
        debugLabel.isHidden = true
        calibrationGestureControl.isHidden = true
        samplingButton.isHidden = true
        exportDataButton.isHidden = true
        samplingStatusLabel.isHidden = true
        statsDisplayTextView.isHidden = true
        statsDisplayLabel.isHidden = true
        if isTuningModeEnabled { tuningPanelStackView.isHidden = true }
        
        switch currentMode {
        case .handGesture:
            gestureLabel.text = "请把手伸到镜头前"
            gestureLabel.isHidden = false
            #if DEBUG
            debugContainerView.isHidden = !isDebugEnabled
            confidenceProgressView.isHidden = !isDebugEnabled
            #endif
            if isTuningModeEnabled { tuningPanelStackView.isHidden = false }
            
        case .faceTracking:
            gestureLabel.text = "正在初始化人脸检测..."
            gestureLabel.isHidden = false
            print("Starting face detector...")
            faceDetector.start()
            
        case .objectTracking:
            gestureLabel.text = "请点击屏幕选择跟踪目标"
            gestureLabel.isHidden = false
            
        #if DEBUG
        case .calibration:
            gestureLabel.text = "统计标定模式"
            gestureLabel.isHidden = false
            calibrationGestureControl.isHidden = false
            samplingButton.isHidden = false
            exportDataButton.isHidden = false
            samplingStatusLabel.isHidden = false
            statsDisplayTextView.isHidden = false
            // 初始化标定会话
            let targetGesture = gestureFromCalibrationIndex(calibrationGestureControl.selectedSegmentIndex)
            calibrationSession = CalibrationSession(targetGesture: targetGesture)
            updateCalibrationStatus()
        #endif
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
    
    private func setupConfidenceProgressView() {
        #if DEBUG
        view.addSubview(confidenceProgressView)
        confidenceProgressView.isHidden = !isDebugEnabled
        #else
        confidenceProgressView.isHidden = true
        #endif
    }

    /// 设置调试UI
    private func setupDebugUI() {
        #if DEBUG
        // 添加调试容器
        view.addSubview(debugContainerView)
        debugContainerView.addSubview(debugStackView)
        debugContainerView.isHidden = !isDebugEnabled
        
        // 创建标题标签
        let titleLabel = UILabel()
        titleLabel.text = "关键特征："
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .white
        debugStackView.addArrangedSubview(titleLabel)
        
        // 保留旧的 debugLabel 用于向后兼容
        view.addSubview(debugLabel)

        // 添加Debug开关按钮（右上角）
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Debug",
            style: .plain,
            target: self,
            action: #selector(toggleDebug)
        )
        #else
        // Release 模式：不显示任何调试UI
        debugContainerView.isHidden = true
        debugLabel.isHidden = true
        #endif
    }
    
    /// 设置标定模式UI
    private func setupCalibrationUI() {
        #if DEBUG
        view.addSubview(calibrationGestureControl)
        view.addSubview(samplingButton)
        view.addSubview(exportDataButton)
        view.addSubview(samplingStatusLabel)
        view.addSubview(statsDisplayTextView)
        view.addSubview(statsDisplayLabel)  // 保留用于向后兼容
        
        calibrationGestureControl.addTarget(self, action: #selector(calibrationGestureChanged(_:)), for: .valueChanged)
        samplingButton.addTarget(self, action: #selector(samplingButtonTapped), for: .touchUpInside)
        exportDataButton.addTarget(self, action: #selector(exportDataButtonTapped), for: .touchUpInside)
        #endif
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
        
        // 设置调试信息回调，用于UI显示
        if showDebugInfo {
            classifier.debugInfoHandler = { [weak self] info in
                DispatchQueue.main.async {
                    self?.updateDebugUI(with: info)
                }
            }
        }
        #endif
    }

    /// 切换Debug显示
    @objc private func toggleDebug() {
        #if DEBUG
        isDebugEnabled.toggle()
        debugContainerView.isHidden = !isDebugEnabled
        confidenceProgressView.isHidden = !isDebugEnabled
        debugLabel.isHidden = true  // 始终隐藏旧的debugLabel

        if isDebugEnabled {
            classifier.debugInfoHandler = { [weak self] info in
                DispatchQueue.main.async {
                    self?.updateDebugUI(with: info)
                }
            }
        } else {
            classifier.debugInfoHandler = nil
        }
        #endif
    }

    /// 更新调试UI显示（结构化版本）
    private func updateDebugUI(with info: HandGestureClassifier.HandGestureDebugInfo) {
        #if DEBUG
        guard isDebugEnabled else { return }
        
        // 清空旧的特征标签（保留标题）
        while debugStackView.arrangedSubviews.count > 1 {
            let view = debugStackView.arrangedSubviews[debugStackView.arrangedSubviews.count - 1]
            debugStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        
        // 添加结构化的特征信息
        let features: [(String, String)] = [
            ("• thumb-idx", String(format: "%.3f", info.gapThumbIndex)),
            ("• idx-mid", String(format: "%.3f", info.gapIndexMiddle)),
            ("• idx/mid", String(format: "%.2f", info.indexToMiddleRatio)),
            ("• ring/mid", String(format: "%.2f", info.ringToMiddleRatio)),
            ("• straightCount", "\(info.straightCount)")
        ]
        
        for (name, value) in features {
            let featureLabel = UILabel()
            featureLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            featureLabel.textColor = .white
            featureLabel.text = "\(name): \(value)"
            debugStackView.addArrangedSubview(featureLabel)
        }
        
        // 更新置信度进度条
        let maxScore = max(info.scoreV, info.scoreOK, info.scorePalm, info.scoreFist, info.scoreIndexFinger)
        let confidence = min(Float(maxScore) / 10.0, 1.0)  // 假设最大分数为10
        confidenceProgressView.progress = confidence
        
        // 根据置信度改变进度条颜色
        if confidence >= 0.7 {
            confidenceProgressView.progressTintColor = .systemGreen
        } else if confidence >= 0.4 {
            confidenceProgressView.progressTintColor = .systemYellow
        } else {
            confidenceProgressView.progressTintColor = .systemOrange
        }
        #endif
    }
    
    // MARK: - 标定模式Actions
    
    #if DEBUG
    @objc private func calibrationGestureChanged(_ sender: UISegmentedControl) {
        let targetGesture = gestureFromCalibrationIndex(sender.selectedSegmentIndex)
        calibrationSession = CalibrationSession(targetGesture: targetGesture)
        updateCalibrationStatus()
    }
    
    @objc private func samplingButtonTapped() {
        guard let session = calibrationSession else { return }
        
        if session.isRecording {
            // 停止采样
            session.stopRecording()
            samplingButton.setTitle("开始采样", for: .normal)
            samplingButton.backgroundColor = .systemGreen
            
            // 计算并显示统计结果
            updateCalibrationStatsDisplay()
            
        } else {
            // 开始采样
            session.startRecording()
            samplingButton.setTitle("停止采样", for: .normal)
            samplingButton.backgroundColor = .systemRed
            statsDisplayTextView.text = "正在采样中...\n样本数: 0"
        }
    }
    
    @objc private func exportDataButtonTapped() {
        guard let session = calibrationSession, !session.samples.isEmpty else {
            showAlert(title: "无数据", message: "当前没有采集的样本数据")
            return
        }
        
        // 将CalibrationSession的数据保存为JSONL
        let summary = session.generateSummary()
        print(summary)
        
        // 显示导出成功提示
        showAlert(title: "数据已导出", message: "统计数据已输出到控制台\n样本数: \(session.samples.count)")
    }
    
    /// 更新标定模式的状态显示
    private func updateCalibrationStatus() {
        guard let session = calibrationSession else { return }
        let gestureName = session.targetGesture.rawValue
        let sampleCount = session.samples.count
        samplingStatusLabel.text = "当前：\(gestureName) / 已采集：\(sampleCount) 样本"
        
        if sampleCount == 0 {
            statsDisplayTextView.text = "选择手势并开始采样..."
        }
    }
    
    /// 更新标定统计结果显示
    private func updateCalibrationStatsDisplay() {
        guard let session = calibrationSession else { return }
        let summary = session.generateSummary()
        
        // 格式化为更易读的表格形式
        var displayText = ""
        displayText += "手势: \(session.targetGesture.rawValue)\n"
        displayText += "样本数: \(session.samples.count)\n"
        displayText += String(repeating: "─", count: 40) + "\n\n"
        
        let stats = session.computeStats()
        let featureOrder = ["lenIndex", "lenMiddle", "lenRing", "lenLittle",
                           "gapThumbIndex", "gapIndexMiddle",
                           "indexToMiddleRatio", "ringToMiddleRatio", "littleToMiddleRatio"]
        
        displayText += String(format: "%-20s %6s %6s %6s\n", "特征", "min", "max", "mean")
        displayText += String(repeating: "─", count: 40) + "\n"
        
        for name in featureOrder {
            if let stat = stats[name] {
                displayText += String(format: "%-20s %6.3f %6.3f %6.3f\n",
                                    name, stat.min, stat.max, stat.mean)
            }
        }
        
        statsDisplayTextView.text = displayText
        updateCalibrationStatus()
    }
    
    /// 显示提示框
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
    #endif
    
    /// 从UI索引转换为手势类型
    private func gestureFromCalibrationIndex(_ index: Int) -> HandGestureType {
        switch index {
        case 0: return .vSign
        case 1: return .okSign
        case 2: return .palm
        case 3: return .fist
        case 4: return .indexFinger
        default: return .unknown
        }
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
            
        #if DEBUG
        case .calibration:
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
        #endif
            
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

        // 标定模式：采集样本
        #if DEBUG
        if currentMode == .calibration, let session = calibrationSession, session.isRecording {
            // 获取调试信息用于采样
            if let debugInfo = getLastDebugInfo(from: observation) {
                let sample = GestureSample(
                    lenIndex: debugInfo.lenIndex,
                    lenMiddle: debugInfo.lenMiddle,
                    lenRing: debugInfo.lenRing,
                    lenLittle: debugInfo.lenLittle,
                    gapThumbIndex: debugInfo.gapThumbIndex,
                    gapIndexMiddle: debugInfo.gapIndexMiddle,
                    indexToMiddleRatio: debugInfo.indexToMiddleRatio,
                    ringToMiddleRatio: debugInfo.ringToMiddleRatio,
                    littleToMiddleRatio: debugInfo.littleToMiddleRatio,
                    straightCount: debugInfo.straightCount,
                    scoreV: debugInfo.scoreV,
                    scoreOK: debugInfo.scoreOK,
                    scorePalm: debugInfo.scorePalm,
                    scoreFist: debugInfo.scoreFist,
                    scoreIndexFinger: debugInfo.scoreIndexFinger
                )
                session.addSample(sample)
                
                // 更新UI显示采样数
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, let session = self.calibrationSession else { return }
                    self.samplingStatusLabel.text = "当前：\(session.targetGesture.rawValue) / 已采集：\(session.samples.count) 样本"
                    self.statsDisplayTextView.text = "正在采样中...\n样本数: \(session.samples.count)"
                }
            }
            return  // 标定模式不更新手势识别UI
        }
        #endif

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
    
    /// 获取最后一次的调试信息（用于标定模式采样）
    private func getLastDebugInfo(from observation: VNHumanHandPoseObservation) -> HandGestureClassifier.HandGestureDebugInfo? {
        var capturedInfo: HandGestureClassifier.HandGestureDebugInfo?
        
        // 临时设置调试回调来捕获信息
        let originalHandler = classifier.debugInfoHandler
        classifier.debugInfoHandler = { info in
            capturedInfo = info
        }
        
        // 重新分类以触发调试回调
        _ = classifier.classify(from: observation)
        
        // 恢复原始回调
        classifier.debugInfoHandler = originalHandler
        
        return capturedInfo
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
                self.gestureLabel.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.7)
            case .okSign:
                self.gestureLabel.text = "识别到：👌 OK 手势"
                self.gestureLabel.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.7)
            case .palm:
                self.gestureLabel.text = "识别到：🖐 手掌张开"
                self.gestureLabel.backgroundColor = UIColor.systemPurple.withAlphaComponent(0.7)
            case .fist:
                self.gestureLabel.text = "识别到：✊ 拳头"
                self.gestureLabel.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.7)
            case .indexFinger:
                self.gestureLabel.text = "识别到：☝️ 食指"
                self.gestureLabel.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.7)
            default:
                // 检查是否是因为手部太远
                self.gestureLabel.text = "请把手伸到镜头前"
                self.gestureLabel.backgroundColor = UIColor.black.withAlphaComponent(0.5)
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
