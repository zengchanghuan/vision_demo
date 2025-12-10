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
    /// - Parameter orientation: 图像方向
    func detectFaces(in pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation = .up) {
        guard isEnabled, let request = faceDetectionRequest else { return }
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        
        do {
            try handler.perform([request])
        } catch {
            print("人脸检测执行失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 私有方法

    /// 处理人脸检测结果
    private func handleFaceDetectionResults(request: VNRequest) {
        guard
            let results = request.results as? [VNFaceObservation],
            let faceObservation = results.first
        else {
            onNoFaceDetected?()
            return
        }

        // 直接把 Vision 的 normalized boundingBox 往外抛
        // 0~1 之间的归一化坐标，后面交给 AVCaptureVideoPreviewLayer 去转换
        let boundingBox = faceObservation.boundingBox
        onFaceDetected?(boundingBox)
    }
}



