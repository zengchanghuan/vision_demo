import Foundation
import CoreGraphics

/// 手势特征统计管理器
final class HandGestureStatsManager {

    // MARK: - 数据结构

    /// 单个样本
    struct Sample {
        let groundTruth: HandGestureType    // 真实手势
        let predicted: HandGestureType      // 预测手势
        let features: HandGestureClassifier.HandGestureFeatureVector
    }

    /// 特征统计量
    struct FeatureStats {
        let count: Int
        let min: CGFloat
        let max: CGFloat
        let mean: CGFloat
        let std: CGFloat  // 标准差
    }

    // MARK: - 私有属性

    /// 所有样本
    private var samples: [Sample] = []

    /// 混淆矩阵：groundTruth -> predicted -> count
    private var confusionMatrix: [HandGestureType: [HandGestureType: Int]] = [:]

    // MARK: - 公共方法

    /// 记录一个样本
    /// - Parameters:
    ///   - groundTruth: 真实手势
    ///   - predicted: 预测手势
    ///   - features: 特征向量
    func recordSample(groundTruth: HandGestureType,
                      predicted: HandGestureType,
                      features: HandGestureClassifier.HandGestureFeatureVector) {
        let sample = Sample(groundTruth: groundTruth, predicted: predicted, features: features)
        samples.append(sample)

        // 更新混淆矩阵
        var predictions = confusionMatrix[groundTruth] ?? [:]
        predictions[predicted] = (predictions[predicted] ?? 0) + 1
        confusionMatrix[groundTruth] = predictions
    }

    /// 获取指定手势和特征的统计量
    /// - Parameters:
    ///   - gesture: 手势类型
    ///   - keyPath: 特征字段路径
    /// - Returns: 统计量，如果没有样本返回 nil
    func stats(for gesture: HandGestureType,
               feature keyPath: KeyPath<HandGestureClassifier.HandGestureFeatureVector, CGFloat>) -> FeatureStats? {
        let gestureSamples = samples.filter { $0.groundTruth == gesture }
        guard !gestureSamples.isEmpty else { return nil }

        let values = gestureSamples.map { $0.features[keyPath: keyPath] }
        return calculateStats(values: values)
    }

    /// 获取指定手势的所有样本数量
    /// - Parameter gesture: 手势类型
    /// - Returns: 样本数量
    func sampleCount(for gesture: HandGestureType) -> Int {
        return samples.filter { $0.groundTruth == gesture }.count
    }

    /// 生成调试摘要文本
    /// - Returns: 格式化的统计摘要
    func debugSummaryText() -> String {
        var lines: [String] = []
        lines.append(String(repeating: "=", count: 60))
        lines.append("手势特征统计摘要")
        lines.append(String(repeating: "=", count: 60))
        lines.append("")

        // 按手势类型显示统计
        let gestureTypes: [HandGestureType] = [.vSign, .okSign, .palm, .fist, .indexFinger, .unknown]

        for gesture in gestureTypes {
            let count = sampleCount(for: gesture)
            guard count > 0 else { continue }

            lines.append("=== Gesture: \(gesture.rawValue) ===")
            lines.append("样本帧数: \(count)")
            lines.append("")

            // 显示关键特征的统计
            let keyFeatures: [(String, KeyPath<HandGestureClassifier.HandGestureFeatureVector, CGFloat>)] = [
                ("thumbIndexGap", \HandGestureClassifier.HandGestureFeatureVector.thumbIndexGap),
                ("indexMiddleGap", \HandGestureClassifier.HandGestureFeatureVector.indexMiddleGap),
                ("lenIndex", \HandGestureClassifier.HandGestureFeatureVector.lenIndex),
                ("lenMiddle", \HandGestureClassifier.HandGestureFeatureVector.lenMiddle),
                ("lenRing", \HandGestureClassifier.HandGestureFeatureVector.lenRing),
                ("lenLittle", \HandGestureClassifier.HandGestureFeatureVector.lenLittle),
                ("thumbIndexGapNorm", \HandGestureClassifier.HandGestureFeatureVector.thumbIndexGapNorm),
                ("indexMiddleGapNorm", \HandGestureClassifier.HandGestureFeatureVector.indexMiddleGapNorm),
                ("lenIndexNorm", \HandGestureClassifier.HandGestureFeatureVector.lenIndexNorm),
                ("lenMiddleNorm", \HandGestureClassifier.HandGestureFeatureVector.lenMiddleNorm)
            ]

            for (name, keyPath) in keyFeatures {
                if let stats = self.stats(for: gesture, feature: keyPath) {
                    lines.append(String(format: "%@: count=%d, min=%.3f, max=%.3f, mean=%.3f, std=%.3f",
                                      name, stats.count, stats.min, stats.max, stats.mean, stats.std))
                }
            }

            lines.append("")
        }

        // 显示混淆矩阵
        lines.append("混淆矩阵 (groundTruth -> predicted):")
        for groundTruth in gestureTypes {
            guard let predictions = confusionMatrix[groundTruth] else { continue }
            for predicted in gestureTypes {
                if let count = predictions[predicted], count > 0 {
                    lines.append("  \(groundTruth.rawValue) -> \(predicted.rawValue): \(count)")
                }
            }
        }
        lines.append("")

        // 生成阈值建议
        lines.append(generateThresholdSuggestions())

        return lines.joined(separator: "\n")
    }

    /// 重置所有统计
    func reset() {
        samples.removeAll()
        confusionMatrix.removeAll()
    }

    // MARK: - 私有方法

    /// 计算统计量
    private func calculateStats(values: [CGFloat]) -> FeatureStats? {
        guard !values.isEmpty else { return nil }

        let count = values.count
        let min = values.min() ?? 0
        let max = values.max() ?? 0
        let mean = values.reduce(0, +) / CGFloat(count)

        // 计算标准差
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / CGFloat(count)
        let std = sqrt(variance)

        return FeatureStats(count: count, min: min, max: max, mean: mean, std: std)
    }

    /// 生成阈值建议文本
    private func generateThresholdSuggestions() -> String {
        var lines: [String] = []
        lines.append(String(repeating: "=", count: 60))
        lines.append("阈值建议")
        lines.append(String(repeating: "=", count: 60))
        lines.append("")

        // 关键特征列表
        let keyFeatures: [(String, KeyPath<HandGestureClassifier.HandGestureFeatureVector, CGFloat>)] = [
            ("thumbIndexGap", \HandGestureClassifier.HandGestureFeatureVector.thumbIndexGap),
            ("indexMiddleGap", \HandGestureClassifier.HandGestureFeatureVector.indexMiddleGap),
            ("lenIndex", \HandGestureClassifier.HandGestureFeatureVector.lenIndex),
            ("lenMiddle", \HandGestureClassifier.HandGestureFeatureVector.lenMiddle),
            ("thumbIndexGapNorm", \HandGestureClassifier.HandGestureFeatureVector.thumbIndexGapNorm),
            ("indexMiddleGapNorm", \HandGestureClassifier.HandGestureFeatureVector.indexMiddleGapNorm)
        ]

        for (featureName, keyPath) in keyFeatures {
            lines.append("// \(featureName):")

            var gestureStats: [HandGestureType: FeatureStats] = [:]
            for gesture in [HandGestureType.vSign, .okSign, .palm, .fist, .indexFinger] {
                if let stats = self.stats(for: gesture, feature: keyPath) {
                    gestureStats[gesture] = stats
                    lines.append("//   \(gesture.rawValue):    min=\(String(format: "%.3f", stats.min)), max=\(String(format: "%.3f", stats.max)), mean=\(String(format: "%.3f", stats.mean))")
                }
            }

            // 分析区间重叠并提供建议
            if gestureStats.count >= 2 {
                lines.append("// 建议：")

                // 检查 V 手势和其他手势的区分
                if let vStats = gestureStats[.vSign] {
                    if let okStats = gestureStats[.okSign] {
                        if vStats.min > okStats.max {
                            lines.append("//   1) 判 V 时，\(featureName) > \(String(format: "%.3f", okStats.max)) 比较安全（能和 OK 拉开）")
                        } else if vStats.max < okStats.min {
                            lines.append("//   1) 判 V 时，\(featureName) < \(String(format: "%.3f", okStats.min)) 比较安全")
                        } else {
                            lines.append("//   1) V 和 OK 区间有重叠，需要引入其他特征辅助区分")
                        }
                    }

                    if let palmStats = gestureStats[.palm] {
                        if vStats.min > palmStats.max || vStats.max < palmStats.min {
                            lines.append("//   2) V 和 Palm 区间不重叠，可以区分")
                        } else {
                            lines.append("//   2) V 和 Palm 区间有重叠，需要引入其他特征辅助区分")
                        }
                    }
                }

                // 检查 OK 手势
                if let okStats = gestureStats[.okSign] {
                    if let palmStats = gestureStats[.palm] {
                        if okStats.max < palmStats.min {
                            lines.append("//   3) 判 OK 时，\(featureName) < \(String(format: "%.3f", palmStats.min)) 比较安全")
                        } else {
                            lines.append("//   3) OK 和 Palm 区间有重叠，需要引入其他特征辅助区分")
                        }
                    }
                }
            }

            lines.append("")
        }

        lines.append("// 如何更新阈值：")
        lines.append("// 1. 根据上述统计量，在 HandGestureClassifier.Constants 中调整对应阈值")
        lines.append("// 2. 如果区间重叠，考虑使用多个特征组合判断")
        lines.append("// 3. 建议阈值选择在非目标手势的最大值和目标手势的最小值之间")
        lines.append("")

        return lines.joined(separator: "\n")
    }
}
