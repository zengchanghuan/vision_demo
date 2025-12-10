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

        // 精度优先
        request.trackingLevel = .accurate

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        do {
            try handler.perform([request])

            guard
                let results = request.results as? [VNObservation],
                let observation = results.first as? VNDetectedObjectObservation
            else {
                onTrackingLost?()
                return
            }

            // 置信度过低直接认为丢失
            guard observation.confidence > 0.3 else {
                onTrackingLost?()
                return
            }

            let bbox = observation.boundingBox // Vision：归一化，原点在左下

            // 先转换到"元数据坐标系"：归一化 + 原点左上，方便给 previewLayer 使用
            var rect = CGRect(
                x: bbox.minX,
                y: 1 - bbox.minY - bbox.height,
                width: bbox.width,
                height: bbox.height
            )

            // 把矩形调整为"接近正方形"：以中心点为基准，取宽高中的较小值
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let side = max(min(rect.width, rect.height), 0.001)
            rect = CGRect(
                x: center.x - side / 2,
                y: center.y - side / 2,
                width: side,
                height: side
            )

            // 保证仍然在 0~1 范围，避免越界
            rect.origin.x = max(0, min(rect.origin.x, 1 - rect.width))
            rect.origin.y = max(0, min(rect.origin.y, 1 - rect.height))

            onTrackingUpdate?(rect)
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



