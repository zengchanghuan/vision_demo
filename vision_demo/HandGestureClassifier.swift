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
        // MARK: - 手部大小检测
        
        /// 手部最小尺寸阈值（用于远距离检测）
        static let minHandSize: CGFloat = 0.08  // 手腕到食指尖距离的最小值
        /// 手指最小长度阈值（用于远距离V手势检测）
        static let minFingerLengthForV: CGFloat = 0.035  // lenIndex 或 lenMiddle 的最小值
        
        // MARK: - 基于统计量的阈值结构体

        /// V 手势阈值（优化远距离识别 - 基于比例特征）
        struct VThreshold {
            // V手势核心特征：食指中指间距（远距离最可靠的特征）
            static let indexMiddleGapMin: CGFloat = 0.025  // 降低阈值以适应远距离
            static let indexMiddleGapMax: CGFloat = 0.25   // 上限放宽
            
            // V手势比例特征：无名指和小指必须弯曲（相对于中指）
            static let ringToMiddleRatioMax: CGFloat = 0.80   // 无名指/中指 < 0.8
            static let littleToMiddleRatioMax: CGFloat = 0.80 // 小指/中指 < 0.8
            
            // V手势排除条件：手掌特征（所有手指都伸直）
            static let palmLikeRingRatioMin: CGFloat = 0.90   // ring/mid > 0.9 表示像手掌
            static let palmLikeLittleRatioMin: CGFloat = 0.90 // lit/mid > 0.9 表示像手掌
            static let palmLikeIndexRatioMin: CGFloat = 0.85  // |idx/mid - 1.0| < 0.15 表示像手掌
            static let palmLikeIndexRatioMax: CGFloat = 1.15
            
            // V手势排除条件：拳头/OK特征（拇指食指靠得很近）
            static let fistLikeThumbIndexGapMax: CGFloat = 0.02
            
            // V手势通常是2根手指伸直（食指和中指）
            static let maxStraightCount: Int = 3
            static let minScore: Int = 4
        }

        /// OK 手势阈值（基于统计量：thumbIndexGap≈0.043, indexToMiddleRatio≈0.70等）
        struct OKThreshold {
            /// OK 时拇指和食指几乎相接，这里把上限从 0.11 收紧到 0.08
            static let thumbIndexGapMax: CGFloat = 0.08
            // 基于OK手势indexMiddleGap mean≈0.18，V mean≈0.14，取略偏OK的值0.16
            static let indexMiddleGapMin: CGFloat = 0.16
            /// OK 时食指要明显短于中指，把上限从 0.90 收紧到 0.85
            static let indexToMiddleRatioMax: CGFloat = 0.85
            // 基于OK手势ringToMiddleRatio mean≈0.89，要求无名指接近中指长度
            static let ringToMiddleRatioMin: CGFloat = 0.90
            // 基于OK手势littleToMiddleRatio mean≈0.77
            static let littleToMiddleRatioMin: CGFloat = 0.85
            // OK手势至少还有3根手指伸直（中指、无名指等）
            static let minStraightCount: Int = 3
            static let minScore: Int = 3
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
            static let littleToMiddleRatioMin: CGFloat = 0.60   // 放宽小指长度要求
            // 手掌张开至少3根手指伸直
            static let minStraightCount: Int = 3                // 至少 3 根手指伸直即可
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
            
            // 【V手势强制减分】拳头不应该有以下特征
            static let vLikeGapThreshold: CGFloat = 0.025     // 如果 gapIdxMid > 0.025，强力减分
            static let vLikeStrongGapThreshold: CGFloat = 0.03 // 如果 gapIdxMid > 0.03，额外减分
            static let vLikeMinFingerLength: CGFloat = 0.05    // 如果 min(lenIdx, lenMid) > 0.05，减分
            
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
        /// 平均指长太小说明手还没真正举到画面中，直接视作 unknown，避免凭噪声判成"食指"
        static let minAvgFingerLengthForValidHand: CGFloat = 0.02
        
        // MARK: - 手势置信度阈值和margin配置
        
        /// 每种手势的最低分数阈值（低于此阈值返回 unknown）
        struct GestureThreshold {
            static let vSign: Int = 4      // 降低V手势的阈值，便于远距离识别
            static let okSign: Int = 4
            static let palm: Int = 5
            static let fist: Int = 5
            static let indexFinger: Int = 5
        }
        
        /// 每种手势与第二高分的最小差距（低于此差距说明不够稳定，返回 unknown）
        struct GestureMargin {
            static let vSign: Int = 2
            static let okSign: Int = 2
            static let palm: Int = 2
            static let fist: Int = 2
            static let indexFinger: Int = 2
        }
        
        // MARK: - 连续帧稳定判决配置
        
        /// 连续帧稳定判决的队列长度
        static let stabilityQueueLength: Int = 8
        /// 连续帧中某手势出现的最小次数（绝对值）
        static let minOccurrences: Int = 3
        /// 连续帧中某手势出现的最小比例（相对于非unknown的有效帧）
        static let minOccurrenceRatio: CGFloat = 0.6
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
    
    // MARK: - 连续帧稳定判决
    
    /// 连续帧稳定判决器
    private class StabilityFilter {
        private var recentPredictions: [HandGestureType] = []
        private var currentOutput: HandGestureType = .unknown
        private let maxLength: Int
        private let minOccurrences: Int
        private let minRatio: CGFloat
        
        init(maxLength: Int, minOccurrences: Int, minRatio: CGFloat) {
            self.maxLength = maxLength
            self.minOccurrences = minOccurrences
            self.minRatio = minRatio
        }
        
        /// 添加新的预测结果并返回稳定的输出
        func addPrediction(_ gesture: HandGestureType) -> HandGestureType {
            // 添加到队列
            recentPredictions.append(gesture)
            if recentPredictions.count > maxLength {
                recentPredictions.removeFirst()
            }
            
            // 统计非 unknown 的手势分布
            let validGestures = recentPredictions.filter { $0 != .unknown }
            guard !validGestures.isEmpty else {
                return currentOutput  // 全是 unknown，保持上一帧输出
            }
            
            // 统计每种手势的出现次数
            var counts: [HandGestureType: Int] = [:]
            for gesture in validGestures {
                counts[gesture, default: 0] += 1
            }
            
            // 找出出现次数最多的手势
            guard let (mostFrequent, count) = counts.max(by: { $0.value < $1.value }) else {
                return currentOutput
            }
            
            // 检查是否满足稳定条件
            let validCount = validGestures.count
            let ratio = CGFloat(count) / CGFloat(validCount)
            
            if count >= minOccurrences && ratio >= minRatio {
                currentOutput = mostFrequent
            }
            // 否则保持上一帧输出
            
            return currentOutput
        }
        
        /// 重置状态
        func reset() {
            recentPredictions.removeAll()
            currentOutput = .unknown
        }
    }
    
    private var stabilityFilter = StabilityFilter(
        maxLength: Constants.stabilityQueueLength,
        minOccurrences: Constants.minOccurrences,
        minRatio: Constants.minOccurrenceRatio
    )

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
        
        // 预先计算通用的派生特征
        let minFingerLen = min(features.lenIndex, features.lenMiddle)
        let indexMiddleRatioDiff = abs(features.indexToMiddleRatio - 1.0)

        // V手势打分 - 优化远距离识别（基于比例特征 + 间距）
        // 核心思想：减少对绝对长度的依赖，更多使用ratio和gap
        
        // 1. 核心特征：食指中指间距（V手势的最明显特征）
        if features.gapIndexMiddle > Constants.VThreshold.indexMiddleGapMin {
            scoreV += 4  // 强权重：食指中指分开是V的核心特征
        }
        
        // 2. 关键区分：无名指和小指必须弯曲（相对中指短）
        if features.ringToMiddleRatio < Constants.VThreshold.ringToMiddleRatioMax &&
           features.littleToMiddleRatio < Constants.VThreshold.littleToMiddleRatioMax {
            scoreV += 4  // 强权重：后两指弯曲是V vs Palm的关键
        } else {
            scoreV -= 3  // 如果后两指伸直，更可能是手掌
        }
        
        // 3. 最小手指长度检查（远距离保护）
        if minFingerLen > Constants.minFingerLengthForV {
            scoreV += 2  // 手指足够长，不是噪声
        }
        
        // 4. 排除手掌特征：所有手指都伸直且比例接近
        if features.ringToMiddleRatio > Constants.VThreshold.palmLikeRingRatioMin &&
           features.littleToMiddleRatio > Constants.VThreshold.palmLikeLittleRatioMin &&
           indexMiddleRatioDiff < 0.15 {
            scoreV -= 4  // 明显的手掌特征，不是V
        }
        
        // 5. 排除拳头/OK特征：拇指食指靠得太近
        if features.gapThumbIndex < Constants.VThreshold.fistLikeThumbIndexGapMax {
            scoreV -= 3  // 拇指食指靠近，更像拳头或OK
        }
        
        // 6. straightCount作为辅助（不作为主要特征）
        if straightCount <= Constants.VThreshold.maxStraightCount {
            scoreV += 1  // 轻权重：通常2根手指伸直
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
            scoreOK += 1  // 至少还有3根手指伸直
        }

        // 新增：如果整体更像"手掌张开"（食指不短 + 拇指张得很开），给 OK 一个惩罚，避免和手掌混淆
        // 日志中这类帧的典型特征：
        //  - indexToMiddleRatio ≈ 1.05 ~ 1.15
        //  - gapThumbIndex    ≈ 0.10 以上
        if features.indexToMiddleRatio > 0.95 && features.gapThumbIndex > 0.07 {
            scoreOK -= 2
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
        
        // 关键区分点：手掌要求无名指和小指尽量伸直
        if features.ringToMiddleRatio >= Constants.PalmThreshold.ringToMiddleRatioMin {
            scorePalm += 2   // 无名指比较长（加强权重）
        } else {
            scorePalm -= 1   // 不再强扣 2 分，只扣 1 分
        }
        
        if features.littleToMiddleRatio >= Constants.PalmThreshold.littleToMiddleRatioMin {
            // 小指够长就加一点分，不够长也不扣分
            scorePalm += 1
        }
        
        if straightCount >= Constants.PalmThreshold.minStraightCount {
            scorePalm += 1   // 至少 3 根手指伸直
        }

        // 拳头打分 + V手势强制减分
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
        
        // 【V手势强制减分】如果特征明显偏向V手势，大幅降低Fist得分
        // 注意：minFingerLen 已在函数开头定义
        
        // 核心V特征：后两指弯曲 + 食指中指分开
        if features.ringToMiddleRatio < 0.8 && 
           features.littleToMiddleRatio < 0.8 && 
           features.gapIndexMiddle > Constants.FistThreshold.vLikeGapThreshold {
            scoreFist -= 4  // 强力减分：这是明显的V手势特征
        }
        
        // 辅助特征：食指中指间距很大
        if features.gapIndexMiddle > Constants.FistThreshold.vLikeStrongGapThreshold {
            scoreFist -= 2  // 额外减分：间距太大不像拳头
        }
        
        // 辅助特征：手指长度足够
        if minFingerLen > Constants.FistThreshold.vLikeMinFingerLength {
            scoreFist -= 2  // 额外减分：手指太长不像拳头
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

        // 额外约束：如果伸直的手指超过 1 根，就逐步降低"食指手势"的置信度
        if straightCount > Constants.IndexFingerThreshold.exactStraightCount {
            scoreIndexFinger -= (straightCount - Constants.IndexFingerThreshold.exactStraightCount)
            // 例如 straightCount = 3 时，额外扣 2 分
        }

        // 额外区分逻辑：如果几何特征明显偏向 OK，就稍微提升 OK，压低 Palm
        if features.gapThumbIndex <= Constants.OKThreshold.thumbIndexGapMax &&
           features.gapIndexMiddle >= Constants.OKThreshold.indexMiddleGapMin &&
           features.indexToMiddleRatio <= Constants.OKThreshold.indexToMiddleRatioMax {
            // 典型 OK 手势：拇指和食指非常接近，食指明显变短，并且和中指之间间距变大
            scoreOK += 1
            scorePalm -= 1
        }
        
        // 【临时启发式】TODO: 未来将被统计驱动的规则替换
        // 问题：OK手势（thumbIdxGap≈0.006, straightCount=2）被误判为Fist
        // 修复：当拇指食指非常靠近且有手指伸直时，强化OK手势判定
        if features.gapThumbIndex < 0.02 && straightCount >= 2 {
            scoreOK += 2  // OK手势额外加权
            scoreFist -= 1  // 降低Fist的竞争力
        }
        
        // 【临时启发式】Fist手势特征强化
        // 当几乎没有手指伸直且拇指食指有一定间距时，更可能是Fist而非OK
        if straightCount <= 1 && features.gapThumbIndex > 0.02 {
            scoreFist += 1  // 明确的Fist特征
            scoreOK -= 1
        }

        return (scoreV, scoreOK, scorePalm, scoreFist, scoreIndexFinger)
    }

    // MARK: - 手势分类入口

    /// 基于特征向量进行分类（使用多特征打分机制）
    /// - Parameter features: 特征向量
    /// - Returns: 识别的手势类型
    func classify(features: HandGestureFeatureVector) -> HandGestureType {
        // 1. 检查手部大小（远距离检测）
        let handSize = features.wristToIndexTip  // 手腕到食指尖的距离
        if handSize < Constants.minHandSize {
            debugLogHandler?(
                String(
                    format: "[HandGestureDebug] 手部太远(handSize=%.3f < %.3f) | 请把手靠近摄像头",
                    handSize, Constants.minHandSize
                )
            )
            return .unknown
        }
        
        // 2. 创建GestureFeatures（包含ratio计算）
        guard let gestureFeatures = makeFeatures(from: features) else {
            debugLogHandler?("未识别 ✗ | lenMiddle too small, cannot compute ratios")
            return .unknown
        }

        // 3. 先做一层"是否真的有手"的过滤：
        // 如果四个手指长度的平均值非常小，说明手还没举到画面里，
        // 此时很多比值特征会非常不稳定，容易被误判为"食指"。
        let avgLen = (gestureFeatures.lenIndex
                      + gestureFeatures.lenMiddle
                      + gestureFeatures.lenRing
                      + gestureFeatures.lenLittle) / 4.0
        if avgLen < Constants.minAvgFingerLengthForValidHand {
            debugLogHandler?(
                String(
                    format: "[HandGestureDebug] 无效手势(平均指长过小) | lenIdx:%.3f lenMid:%.3f lenRing:%.3f lenLit:%.3f avgLen:%.3f",
                    gestureFeatures.lenIndex,
                    gestureFeatures.lenMiddle,
                    gestureFeatures.lenRing,
                    gestureFeatures.lenLittle,
                    avgLen
                )
            )
            return .unknown
        }

        // 为五个手势打分
        let scores = scoreGestures(features: gestureFeatures, straightCount: features.straightCount)
        let (scoreV, scoreOK, scorePalm, scoreFist, scoreIndexFinger) = scores

        // 创建分数数组用于排序
        let scoreArray: [(HandGestureType, Int)] = [
            (.vSign, scoreV),
            (.okSign, scoreOK),
            (.palm, scorePalm),
            (.fist, scoreFist),
            (.indexFinger, scoreIndexFinger)
        ]
        
        // 按分数降序排序
        let sortedScores = scoreArray.sorted { $0.1 > $1.1 }
        let (bestGesture, bestScore) = sortedScores[0]
        let secondScore = sortedScores[1].1
        
        // 获取最佳手势的阈值和margin
        let threshold: Int
        let margin: Int
        
        switch bestGesture {
        case .vSign:
            threshold = Constants.GestureThreshold.vSign
            margin = Constants.GestureMargin.vSign
        case .okSign:
            threshold = Constants.GestureThreshold.okSign
            margin = Constants.GestureMargin.okSign
        case .palm:
            threshold = Constants.GestureThreshold.palm
            margin = Constants.GestureMargin.palm
        case .fist:
            threshold = Constants.GestureThreshold.fist
            margin = Constants.GestureMargin.fist
        case .indexFinger:
            threshold = Constants.GestureThreshold.indexFinger
            margin = Constants.GestureMargin.indexFinger
        default:
            threshold = Constants.minAcceptScore
            margin = 2
        }
        
        // 检查是否满足阈值和margin条件
        let predicted: HandGestureType
        if bestScore < threshold || (bestScore - secondScore) < margin {
            // 不满足条件，返回 unknown
            predicted = .unknown
        } else {
            predicted = bestGesture
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
    
    /// 基于特征向量进行分类（带连续帧稳定判决）
    /// - Parameter features: 特征向量
    /// - Returns: 稳定后的识别手势类型
    mutating func classifyWithStability(features: HandGestureFeatureVector) -> HandGestureType {
        let rawPrediction = classify(features: features)
        return stabilityFilter.addPrediction(rawPrediction)
    }
    
    /// 重置连续帧稳定判决器
    mutating func resetStability() {
        stabilityFilter.reset()
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

// MARK: - 统计与标定相关结构体

/// 单帧手势特征的统计样本
struct GestureSample {
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

/// 某个特征的统计结果
struct FeatureStats {
    let min: CGFloat
    let max: CGFloat
    let mean: CGFloat
    let std: CGFloat  // 标准差
    let count: Int
}

/// 手势标定会话
class CalibrationSession {
    let targetGesture: HandGestureType
    private(set) var samples: [GestureSample] = []
    private(set) var isRecording: Bool = false
    
    init(targetGesture: HandGestureType) {
        self.targetGesture = targetGesture
    }
    
    /// 开始采样
    func startRecording() {
        samples.removeAll()
        isRecording = true
    }
    
    /// 停止采样
    func stopRecording() {
        isRecording = false
    }
    
    /// 添加一帧样本
    func addSample(_ sample: GestureSample) {
        guard isRecording else { return }
        samples.append(sample)
    }
    
    /// 计算统计结果
    func computeStats() -> [String: FeatureStats] {
        guard !samples.isEmpty else { return [:] }
        
        var stats: [String: FeatureStats] = [:]
        
        // 计算各个特征的统计量
        let features: [(String, (GestureSample) -> CGFloat)] = [
            ("lenIndex", { $0.lenIndex }),
            ("lenMiddle", { $0.lenMiddle }),
            ("lenRing", { $0.lenRing }),
            ("lenLittle", { $0.lenLittle }),
            ("gapThumbIndex", { $0.gapThumbIndex }),
            ("gapIndexMiddle", { $0.gapIndexMiddle }),
            ("indexToMiddleRatio", { $0.indexToMiddleRatio }),
            ("ringToMiddleRatio", { $0.ringToMiddleRatio }),
            ("littleToMiddleRatio", { $0.littleToMiddleRatio })
        ]
        
        for (name, extractor) in features {
            let values = samples.map { extractor($0) }
            let min = values.min() ?? 0
            let max = values.max() ?? 0
            let mean = values.reduce(0, +) / CGFloat(values.count)
            
            // 计算标准差
            let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / CGFloat(values.count)
            let std = sqrt(variance)
            
            stats[name] = FeatureStats(min: min, max: max, mean: mean, std: std, count: values.count)
        }
        
        return stats
    }
    
    /// 生成基于统计量的阈值推荐
    /// - Returns: 阈值推荐文本
    func recommendedThresholds() -> String {
        let stats = computeStats()
        guard !stats.isEmpty else { return "没有足够的样本数据生成推荐" }
        
        var recommendations: [String] = []
        recommendations.append("\n===== 阈值推荐 for \(targetGesture.rawValue) =====\n")
        recommendations.append("基于 \(samples.count) 个样本的统计分析\n")
        recommendations.append(String(repeating: "=", count: 50) + "\n")
        
        // 关键特征的推荐阈值
        let keyFeatures = ["gapThumbIndex", "gapIndexMiddle", "indexToMiddleRatio", 
                          "ringToMiddleRatio", "littleToMiddleRatio"]
        
        for featureName in keyFeatures {
            guard let stat = stats[featureName] else { continue }
            
            recommendations.append("\n\(featureName):")
            recommendations.append(String(format: "  统计: mean=%.3f, std=%.3f", stat.mean, stat.std))
            recommendations.append(String(format: "  范围: [%.3f, %.3f]", stat.min, stat.max))
            
            // 基于 mean ± k*std 推荐合理区间
            let lowerBound = max(0, stat.mean - 2.5 * stat.std)
            let upperBound = stat.mean + 2.5 * stat.std
            recommendations.append(String(format: "  推荐区间: [%.3f, %.3f] (mean ± 2.5*std)", lowerBound, upperBound))
            
            // 针对不同手势给出具体建议
            switch targetGesture {
            case .okSign:
                if featureName == "gapThumbIndex" {
                    recommendations.append("  💡 OK手势建议: 拇指食指间距应该很小")
                    recommendations.append(String(format: "     设置 thumbIndexGapMax ≈ %.3f", upperBound))
                } else if featureName == "indexToMiddleRatio" {
                    recommendations.append("  💡 OK手势建议: 食指弯曲变短")
                    recommendations.append(String(format: "     设置 indexToMiddleRatioMax ≈ %.3f", upperBound))
                }
                
            case .vSign:
                if featureName == "gapThumbIndex" {
                    recommendations.append("  💡 V手势建议: 拇指食指间距较大")
                    recommendations.append(String(format: "     设置 thumbIndexGapMin ≈ %.3f", lowerBound))
                } else if featureName == "ringToMiddleRatio" {
                    recommendations.append("  💡 V手势建议: 无名指应该弯曲（短）")
                    recommendations.append(String(format: "     设置 ringToMiddleRatioMax ≈ %.3f", upperBound))
                }
                
            case .palm:
                if featureName == "gapIndexMiddle" {
                    recommendations.append("  💡 手掌建议: 手指并拢，间距小")
                    recommendations.append(String(format: "     设置 indexMiddleGapMax ≈ %.3f", upperBound))
                } else if featureName == "ringToMiddleRatio" {
                    recommendations.append("  💡 手掌建议: 无名指伸直，接近中指长度")
                    recommendations.append(String(format: "     设置 ringToMiddleRatioMin ≈ %.3f", lowerBound))
                }
                
            case .fist:
                if featureName == "gapThumbIndex" {
                    recommendations.append("  💡 拳头建议: 所有手指弯曲，间距小")
                    recommendations.append(String(format: "     设置 thumbIndexGapMax ≈ %.3f", upperBound))
                }
                
            case .indexFinger:
                if featureName == "indexToMiddleRatio" {
                    recommendations.append("  💡 食指建议: 食指伸直，比中指长")
                    recommendations.append(String(format: "     设置 indexToMiddleRatioMin ≈ %.3f", lowerBound))
                }
                
            default:
                break
            }
        }
        
        // straightCount 统计
        let straightCounts = samples.map { $0.straightCount }
        if !straightCounts.isEmpty {
            let countDict = Dictionary(grouping: straightCounts, by: { $0 }).mapValues { $0.count }
            let mode = countDict.max { $0.value < $1.value }?.key ?? 0
            let modePercent = Double(countDict[mode] ?? 0) / Double(straightCounts.count) * 100
            
            recommendations.append("\nstraightCount:")
            recommendations.append(String(format: "  众数: %d (出现率 %.1f%%)", mode, modePercent))
            recommendations.append("  💡 建议: 将此值作为该手势的典型伸直手指数")
        }
        
        recommendations.append("\n" + String(repeating: "=", count: 50))
        recommendations.append("\n如何应用这些推荐:")
        recommendations.append("1. 在 HandGestureClassifier.Constants 中找到对应手势的阈值结构体")
        recommendations.append("2. 根据上述统计量调整阈值参数")
        recommendations.append("3. 建议采集多个手势的数据后，对比各手势的区间是否有重叠")
        recommendations.append("4. 如果区间重叠，需要引入其他特征来辅助区分\n")
        
        return recommendations.joined(separator: "\n")
    }
    
    /// 生成统计摘要字符串（用于控制台输出）
    func generateSummary() -> String {
        let stats = computeStats()
        guard !stats.isEmpty else { return "No samples collected" }
        
        var summary = "\n===== Calibration Summary for \(targetGesture) =====\n"
        summary += "Total samples: \(samples.count)\n\n"
        
        let featureOrder = ["lenIndex", "lenMiddle", "lenRing", "lenLittle",
                           "gapThumbIndex", "gapIndexMiddle",
                           "indexToMiddleRatio", "ringToMiddleRatio", "littleToMiddleRatio"]
        
        for name in featureOrder {
            if let stat = stats[name] {
                summary += String(format: "%20s: min=%.3f, max=%.3f, mean=%.3f, std=%.3f\n",
                                name, stat.min, stat.max, stat.mean, stat.std)
            }
        }
        
        // 分数统计
        let scoreV = samples.map { $0.scoreV }
        let scoreOK = samples.map { $0.scoreOK }
        let scorePalm = samples.map { $0.scorePalm }
        let scoreFist = samples.map { $0.scoreFist }
        let scoreIdx = samples.map { $0.scoreIndexFinger }
        
        summary += "\nScore Statistics:\n"
        summary += String(format: "  V:     min=%d, max=%d, mean=%.1f\n",
                         scoreV.min() ?? 0, scoreV.max() ?? 0,
                         Double(scoreV.reduce(0, +)) / Double(scoreV.count))
        summary += String(format: "  OK:    min=%d, max=%d, mean=%.1f\n",
                         scoreOK.min() ?? 0, scoreOK.max() ?? 0,
                         Double(scoreOK.reduce(0, +)) / Double(scoreOK.count))
        summary += String(format: "  Palm:  min=%d, max=%d, mean=%.1f\n",
                         scorePalm.min() ?? 0, scorePalm.max() ?? 0,
                         Double(scorePalm.reduce(0, +)) / Double(scorePalm.count))
        summary += String(format: "  Fist:  min=%d, max=%d, mean=%.1f\n",
                         scoreFist.min() ?? 0, scoreFist.max() ?? 0,
                         Double(scoreFist.reduce(0, +)) / Double(scoreFist.count))
        summary += String(format: "  Index: min=%d, max=%d, mean=%.1f\n",
                         scoreIdx.min() ?? 0, scoreIdx.max() ?? 0,
                         Double(scoreIdx.reduce(0, +)) / Double(scoreIdx.count))
        
        summary += "==================================================\n"
        
        // 添加阈值推荐
        summary += recommendedThresholds()
        
        return summary
    }
}
