# Vision 手势识别 Demo

基于 Swift Vision 框架的手势识别演示项目，采用统计量驱动的智能识别系统。

## ✨ 主要功能

### iOS 应用
- **手势识别**：支持V手势、OK手势、手掌张开、拳头、食指
  - 基于统计量的智能识别
  - 远距离识别优化（特别是V手势）
  - 实时调试信息显示
- **人脸跟踪**：实时人脸检测和跟踪
- **目标跟踪**：通用物体跟踪
- **统计标定界面**（Debug模式）：
  - 手势数据采集
  - 特征统计分析
  - 阈值推荐

### 🐍 Python 分析工具（新增）
- **日志分析脚本**：`analyze_gesture_log.py`
  - 解析调试日志
  - 生成统计报告（CSV + Markdown）
  - 创建可视化图表（PNG）
  - 识别远距离识别问题
  - 对比正确/错误样本特征

## 🚀 快速开始

### 运行 iOS 应用

```bash
# 1. 打开项目
open vision_demo.xcodeproj

# 2. 在 Xcode 中选择目标设备并运行
```

### 使用 Python 分析工具

```bash
# 1. 安装依赖
pip install -r requirements.txt

# 2. 从 Xcode 控制台复制日志
# 在应用中摆出V手势，复制 [HandGestureDebug] 开头的行到文件

# 3. 运行分析
python analyze_gesture_log.py \
  --log-file v_gesture.log \
  --gt-gesture V \
  --output-dir ./v_analysis

# 4. 查看结果
cat v_analysis/stats_summary.md
open v_analysis/*.png  # macOS
```

详细使用说明请参考：[LOG_ANALYSIS_GUIDE.md](LOG_ANALYSIS_GUIDE.md)

## 📁 项目结构

```
vision_demo/
├── vision_demo/                    # iOS 应用源码
│   ├── CameraViewController.swift  # 主相机控制器
│   ├── HandGestureClassifier.swift # 手势识别核心逻辑
│   ├── HandGestureStatsManager.swift # 统计数据管理
│   ├── HandGestureType.swift       # 手势类型定义
│   ├── FaceDetector.swift          # 人脸检测
│   ├── ObjectTracker.swift         # 物体跟踪
│   └── TrackingView.swift          # 跟踪视图
├── analyze_gesture_log.py          # 日志分析主脚本 🆕
├── test_parse.py                   # 简化版测试脚本 🆕
├── requirements.txt                # Python 依赖 🆕
├── test_gesture.log                # 示例日志文件 🆕
└── 文档/
    ├── ANALYZE_LOG_README.md       # 分析工具基础文档
    ├── LOG_ANALYSIS_GUIDE.md       # 详细使用指南
    ├── PYTHON_TOOL_SUMMARY.md      # 工具功能总结
    ├── V_GESTURE_OPTIMIZATION.md   # V手势优化文档
    └── 完整实施总结.md              # 完整功能总结
```

## 🎯 核心特性

### 1. 统计量驱动的识别
- 摒弃硬编码阈值
- 基于实际数据统计
- 可自动推荐阈值

### 2. 远距离识别优化
- V手势远距离识别增强
- 基于比例特征而非绝对长度
- 手部尺寸检测和提示

### 3. Debug/Release 模式控制
- Debug 模式：完整调试信息和统计界面
- Release 模式：简洁的用户界面

### 4. 数据分析工作流
```
录制视频 → 采集日志 → Python分析 → 调整阈值 → 验证效果
  (iOS)      (iOS)      (Python)      (Swift)      (iOS)
```

## 💡 使用场景

### 场景1：优化 V 手势识别
1. 在应用中录制V手势视频（从近到远移动）
2. 复制 Xcode 日志到文件
3. 运行 Python 分析工具
4. 查看 far 组准确率和特征对比
5. 根据推荐调整 Swift 代码中的 Constants
6. 重新测试验证

### 场景2：校准多手势阈值
1. 分别采集 5 种手势的数据
2. 批量运行分析脚本
3. 对比各手势的特征范围
4. 调整阈值避免手势混淆

## 🛠 技术栈

### iOS
- Swift 5+
- UIKit
- AVFoundation
- Vision Framework

### Python
- pandas：数据处理
- numpy：数值计算
- matplotlib：可视化
- re：日志解析

## 📚 文档

- **[Python 分析工具使用指南](LOG_ANALYSIS_GUIDE.md)** - 详细教程和实际案例
- **[分析工具 README](ANALYZE_LOG_README.md)** - 基础说明和安装指南
- **[工具功能总结](PYTHON_TOOL_SUMMARY.md)** - 完整特性列表
- **[V 手势优化文档](V_GESTURE_OPTIMIZATION.md)** - 优化细节和原理
- **[完整实施总结](完整实施总结.md)** - 所有实现的功能

## 🔧 系统要求

### iOS 应用
- iOS 14.0+
- Xcode 12.0+
- 支持相机的设备

### Python 工具
- Python 3.7+
- pandas, numpy, matplotlib

## ❓ 常见问题

### Q: 如何获取调试日志？
A: 运行 iOS 应用，在 Xcode 控制台中搜索 `[HandGestureDebug]`，复制所有匹配行到文本文件。

### Q: Python 工具提示缺少依赖？
A: 运行 `pip install pandas numpy matplotlib` 安装依赖。如果系统限制，使用虚拟环境：
```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### Q: 如何调整手势识别阈值？
A: 在 `HandGestureClassifier.swift` 的 `Constants` 结构体中修改相应阈值。建议使用 Python 工具分析后再调整。

### Q: 统计标定界面在哪里？
A: 仅在 Debug 构建中可用。在应用顶部切换到"统计标定" Tab。

### Q: 测试脚本不需要依赖？
A: 是的！使用 `python test_parse.py test_gesture.log` 可以在不安装 pandas 的情况下验证日志解析功能。

## 📄 许可证

MIT License

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

---

**最后更新**: 2025-12-10 | **版本**: 2.0 (新增 Python 分析工具)
