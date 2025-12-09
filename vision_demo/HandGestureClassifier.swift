import Vision
import CoreGraphics

struct HandGestureClassifier {

    // MARK: - 特征向量定义

    /// 单帧手势的几何特征向量
    struct HandGestureFeatureVector {
        // 原始手指长度（到手腕的距离）
        let lenThumb: CGFloat
        let lenIndex: CGFloat
        let lenMiddle: CGFloat
        let lenRing: CGFloat
        let lenLittle: CGFloat

        // 原始指尖间距
        let thumbIndexGap: CGFloat
        let indexMiddleGap: CGFloat
        let middleRingGap: CGFloat
        let ringLittleGap: CGFloat

        // 手宽归一化基准
        let handWidth: CGFloat

        // 归一化手指长度（相对于手宽）
        let lenThumbNorm: CGFloat
        let lenIndexNorm: CGFloat
        let lenMiddleNorm: CGFloat
        let lenRingNorm: CGFloat
        let lenLittleNorm: CGFloat

        // 归一化指尖间距（相对于手宽）
        let thumbIndexGapNorm: CGFloat
        let indexMiddleGapNorm: CGFloat
        let middleRingGapNorm: CGFloat
        let ringLittleGapNorm: CGFloat

        // 其他特征
        let straightCount: Int  // 伸直手指数量（index, middle, ring）
        let wristToIndexTip: CGFloat  // 手腕到食指尖距离
        let wristToLittleTip: CGFloat  // 手腕到小指尖距离
    }

    /// 手势分类结果（包含预测结果和特征向量）
    struct GestureClassificationResult {
        let predicted: HandGestureType
        let features: HandGestureFeatureVector
    }

    // MARK: - 阈值配置

    /// 手势识别相关的阈值配置，统一管理便于调参
    private struct Constants {
        // V 手势阈值
        static let vIndexLongThreshold: CGFloat = 0.18      // 食指长度阈值（到手腕距离）
        static let vMiddleLongThreshold: CGFloat = 0.18     // 中指长度阈值
        static let vRingShortThreshold: CGFloat = 0.15      // 无名指"短"的阈值
        static let vLittleShortThreshold: CGFloat = 0.15   // 小指"短"的阈值
        static let vIndexMiddleGapMin: CGFloat = 0.08      // 食指与中指最小间距

        // OK 手势阈值（归一化后，相对于手宽）
        static let okLoopMaxGap: CGFloat = 0.35            // 拇指-食指最大间距（形成圆圈）
        static let okThumbMinLength: CGFloat = 0.5         // 拇指最小长度（归一化）
        static let okIndexMinLength: CGFloat = 0.5          // 食指最小长度（归一化）
        static let okOthersShortRatio: CGFloat = 0.9        // 中指相对食指/中指的"短"比例（0.9 表示 < 90%）
        static let okRingShortRatio: CGFloat = 0.8          // 无名指相对食指/中指的"短"比例
        static let okLittleShortRatio: CGFloat = 0.8        // 小指相对食指/中指的"短"比例
        static let okMaxStraightFingers: Int = 1            // 最多允许几根手指伸直（超过则更像张开掌）
        static let okMinShortFingers: Int = 2               // 至少几根其他手指要"短"

        // 张开手掌阈值（归一化后，相对于手宽）
        static let openPalmFingerMinLength: CGFloat = 0.5   // 每根手指的最小长度
        static let openPalmThumbIndexGapMin: CGFloat = 0.45 // 拇指-食指最小间距（明显分开）
        static let openPalmIndexMiddleGapMin: CGFloat = 0.15 // 食指-中指最小间距
        static let openPalmMiddleRingGapMin: CGFloat = 0.12  // 中指-无名指最小间距
        static let openPalmRingLittleGapMin: CGFloat = 0.10  // 无名指-小指最小间距
        static let openPalmMinStraightFingers: Int = 2       // 至少几根手指要伸直

        // 通用阈值
        static let minConfidence: CGFloat = 0.3              // 关键点最小置信度
        static let fingerStraightAngleRad: CGFloat = .pi * 0.75  // 手指伸直的角度阈值（135°）
    }

    // MARK: - Debug 回调

    /// 可选的调试日志回调，用于输出关键特征值
    var debugLogHandler: ((String) -> Void)?

    // MARK: - 特征提取

    /// 从 Vision 观察结果中提取所有几何特征
    /// - Parameter observation: Vision 框架的手部姿态观察结果
    /// - Returns: 特征向量，如果提取失败返回 nil
    func computeFeatures(from observation: VNHumanHandPoseObservation) -> HandGestureFeatureVector? {
        do {
            let allPoints = try observation.recognizedPoints(.all)
            let thumbPoints = try observation.recognizedPoints(.thumb)
            let indexPoints = try observation.recognizedPoints(.indexFinger)
            let middlePoints = try observation.recognizedPoints(.middleFinger)
            let ringPoints = try observation.recognizedPoints(.ringFinger)
            let littlePoints = try observation.recognizedPoints(.littleFinger)

            // 获取指尖和手腕
            guard
                let wrist      = allPoints[.wrist],
                let thumbTip   = thumbPoints[.thumbTip],
                let indexTip   = indexPoints[.indexTip],
                let middleTip  = middlePoints[.middleTip],
                let ringTip    = ringPoints[.ringTip],
                let littleTip  = littlePoints[.littleTip],
                CGFloat(wrist.confidence) > Constants.minConfidence,
                CGFloat(thumbTip.confidence) > Constants.minConfidence,
                CGFloat(indexTip.confidence) > Constants.minConfidence,
                CGFloat(middleTip.confidence) > Constants.minConfidence,
                CGFloat(ringTip.confidence) > Constants.minConfidence,
                CGFloat(littleTip.confidence) > Constants.minConfidence
            else {
                return nil
            }

            // 获取关节点（用于判断手指是否伸直）
            guard
                let indexMCP  = indexPoints[.indexMCP],
                let indexPIP  = indexPoints[.indexPIP],
                let indexDIP  = indexPoints[.indexDIP],
                let middleMCP = middlePoints[.middleMCP],
                let middlePIP = middlePoints[.middlePIP],
                let middleDIP = middlePoints[.middleDIP],
                let ringMCP   = ringPoints[.ringMCP],
                let ringPIP   = ringPoints[.ringPIP],
                let ringDIP   = ringPoints[.ringDIP],
                CGFloat(indexMCP.confidence) > Constants.minConfidence,
                CGFloat(indexPIP.confidence) > Constants.minConfidence,
                CGFloat(indexDIP.confidence) > Constants.minConfidence,
                CGFloat(middleMCP.confidence) > Constants.minConfidence,
                CGFloat(middlePIP.confidence) > Constants.minConfidence,
                CGFloat(middleDIP.confidence) > Constants.minConfidence,
                CGFloat(ringMCP.confidence) > Constants.minConfidence,
                CGFloat(ringPIP.confidence) > Constants.minConfidence,
                CGFloat(ringDIP.confidence) > Constants.minConfidence
            else {
                return nil
            }

            // 计算手指长度（到手腕的距离）
            let lenThumb  = normalizedFingerLength(tip: thumbTip,  wrist: wrist)
            let lenIndex  = normalizedFingerLength(tip: indexTip,  wrist: wrist)
            let lenMiddle = normalizedFingerLength(tip: middleTip, wrist: wrist)
            let lenRing   = normalizedFingerLength(tip: ringTip,   wrist: wrist)
            let lenLittle = normalizedFingerLength(tip: littleTip, wrist: wrist)

            // 计算指尖之间的距离
            let indexMiddleGap = distance(indexTip, middleTip)
            let thumbIndexGap  = distance(thumbTip, indexTip)
            let middleRingGap  = distance(middleTip, ringTip)
            let ringLittleGap  = distance(ringTip, littleTip)

            // 计算手宽归一化基准（用食指尖到小指尖的距离）
            let handWidth = max(distance(indexTip, littleTip), 0.0001)

            // 计算归一化距离（相对于手宽）
            let thumbIndexGapNorm = thumbIndexGap / handWidth
            let indexMiddleGapNorm = indexMiddleGap / handWidth
            let middleRingGapNorm = middleRingGap / handWidth
            let ringLittleGapNorm = ringLittleGap / handWidth

            // 归一化手指长度（相对于手宽）
            let lenThumbNorm  = lenThumb / handWidth
            let lenIndexNorm  = lenIndex / handWidth
            let lenMiddleNorm = lenMiddle / handWidth
            let lenRingNorm   = lenRing / handWidth
            let lenLittleNorm = lenLittle / handWidth

            // 判断手指是否伸直
            let indexStraight  = isFingerStraight(mcp: indexMCP,  pip: indexPIP,  dip: indexDIP)
            let middleStraight = isFingerStraight(mcp: middleMCP, pip: middlePIP, dip: middleDIP)
            let ringStraight   = isFingerStraight(mcp: ringMCP,   pip: ringPIP,   dip: ringDIP)
            let straightCount = [indexStraight, middleStraight, ringStraight].filter { $0 }.count

            // 计算手腕到指尖距离（用于手宽计算）
            let wristToIndexTip = distance(wrist, indexTip)
            let wristToLittleTip = distance(wrist, littleTip)

            return HandGestureFeatureVector(
                lenThumb: lenThumb,
                lenIndex: lenIndex,
                lenMiddle: lenMiddle,
                lenRing: lenRing,
                lenLittle: lenLittle,
                thumbIndexGap: thumbIndexGap,
                indexMiddleGap: indexMiddleGap,
                middleRingGap: middleRingGap,
                ringLittleGap: ringLittleGap,
                handWidth: handWidth,
                lenThumbNorm: lenThumbNorm,
                lenIndexNorm: lenIndexNorm,
                lenMiddleNorm: lenMiddleNorm,
                lenRingNorm: lenRingNorm,
                lenLittleNorm: lenLittleNorm,
                thumbIndexGapNorm: thumbIndexGapNorm,
                indexMiddleGapNorm: indexMiddleGapNorm,
                middleRingGapNorm: middleRingGapNorm,
                ringLittleGapNorm: ringLittleGapNorm,
                straightCount: straightCount,
                wristToIndexTip: wristToIndexTip,
                wristToLittleTip: wristToLittleTip
            )

        } catch {
            return nil
        }
    }

    // MARK: - 手势分类入口

    /// 基于特征向量进行分类
    /// - Parameter features: 特征向量
    /// - Returns: 识别的手势类型
    func classify(features: HandGestureFeatureVector) -> HandGestureType {
        // 准备调试信息
        var debugInfo: [String] = []
        debugInfo.append(String(format: "lenIdx:%.3f lenMid:%.3f lenRing:%.3f lenLit:%.3f", features.lenIndex, features.lenMiddle, features.lenRing, features.lenLittle))
        debugInfo.append(String(format: "gapIdxMid:%.3f gapThumbIdx:%.3f", features.indexMiddleGap, features.thumbIndexGap))
        debugInfo.append(String(format: "straightCnt:%d", features.straightCount))

        // 按优先级检查手势：先 V，再 OK，最后张开手掌
        // 优先级说明：V 手势特征最明显（两指长两指短），OK 手势需要排除（拇指食指接近），最后才是张开手掌

        // 1. 检查 V 手势
        if isVSign(lenIndex: features.lenIndex,
                   lenMiddle: features.lenMiddle,
                   lenRing: features.lenRing,
                   lenLittle: features.lenLittle,
                   indexMiddleGap: features.indexMiddleGap) {
            debugLogHandler?("V手势 ✓ | \(debugInfo.joined(separator: " | "))")
            return .vSign
        }

        // 2. 检查 OK 手势（更特殊的手势，优先级高于张开手掌）
        if isOKSign(lenIndexNorm: features.lenIndexNorm,
                    lenMiddleNorm: features.lenMiddleNorm,
                    lenRingNorm: features.lenRingNorm,
                    lenLittleNorm: features.lenLittleNorm,
                    lenThumbNorm: features.lenThumbNorm,
                    thumbIndexGapNorm: features.thumbIndexGapNorm,
                    straightCount: features.straightCount) {
            debugInfo.append(String(format: "lenThumbNorm:%.3f gapThumbIdxNorm:%.3f", features.lenThumbNorm, features.thumbIndexGapNorm))
            debugLogHandler?("OK手势 ✓ | \(debugInfo.joined(separator: " | "))")
            return .okSign
        }

        // 3. 检查手掌张开（需要排除 OK 手势的情况）
        if isOpenPalm(lenIndexNorm: features.lenIndexNorm,
                      lenMiddleNorm: features.lenMiddleNorm,
                      lenRingNorm: features.lenRingNorm,
                      lenLittleNorm: features.lenLittleNorm,
                      lenThumbNorm: features.lenThumbNorm,
                      indexMiddleGapNorm: features.indexMiddleGapNorm,
                      thumbIndexGapNorm: features.thumbIndexGapNorm,
                      middleRingGapNorm: features.middleRingGapNorm,
                      ringLittleGapNorm: features.ringLittleGapNorm,
                      straightCount: features.straightCount) {
            debugInfo.append(String(format: "gapsNorm:%.3f,%.3f,%.3f,%.3f", features.thumbIndexGapNorm, features.indexMiddleGapNorm, features.middleRingGapNorm, features.ringLittleGapNorm))
            debugLogHandler?("手掌张开 ✓ | \(debugInfo.joined(separator: " | "))")
            return .openPalm
        }

        // 未识别
        debugLogHandler?("未识别 ✗ | \(debugInfo.joined(separator: " | "))")
        return .unknown
    }

    /// 从 Vision 观察结果进行分类（保持原有接口）
    /// - Parameter observation: Vision 框架的手部姿态观察结果
    /// - Returns: 识别的手势类型
    func classify(from observation: VNHumanHandPoseObservation) -> HandGestureType {
        guard let features = computeFeatures(from: observation) else {
            return .unknown
        }
        return classify(features: features)
    }

    /// 从 Vision 观察结果进行分类，并返回完整结果（包含特征向量）
    /// - Parameter observation: Vision 框架的手部姿态观察结果
    /// - Returns: 分类结果（包含预测结果和特征向量），如果提取失败返回 nil
    func classifyWithFeatures(from observation: VNHumanHandPoseObservation) -> GestureClassificationResult? {
        guard let features = computeFeatures(from: observation) else {
            return nil
        }
        let predicted = classify(features: features)
        return GestureClassificationResult(predicted: predicted, features: features)
    }

    // MARK: - 基础工具

    private func distance(_ a: VNRecognizedPoint, _ b: VNRecognizedPoint) -> CGFloat {
        let dx = a.location.x - b.location.x
        let dy = a.location.y - b.location.y
        return sqrt(dx * dx + dy * dy)
    }

    private func normalizedFingerLength(tip: VNRecognizedPoint, wrist: VNRecognizedPoint) -> CGFloat {
        // 这里直接用归一化坐标的距离，0~1 之间
        distance(tip, wrist)
    }

    /// 计算三点形成的角度（返回弧度）
    /// - Parameters:
    ///   - a: 第一个点
    ///   - b: 中间点（顶点）
    ///   - c: 第三个点
    /// - Returns: 角度（弧度），范围 0 到 π
    private func angle(_ a: VNRecognizedPoint, _ b: VNRecognizedPoint, _ c: VNRecognizedPoint) -> CGFloat {
        let v1 = CGVector(dx: a.location.x - b.location.x, dy: a.location.y - b.location.y)
        let v2 = CGVector(dx: c.location.x - b.location.x, dy: c.location.y - b.location.y)
        let dot = v1.dx * v2.dx + v1.dy * v2.dy
        let len1 = sqrt(v1.dx * v1.dx + v1.dy * v1.dy)
        let len2 = sqrt(v2.dx * v2.dx + v2.dy * v2.dy)
        let cosValue = dot / max(len1 * len2, 0.0001)
        return acos(max(-1, min(1, cosValue))) // 返回弧度
    }

    /// 判断单根手指是否伸直
    /// - Parameters:
    ///   - mcp: 掌指关节（Metacarpophalangeal joint）
    ///   - pip: 近端指间关节（Proximal Interphalangeal joint）
    ///   - dip: 远端指间关节（Distal Interphalangeal joint）
    /// - Returns: 如果手指伸直（角度 > 135°）返回 true
    private func isFingerStraight(mcp: VNRecognizedPoint,
                                  pip: VNRecognizedPoint,
                                  dip: VNRecognizedPoint) -> Bool {
        let rad = angle(mcp, pip, dip)
        return rad > Constants.fingerStraightAngleRad
    }

    // MARK: - 手势规则

    /// ✌️ V 手势：食指 & 中指长，另外两指明显短，而且食指与中指间距较大
    private func isVSign(
        lenIndex: CGFloat,
        lenMiddle: CGFloat,
        lenRing: CGFloat,
        lenLittle: CGFloat,
        indexMiddleGap: CGFloat
    ) -> Bool {
        let indexLong   = lenIndex  > Constants.vIndexLongThreshold
        let middleLong  = lenMiddle > Constants.vMiddleLongThreshold
        let ringShort   = lenRing   < Constants.vRingShortThreshold
        let littleShort = lenLittle < Constants.vLittleShortThreshold
        let spreadBig   = indexMiddleGap > Constants.vIndexMiddleGapMin

        return indexLong && middleLong && ringShort && littleShort && spreadBig
    }

    /// 👌 OK 手势：拇指和食指指尖非常接近，且两者都不算短
    /// 关键特征：拇指和食指形成圆圈，其他三个手指应该相对较短（不是完全伸直）
    private func isOKSign(
        lenIndexNorm: CGFloat,
        lenMiddleNorm: CGFloat,
        lenRingNorm: CGFloat,
        lenLittleNorm: CGFloat,
        lenThumbNorm: CGFloat,
        thumbIndexGapNorm: CGFloat,
        straightCount: Int
    ) -> Bool {
        // 1. 拇指和食指形成一个很小的圈（归一化距离）
        let thumbIndexClose = thumbIndexGapNorm < Constants.okLoopMaxGap

        // 2. 拇指 & 食指不算很短（自然伸出）
        let thumbLongEnough = lenThumbNorm > Constants.okThumbMinLength
        let indexLongEnough = lenIndexNorm > Constants.okIndexMinLength

        // 3. 其他三指不要"全部伸直"（否则更像张开掌）
        let notAllOthersStraight = straightCount <= Constants.okMaxStraightFingers

        // 4. 中/无名/小指相对短一点（和 index/中指比）
        let indexRef = max(lenIndexNorm, lenMiddleNorm)
        let middleRelShort = lenMiddleNorm < indexRef * Constants.okOthersShortRatio
        let ringRelShort   = lenRingNorm   < indexRef * Constants.okRingShortRatio
        let littleRelShort = lenLittleNorm < indexRef * Constants.okLittleShortRatio
        let shortRelCount = [middleRelShort, ringRelShort, littleRelShort].filter { $0 }.count

        return thumbIndexClose &&
               thumbLongEnough &&
               indexLongEnough &&
               notAllOthersStraight &&
               shortRelCount >= Constants.okMinShortFingers
    }

    /// 🖐 张开手掌：五根手指都伸得比较长，且指缝有一定间距
    /// 关键特征：所有手指都长，且拇指和食指之间有明显间距（排除 OK 手势）
    private func isOpenPalm(
        lenIndexNorm: CGFloat,
        lenMiddleNorm: CGFloat,
        lenRingNorm: CGFloat,
        lenLittleNorm: CGFloat,
        lenThumbNorm: CGFloat,
        indexMiddleGapNorm: CGFloat,
        thumbIndexGapNorm: CGFloat,
        middleRingGapNorm: CGFloat,
        ringLittleGapNorm: CGFloat,
        straightCount: Int
    ) -> Bool {
        // 1. 多根手指伸直
        let enoughStraightFingers = straightCount >= Constants.openPalmMinStraightFingers

        // 2. 整体都不短（相对 handWidth）
        let allLong = lenIndexNorm  > Constants.openPalmFingerMinLength &&
                      lenMiddleNorm > Constants.openPalmFingerMinLength &&
                      lenRingNorm   > Constants.openPalmFingerMinLength &&
                      lenLittleNorm > Constants.openPalmFingerMinLength &&
                      lenThumbNorm  > Constants.openPalmFingerMinLength

        // 3. 拇指和食指明显分开
        let thumbIndexSpread = thumbIndexGapNorm > Constants.openPalmThumbIndexGapMin

        // 4. 其他指缝也有"张开"感觉
        let otherSpread = indexMiddleGapNorm > Constants.openPalmIndexMiddleGapMin &&
                          middleRingGapNorm  > Constants.openPalmMiddleRingGapMin &&
                          ringLittleGapNorm  > Constants.openPalmRingLittleGapMin

        return enoughStraightFingers && allLong && thumbIndexSpread && otherSpread
    }
}
