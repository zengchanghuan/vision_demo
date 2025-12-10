import Vision
import AVFoundation
import UIKit

/// 目标跟踪器（基于 Vision Framework 的 VNTrackObjectRequest）
class ObjectTracker {

    // MARK: - 回调定义

    /// 跟踪结果回调
    var onTrackingUpdate: ((CGRect) -> Void)?  // 返回归一化坐标的矩形

    /// 跟踪丢失回调
    var onTrackingLost: (() -> Void)?

    // MARK: - 私有属性

    private var trackingRequest: VNTrackObjectRequest?
    private var isEnabled = false
    private var isInitialized = false

    // MARK: - 公共方法

    /// 初始化跟踪目标（用户框选）
    /// - Parameter rect: 归一化坐标的矩形（相对于预览层，原点在左上角）
    func initializeTracking(with rect: CGRect) {
        // 转换为Vision坐标系（原点在左下角）
        let visionRect = CGRect(
            x: rect.minX,
            y: 1 - rect.minY - rect.height,  // 翻转Y轴
            width: rect.width,
            height: rect.height
        )

        let observation = VNDetectedObjectObservation(boundingBox: visionRect)
        let request = VNTrackObjectRequest(detectedObjectObservation: observation)
        request.trackingLevel = .accurate

        trackingRequest = request
        isInitialized = true
        isEnabled = true

        print("✅ 目标跟踪已初始化: \(rect)")
    }

    /// 启动跟踪
    func start() {
        guard isInitialized else {
            print("⚠️ 目标跟踪未初始化，请先调用 initializeTracking")
            return
        }
        isEnabled = true
        print("✅ 目标跟踪已启动")
    }

    /// 停止跟踪
    func stop() {
        isEnabled = false
        isInitialized = false
        trackingRequest = nil
        onTrackingLost?()
        print("⏹️ 目标跟踪已停止")
    }

    /// 重置跟踪（重新初始化）
    func reset() {
        stop()
    }

    /// 在视频帧中执行目标跟踪
    /// - Parameter pixelBuffer: 视频帧的像素缓冲区
    func trackObject(in pixelBuffer: CVPixelBuffer) {
        guard isEnabled, let request = trackingRequest else { return }

        // 设置跟踪结果回调
        request.trackingLevel = .accurate

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        do {
            try handler.perform([request])

            // 处理跟踪结果
            if let results = request.results as? [VNObservation], let observation = results.first as? VNDetectedObjectObservation {
                // 检查置信度
                if observation.confidence > 0.3 {
                    // 转换为UIKit坐标系（原点在左上角）
                    let boundingBox = observation.boundingBox
                    let rect = CGRect(
                        x: boundingBox.minX,
                        y: 1 - boundingBox.minY - boundingBox.height,  // 翻转Y轴
                        width: boundingBox.width,
                        height: boundingBox.height
                    )
                    onTrackingUpdate?(rect)
                } else {
                    onTrackingLost?()
                }
            } else {
                onTrackingLost?()
            }
        } catch {
            print("目标跟踪执行失败: \(error.localizedDescription)")
            onTrackingLost?()
        }
    }

    /// 检查是否正在跟踪
    var isTracking: Bool {
        return isEnabled && isInitialized
    }
}



