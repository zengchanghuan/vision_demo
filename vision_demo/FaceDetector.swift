import Vision
import AVFoundation
import UIKit

/// 人脸检测器（基于 Vision Framework）
class FaceDetector {

    // MARK: - 回调定义

    /// 人脸检测结果回调
    var onFaceDetected: ((CGRect) -> Void)?  // 返回归一化坐标的矩形（相对于预览层）

    /// 未检测到人脸回调
    var onNoFaceDetected: (() -> Void)?

    // MARK: - 私有属性

    private var faceDetectionRequest: VNDetectFaceRectanglesRequest?
    private var isEnabled = false

    // MARK: - 公共方法

    /// 启动人脸检测
    func start() {
        isEnabled = true

        let request = VNDetectFaceRectanglesRequest { [weak self] request, error in
            guard let self = self, self.isEnabled else { return }

            if let error = error {
                print("人脸检测错误: \(error.localizedDescription)")
                return
            }

            self.handleFaceDetectionResults(request: request)
        }

        faceDetectionRequest = request
        print("✅ 人脸检测已启动")
    }

    /// 停止人脸检测
    func stop() {
        isEnabled = false
        faceDetectionRequest = nil
        onNoFaceDetected?()
        print("⏹️ 人脸检测已停止")
    }

    /// 在视频帧中执行人脸检测
    /// - Parameter pixelBuffer: 视频帧的像素缓冲区
    func detectFaces(in pixelBuffer: CVPixelBuffer) {
        guard isEnabled, let request = faceDetectionRequest else { return }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        do {
            try handler.perform([request])
        } catch {
            print("人脸检测执行失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 私有方法

    /// 处理人脸检测结果
    private func handleFaceDetectionResults(request: VNRequest) {
        guard let results = request.results as? [VNFaceObservation], !results.isEmpty else {
            onNoFaceDetected?()
            return
        }

        // 取第一个检测到的人脸
        let faceObservation = results[0]
        let boundingBox = faceObservation.boundingBox

        // Vision框架使用归一化坐标（原点在左下角）
        // 转换为UIKit坐标系（原点在左上角）
        let rect = CGRect(
            x: boundingBox.minX,
            y: 1 - boundingBox.minY - boundingBox.height,  // 翻转Y轴
            width: boundingBox.width,
            height: boundingBox.height
        )

        onFaceDetected?(rect)
    }
}



