# 手势识别日志分析工具

## 功能说明

这是一个用于分析手势识别调试日志的Python脚本，可以：
- 解析日志文件中的特征数据
- 生成统计报告（CSV + Markdown）
- 创建可视化图表（PNG）
- 分析远距离识别问题（特别是V手势）

## 环境设置

### 方法1：使用虚拟环境（推荐）

```bash
# 创建虚拟环境
python3 -m venv venv

# 激活虚拟环境
source venv/bin/activate  # macOS/Linux
# 或
venv\Scripts\activate  # Windows

# 安装依赖
pip install -r requirements.txt
```

### 方法2：使用系统Python（需要权限）

```bash
# 如果系统允许，可以直接安装
pip3 install pandas numpy matplotlib

# 或使用--break-system-packages标志（不推荐）
pip3 install --break-system-packages pandas numpy matplotlib
```

### 方法3：使用conda

```bash
conda create -n gesture python=3.9
conda activate gesture
conda install pandas numpy matplotlib
```

## 使用方法

### 基本用法

```bash
python analyze_gesture_log.py --log-file debug.log
```

### 指定Ground Truth

```bash
# 分析V手势的日志
python analyze_gesture_log.py --log-file v_gesture.log --gt-gesture V --output-dir ./v_results

# 分析OK手势的日志
python analyze_gesture_log.py --log-file ok_gesture.log --gt-gesture OK --output-dir ./ok_results
```

### 不生成图表

```bash
python analyze_gesture_log.py --log-file test.log --no-plots
```

## 日志格式要求

日志文件应包含如下格式的行：

```
[HandGestureDebug] V手势 ✓ | lenIdx:0.145 lenMid:0.152 lenRing:0.089 lenLit:0.078 | gapIdxMid:0.089 gapThumbIdx:0.234 | ratio idx/mid:0.95 ring/mid:0.58 lit/mid:0.51 | score V/OK/Palm/Fist/Idx = 8/1/2/-2/0
```

## 输出文件

脚本会在输出目录生成以下文件：

- `gesture_parsed.csv` - 解析后的完整数据表
- `stats_summary.md` - 统计分析报告（Markdown格式）
- `hist_scale_by_group.png` - scale分布直方图
- `scatter_scale_vs_score_v.png` - scale vs score_v散点图
- `scatter_idxmidratio_vs_score_v_correct_wrong.png` - V手势特定分析图（仅当GT=V时）

## 参数说明

- `--log-file`: （必需）输入日志文件路径
- `--output-dir`: 输出结果目录，默认为当前目录
- `--gt-gesture`: Ground Truth手势，可选值：V, OK, Palm, Fist, Idx
- `--save-plots` / `--no-plots`: 是否生成图表，默认生成

## 示例

项目包含了一个测试日志文件 `test_gesture.log`，可以用来测试脚本：

```bash
# 测试脚本
python analyze_gesture_log.py --log-file test_gesture.log --gt-gesture V --output-dir ./test_results
```

## 数据分析要点

### 关注指标

1. **准确率（如果指定GT）**
   - 总体准确率
   - far/mid/near组的准确率差异

2. **score_v分布**
   - 远距离时是否偏低
   - 与scale的相关性

3. **特征对比（正确vs错误）**
   - 哪些特征能区分正确/错误样本
   - 建议的阈值调整方向

### V手势优化建议

查看以下图表和统计：
1. `scatter_scale_vs_score_v.png` - 识别远距离时score_v是否下降
2. `scatter_idxmidratio_vs_score_v_correct_wrong.png` - 找出正确/错误样本的特征边界
3. stats_summary.md中"正确vs错误样本对比"表格 - 定位关键特征差异

## 故障排除

### 缺少依赖包

```bash
pip install pandas numpy matplotlib
```

### 日志格式不匹配

确保日志包含 `[HandGestureDebug]` 标记和完整的特征字段。

### 中文显示问题

脚本已配置中文字体支持，如果图表中中文仍显示为方框，可以：
- macOS: 已配置 'Arial Unicode MS'
- Windows: 脚本会自动使用 'SimHei'
- Linux: 安装中文字体包

## 许可

MIT License
