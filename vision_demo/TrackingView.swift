import UIKit

class TrackingView: UIView {
    
    private var trackingLayer: CAShapeLayer?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /// 更新跟踪框
    /// - Parameter rect: 归一化坐标的矩形 (0~1)
    /// - Parameter color: 边框颜色
    /// - Parameter isDashed: 是否使用虚线
    func updateTrackingRect(_ rect: CGRect, color: UIColor = .green, isDashed: Bool = false) {
        // 移除旧的层
        trackingLayer?.removeFromSuperlayer()
        
        // 转换坐标
        let convertedRect = CGRect(
            x: rect.minX * bounds.width,
            y: rect.minY * bounds.height,
            width: rect.width * bounds.width,
            height: rect.height * bounds.height
        )
        
        // 创建路径
        let path = UIBezierPath(rect: convertedRect)
        
        // 创建形状层
        let layer = CAShapeLayer()
        layer.path = path.cgPath
        layer.fillColor = UIColor.clear.cgColor
        layer.strokeColor = color.cgColor
        layer.lineWidth = 3.0
        layer.lineCap = .round
        layer.lineJoin = .round
        
        // 添加虚线效果
        if isDashed {
            layer.lineDashPattern = [6, 4]
        }
        
        self.layer.addSublayer(layer)
        trackingLayer = layer
    }
    
    /// 清除跟踪框
    func clear() {
        trackingLayer?.removeFromSuperlayer()
        trackingLayer = nil
    }
}

