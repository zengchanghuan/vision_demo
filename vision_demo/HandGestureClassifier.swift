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

    /// 用于分类的统一特征向量（包含原始特征和派生特征ratio）
    private struct GestureFeatures {
        // 原始特征（使用原始值，因为统计量基于原始值）
        let lenIndex: CGFloat
        let lenMiddle: CGFloat
        let lenRing: CGFloat
        let lenLittle: CGFloat
        let gapThumbIndex: CGFloat
        let gapIndexMiddle: CGFloat

        // 派生特征（ratio）
        let indexToMiddleRatio: CGFloat      // lenIndex / lenMiddle
        let ringToMiddleRatio: CGFloat       // lenRing / lenMiddle
        let littleToMiddleRatio: CGFloat     // lenLittle / lenMiddle
    }

    // MARK: - 阈值配置

    /// 手势识别相关的阈值配置，统一管理便于调参
    private struct Constants {
        // MARK: - 基于统计量的阈值结构体

        /// V 手势阈值（基于统计量：thumbIndexGap≈0.33, indexMiddleGap≈0.14, indexToMiddleRatio≈1.14等）
        struct VThreshold {
            // 基于V手势thumbIndexGap mean≈0.33、Palm mean≈0.18，取中间值0.25作为最小值
            static let thumbIndexGapMin: CGFloat = 0.25
            // 基于V手势indexMiddleGap mean≈0.14，Palm mean≈0.065，OK mean≈0.18，取0.10-0.19区间
            static let indexMiddleGapMin: CGFloat = 0.10
            static let indexMiddleGapMax: CGFloat = 0.19
            // 基于V手势indexToMiddleRatio mean≈1.14，要求食指略长于中指
            static let indexToMiddleRatioMin: CGFloat = 1.05
            // 基于V手势ringToMiddleRatio mean≈0.40，要求无名指明显短于中指
            static let ringToMiddleRatioMax: CGFloat = 0.60
            // 基于V手势littleToMiddleRatio mean≈0.39，要求小指明显短于中指
            static let littleToMiddleRatioMax: CGFloat = 0.60
            // V手势通常是2根手指伸直（食指和中指）
            static let maxStraightCount: Int = 3
            static let minScore: Int = 4
        }

        /// OK 手势阈值（基于统计量：thumbIndexGap≈0.043, indexToMiddleRatio≈0.70等）
        struct OKThreshold {
            // 基于OK手势thumbIndexGap mean≈0.043，Palm mean≈0.18，取中间值0.11作为最大值
            static let thumbIndexGapMax: CGFloat = 0.11
            // 基于OK手势indexMiddleGap mean≈0.18，V mean≈0.14，取略偏OK的值0.16
            static let indexMiddleGapMin: CGFloat = 0.16
            // 基于OK手势indexToMiddleRatio mean≈0.70，要求食指明显短于中指
            static let indexToMiddleRatioMax: CGFloat = 0.90
            // 基于OK手势ringToMiddleRatio mean≈0.89，要求无名指接近中指长度
            static let ringToMiddleRatioMin: CGFloat = 0.75
            // 基于OK手势littleToMiddleRatio mean≈0.77
            static let littleToMiddleRatioMin: CGFloat = 0.60
            // OK手势至少还有2根手指伸直（中指、无名指等）
            static let minStraightCount: Int = 2
            static let minScore: Int = 4
        }

        /// 手掌张开阈值（基于统计量：thumbIndexGap≈0.18, indexToMiddleRatio≈1.02等）
        struct PalmThreshold {
            // 基于Palm手势thumbIndexGap mean≈0.18，V mean≈0.33，取0.13-0.25区间
            static let thumbIndexGapMin: CGFloat = 0.13
            static let thumbIndexGapMax: CGFloat = 0.25
            // 基于Palm手势indexMiddleGap mean≈0.065，OK mean≈0.18，取0.05-0.10区间
            static let indexMiddleGapMin: CGFloat = 0.05
            static let indexMiddleGapMax: CGFloat = 0.10
            // 基于Palm手势indexToMiddleRatio mean≈1.02，要求食指和中指差不多长
            static let indexToMiddleRatioMin: CGFloat = 0.90
            static let indexToMiddleRatioMax: CGFloat = 1.10
            // 基于Palm手势ringToMiddleRatio mean≈0.91
            static let ringToMiddleRatioMin: CGFloat = 0.80
            // 基于Palm手势littleToMiddleRatio mean≈0.77
            static let littleToMiddleRatioMin: CGFloat = 0.70
            // 手掌张开四指都直
            static let minStraightCount: Int = 4
            static let minScore: Int = 4
        }

        /// 拳头手势阈值（所有手指弯曲，手指长度都很短）
        struct FistThreshold {
            // 拳头时所有手指都弯曲，没有手指伸直
            static let maxStraightCount: Int = 0
            // 拳头时食指相对于中指会变短（都弯曲）
            static let indexToMiddleRatioMax: CGFloat = 0.85
            // 拳头时无名指相对中指较短
            static let ringToMiddleRatioMax: CGFloat = 0.85
            // 拳头时小指相对中指较短
            static let littleToMiddleRatioMax: CGFloat = 0.85
            // 拳头时指尖间距都很小
            static let thumbIndexGapMax: CGFloat = 0.15
            static let indexMiddleGapMax: CGFloat = 0.08
            static let minScore: Int = 4
        }

        /// 食指手势阈值（只有食指伸直）
        struct IndexFingerThreshold {
            // 食指手势只有食指伸直（straightCount = 1）
            static let exactStraightCount: Int = 1
            // 食指应该比中指长
            static let indexToMiddleRatioMin: CGFloat = 1.05
            // 无名指和小指应该明显短于中指（弯曲）
            static let ringToMiddleRatioMax: CGFloat = 0.70
            static let littleToMiddleRatioMax: CGFloat = 0.70
            // 拇指和食指间距较小（食指指向时）
            static let thumbIndexGapMax: CGFloat = 0.20
            static let minScore: Int = 4
        }

        // 全局阈值
        static let minAcceptScore: Int = 4  // 最低通过分数

        // 通用阈值
        static let minConfidence: CGFloat = 0.3              // 关键点最小置信度
        static let fingerStraightAngleRad: CGFloat = .pi * 0.75  // 手指伸直的角度阈值（135°）
    }

    // MARK: - Debug 回调

    /// 调试信息结构体
    struct HandGestureDebugInfo {
        let gesture: HandGestureType
        let lenIndex: CGFloat
        let lenMiddle: CGFloat
        let lenRing: CGFloat
        let lenLittle: CGFloat
        let gapThumbIndex: CGFloat
        let gapIndexMiddle: CGFloat
        let indexToMiddleRatio: CGFloat
        let ringToMiddleRatio: CGFloat
        let littleToMiddleRatio: CGFloat
        let straightCount: Int
        let scoreV: Int
        let scoreOK: Int
        let scorePalm: Int
        let scoreFist: Int
        let scoreIndexFinger: Int
    }

    /// 可选的调试日志回调，用于输出关键特征值
    var debugLogHandler: ((String) -> Void)?

    /// 可选的调试信息回调，用于UI显示
    var debugInfoHandler: ((HandGestureDebugInfo) -> Void)?

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


    /// 从HandGestureFeatureVector创建GestureFeatures（包含ratio计算）
    /// - Parameter features: 原始特征向量
    /// - Returns: GestureFeatures，如果lenMiddle太小（除0风险）返回nil
    private func makeFeatures(from features: HandGestureFeatureVector) -> GestureFeatures? {
        // 防止除0：如果lenMiddle太小，认为数据不可靠
        guard features.lenMiddle > 0.001 else {
            return nil
        }

        return GestureFeatures(
            lenIndex: features.lenIndex,
            lenMiddle: features.lenMiddle,
            lenRing: features.lenRing,
            lenLittle: features.lenLittle,
            gapThumbIndex: features.thumbIndexGap,
            gapIndexMiddle: features.indexMiddleGap,
            indexToMiddleRatio: features.lenIndex / features.lenMiddle,
            ringToMiddleRatio: features.lenRing / features.lenMiddle,
            littleToMiddleRatio: features.lenLittle / features.lenMiddle
        )
    }


    // MARK: - 手势打分

    /// 为五个手势分别打分
    /// - Parameters:
    ///   - features: 特征向量
    ///   - straightCount: 伸直手指数量
    /// - Returns: (v分数, ok分数, palm分数, fist分数, indexFinger分数)
    private func scoreGestures(features: GestureFeatures, straightCount: Int) -> (v: Int, ok: Int, palm: Int, fist: Int, indexFinger: Int) {
        var scoreV = 0
        var scoreOK = 0
        var scorePalm = 0
        var scoreFist = 0
        var scoreIndexFinger = 0

        // V手势打分
        if features.gapThumbIndex >= Constants.VThreshold.thumbIndexGapMin {
            scoreV += 2  // 拇指食指间距较大（基于V mean≈0.33）
        }
        if features.gapIndexMiddle >= Constants.VThreshold.indexMiddleGapMin &&
           features.gapIndexMiddle <= Constants.VThreshold.indexMiddleGapMax {
            scoreV += 2  // 食指中指间距在合理区间（基于V mean≈0.14）
        }
        if features.indexToMiddleRatio >= Constants.VThreshold.indexToMiddleRatioMin {
            scoreV += 1  // 食指略长于中指（基于V mean≈1.14）
        }
        
        // 关键区分点：V手势要求无名指和小指必须弯曲（短）
        if features.ringToMiddleRatio <= Constants.VThreshold.ringToMiddleRatioMax {
            scoreV += 2  // 无名指明显短于中指（加强权重）
        } else {
            scoreV -= 2  // 如果无名指太长，说明可能不是V手势（可能是手掌）
        }
        
        if features.littleToMiddleRatio <= Constants.VThreshold.littleToMiddleRatioMax {
            scoreV += 2  // 小指明显短于中指（加强权重）
        } else {
            scoreV -= 2  // 如果小指太长，说明可能不是V手势
        }
        
        if straightCount <= Constants.VThreshold.maxStraightCount {
            scoreV += 1  // 通常2根手指伸直
        }

        // OK手势打分
        if features.gapThumbIndex <= Constants.OKThreshold.thumbIndexGapMax {
            // 拇指食指靠得很近，更像 OK
            scoreOK += 2
        } else if features.gapThumbIndex >= Constants.PalmThreshold.thumbIndexGapMin {
            // 拇指食指间距已经接近/超过手掌区间，更像手掌
            scoreOK -= 2
        }
        
        if features.gapIndexMiddle >= Constants.OKThreshold.indexMiddleGapMin {
            // 食指弯成圈后和中指间距较大
            scoreOK += 2
        } else if features.gapIndexMiddle <= Constants.PalmThreshold.indexMiddleGapMax {
            // 食指中指间距非常小，更像手掌
            scoreOK -= 1
        }
        
        if features.indexToMiddleRatio <= Constants.OKThreshold.indexToMiddleRatioMax {
            scoreOK += 1  // 食指明显变短
        }
        
        if features.ringToMiddleRatio >= Constants.OKThreshold.ringToMiddleRatioMin {
            scoreOK += 1  // 无名指比较直
        }
        
        if features.littleToMiddleRatio >= Constants.OKThreshold.littleToMiddleRatioMin {
            scoreOK += 1  // 小指比较直
        }
        
        if straightCount >= Constants.OKThreshold.minStraightCount {
            scoreOK += 1  // 至少还有2根手指伸直
        }

        // 手掌张开打分
        if features.gapThumbIndex >= Constants.PalmThreshold.thumbIndexGapMin &&
           features.gapThumbIndex <= Constants.PalmThreshold.thumbIndexGapMax {
            scorePalm += 2  // 拇指食指间距在 Palm 合理区间
        } else if features.gapThumbIndex <= Constants.OKThreshold.thumbIndexGapMax {
            // 拇指食指太近，更像 OK
            scorePalm -= 2
        }
        
        if features.gapIndexMiddle >= Constants.PalmThreshold.indexMiddleGapMin &&
           features.gapIndexMiddle <= Constants.PalmThreshold.indexMiddleGapMax {
            scorePalm += 2  // 食指中指间距较小
        } else if features.gapIndexMiddle >= Constants.OKThreshold.indexMiddleGapMin {
            // 食指中指距离太大，更像 OK
            scorePalm -= 2
        }
        
        if features.indexToMiddleRatio >= Constants.PalmThreshold.indexToMiddleRatioMin &&
           features.indexToMiddleRatio <= Constants.PalmThreshold.indexToMiddleRatioMax {
            scorePalm += 1  // 食指和中指长度接近
        }
        
        // 关键区分点：手掌要求无名指和小指必须伸直（长）
        if features.ringToMiddleRatio >= Constants.PalmThreshold.ringToMiddleRatioMin {
            scorePalm += 2  // 无名指比较长
        } else {
            scorePalm -= 2  // 无名指太短，扣分
        }
        
        if features.littleToMiddleRatio >= Constants.PalmThreshold.littleToMiddleRatioMin {
            scorePalm += 2  // 小指比较长
        } else {
            scorePalm -= 2  // 小指太短，扣分
        }
        
        if straightCount >= Constants.PalmThreshold.minStraightCount {
            scorePalm += 1  // 四指都直
        }

        // 拳头打分
        if straightCount <= Constants.FistThreshold.maxStraightCount {
            scoreFist += 2  // 没有手指伸直
        }
        if features.gapThumbIndex <= Constants.FistThreshold.thumbIndexGapMax {
            scoreFist += 2  // 拇指食指间距很小
        }
        if features.gapIndexMiddle <= Constants.FistThreshold.indexMiddleGapMax {
            scoreFist += 1  // 食指中指间距很小
        }
        if features.indexToMiddleRatio <= Constants.FistThreshold.indexToMiddleRatioMax {
            scoreFist += 1  // 食指相对中指变短（都弯曲）
        }
        if features.ringToMiddleRatio <= Constants.FistThreshold.ringToMiddleRatioMax {
            scoreFist += 1  // 无名指相对中指变短
        }
        if features.littleToMiddleRatio <= Constants.FistThreshold.littleToMiddleRatioMax {
            scoreFist += 1  // 小指相对中指变短
        }

        // 食指手势打分
        if straightCount == Constants.IndexFingerThreshold.exactStraightCount {
            scoreIndexFinger += 3  // 只有一根手指伸直（关键特征）
        }
        if features.indexToMiddleRatio >= Constants.IndexFingerThreshold.indexToMiddleRatioMin {
            scoreIndexFinger += 2  // 食指比中指长
        }
        if features.ringToMiddleRatio <= Constants.IndexFingerThreshold.ringToMiddleRatioMax {
            scoreIndexFinger += 1  // 无名指明显短于中指（弯曲）
        }
        if features.littleToMiddleRatio <= Constants.IndexFingerThreshold.littleToMiddleRatioMax {
            scoreIndexFinger += 1  // 小指明显短于中指（弯曲）
        }
        if features.gapThumbIndex <= Constants.IndexFingerThreshold.thumbIndexGapMax {
            scoreIndexFinger += 1  // 拇指食指间距较小
        }

        // 额外区分逻辑：如果几何特征明显偏向 OK，就稍微提升 OK，压低 Palm
        if features.gapThumbIndex <= Constants.OKThreshold.thumbIndexGapMax &&
           features.gapIndexMiddle >= Constants.OKThreshold.indexMiddleGapMin &&
           features.indexToMiddleRatio <= Constants.OKThreshold.indexToMiddleRatioMax {
            // 典型 OK 手势：拇指和食指非常接近，食指明显变短，并且和中指之间间距变大
            scoreOK += 1
            scorePalm -= 1
        }

        return (scoreV, scoreOK, scorePalm, scoreFist, scoreIndexFinger)
    }

    // MARK: - 手势分类入口

    /// 基于特征向量进行分类（使用多特征打分机制）
    /// - Parameter features: 特征向量
    /// - Returns: 识别的手势类型
    func classify(features: HandGestureFeatureVector) -> HandGestureType {
        // 创建GestureFeatures（包含ratio计算）
        guard let gestureFeatures = makeFeatures(from: features) else {
            debugLogHandler?("未识别 ✗ | lenMiddle too small, cannot compute ratios")
            return .unknown
        }

        // 为五个手势打分
        let scores = scoreGestures(features: gestureFeatures, straightCount: features.straightCount)
        let (scoreV, scoreOK, scorePalm, scoreFist, scoreIndexFinger) = scores

        // 找出最高分
        let maxScore = max(scoreV, scoreOK, scorePalm, scoreFist, scoreIndexFinger)

        // 如果最高分低于阈值，返回unknown
        guard maxScore >= Constants.minAcceptScore else {
            // 准备调试信息
            var debugInfo: [String] = []
            debugInfo.append(String(format: "lenIdx:%.3f lenMid:%.3f lenRing:%.3f lenLit:%.3f", features.lenIndex, features.lenMiddle, features.lenRing, features.lenLittle))
            debugInfo.append(String(format: "gapIdxMid:%.3f gapThumbIdx:%.3f", features.indexMiddleGap, features.thumbIndexGap))
            debugInfo.append(String(format: "ratio idx/mid:%.2f ring/mid:%.2f lit/mid:%.2f", gestureFeatures.indexToMiddleRatio, gestureFeatures.ringToMiddleRatio, gestureFeatures.littleToMiddleRatio))
            debugInfo.append(String(format: "score V/OK/Palm/Fist/Idx = %d/%d/%d/%d/%d", scoreV, scoreOK, scorePalm, scoreFist, scoreIndexFinger))
            debugLogHandler?("未识别 ✗ | \(debugInfo.joined(separator: " | "))")

            // 构造调试信息
            let debugInfo_obj = HandGestureDebugInfo(
                gesture: .unknown,
                lenIndex: gestureFeatures.lenIndex,
                lenMiddle: gestureFeatures.lenMiddle,
                lenRing: gestureFeatures.lenRing,
                lenLittle: gestureFeatures.lenLittle,
                gapThumbIndex: gestureFeatures.gapThumbIndex,
                gapIndexMiddle: gestureFeatures.gapIndexMiddle,
                indexToMiddleRatio: gestureFeatures.indexToMiddleRatio,
                ringToMiddleRatio: gestureFeatures.ringToMiddleRatio,
                littleToMiddleRatio: gestureFeatures.littleToMiddleRatio,
                straightCount: features.straightCount,
                scoreV: scoreV,
                scoreOK: scoreOK,
                scorePalm: scorePalm,
                scoreFist: scoreFist,
                scoreIndexFinger: scoreIndexFinger
            )
            debugInfoHandler?(debugInfo_obj)

            return .unknown
        }

        // 按优先级选择最高分的手势
        let predicted: HandGestureType
        if scoreIndexFinger == maxScore {
            predicted = .indexFinger
        } else if scoreFist == maxScore {
            predicted = .fist
        } else if scoreV == maxScore {
            predicted = .vSign
        } else if scoreOK == maxScore {
            // 当 OK 和 Palm 打平时，优先认为是 OK 手势
            predicted = .okSign
        } else {
            predicted = .palm
        }

        // 准备调试信息
        var debugInfo: [String] = []
        debugInfo.append(String(format: "lenIdx:%.3f lenMid:%.3f lenRing:%.3f lenLit:%.3f", features.lenIndex, features.lenMiddle, features.lenRing, features.lenLittle))
        debugInfo.append(String(format: "gapIdxMid:%.3f gapThumbIdx:%.3f", features.indexMiddleGap, features.thumbIndexGap))
        debugInfo.append(String(format: "ratio idx/mid:%.2f ring/mid:%.2f lit/mid:%.2f", gestureFeatures.indexToMiddleRatio, gestureFeatures.ringToMiddleRatio, gestureFeatures.littleToMiddleRatio))
        debugInfo.append(String(format: "score V/OK/Palm/Fist/Idx = %d/%d/%d/%d/%d", scoreV, scoreOK, scorePalm, scoreFist, scoreIndexFinger))

        let gestureName: String
        switch predicted {
        case .vSign:
            gestureName = "V手势"
        case .okSign:
            gestureName = "OK手势"
        case .palm:
            gestureName = "手掌张开"
        case .fist:
            gestureName = "拳头"
        case .indexFinger:
            gestureName = "食指"
        default:
            gestureName = "未知"
        }
        debugLogHandler?("\(gestureName) ✓ | \(debugInfo.joined(separator: " | "))")

        // 构造调试信息
        let debugInfo_obj = HandGestureDebugInfo(
            gesture: predicted,
            lenIndex: gestureFeatures.lenIndex,
            lenMiddle: gestureFeatures.lenMiddle,
            lenRing: gestureFeatures.lenRing,
            lenLittle: gestureFeatures.lenLittle,
            gapThumbIndex: gestureFeatures.gapThumbIndex,
            gapIndexMiddle: gestureFeatures.gapIndexMiddle,
            indexToMiddleRatio: gestureFeatures.indexToMiddleRatio,
            ringToMiddleRatio: gestureFeatures.ringToMiddleRatio,
            littleToMiddleRatio: gestureFeatures.littleToMiddleRatio,
            straightCount: features.straightCount,
            scoreV: scoreV,
            scoreOK: scoreOK,
            scorePalm: scorePalm,
            scoreFist: scoreFist,
            scoreIndexFinger: scoreIndexFinger
        )
        debugInfoHandler?(debugInfo_obj)

        return predicted
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
}
