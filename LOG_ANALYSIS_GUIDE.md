# 手势日志分析脚本使用指南

## 快速开始

### 1. 安装依赖

```bash
# 方式A: 使用虚拟环境（推荐）
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# 方式B: 全局安装（需要权限）
pip3 install pandas numpy matplotlib

# 方式C: Homebrew Python（macOS）
brew install python@3.11
/opt/homebrew/bin/python3.11 -m pip install pandas numpy matplotlib
```

### 2. 获取调试日志

在iOS应用中：
1. 切换到"手势识别"Tab
2. 摆出目标手势（如V手势）
3. 查看Xcode控制台输出
4. 复制所有 `[HandGestureDebug]` 开头的行
5. 保存到文件（如 `v_gesture_debug.log`）

### 3. 运行分析

```bash
# 基础分析（无Ground Truth）
python analyze_gesture_log.py --log-file debug.log

# 完整分析（指定Ground Truth为V手势）
python analyze_gesture_log.py \
  --log-file v_gesture_debug.log \
  --gt-gesture V \
  --output-dir ./v_analysis

# 查看结果
cd v_analysis
cat stats_summary.md
open *.png  # macOS
```

## 典型工作流

### 场景1: V手势远距离识别优化

**问题：** 远距离时V手势被误判为Fist

**分析步骤：**

1. **录制V手势视频，从近到远**
   ```bash
   # 在Xcode中运行应用，摆V手势
   # 慢慢从近到远移动手部
   # 复制控制台日志到 v_far_test.log
   ```

2. **运行分析**
   ```bash
   python analyze_gesture_log.py \
     --log-file v_far_test.log \
     --gt-gesture V \
     --output-dir ./v_far_analysis
   ```

3. **查看关键结果**
   ```bash
   cd v_far_analysis
   
   # 查看准确率表格
   grep "按距离分组" stats_summary.md -A 5
   
   # 查看正确vs错误样本的特征差异
   grep "正确 vs 错误" stats_summary.md -A 20
   
   # 查看图表
   open scatter_idxmidratio_vs_score_v_correct_wrong.png
   ```

4. **确定优化方向**
   - 如果far组准确率<50%，scale<0.08，说明需要降低minHandSize阈值
   - 如果错误样本的gapIdxMid平均值<0.02，说明需要降低indexMiddleGapMin
   - 如果错误样本的score_v平均值<4，说明需要降低GestureThreshold.vSign

### 场景2: 对比优化前后效果

```bash
# 优化前的日志
python analyze_gesture_log.py \
  --log-file v_before.log \
  --gt-gesture V \
  --output-dir ./v_before

# 优化后的日志
python analyze_gesture_log.py \
  --log-file v_after.log \
  --gt-gesture V \
  --output-dir ./v_after

# 对比两个stats_summary.md文件
diff v_before/stats_summary.md v_after/stats_summary.md
```

### 场景3: 多手势数据采集分析

```bash
# 分别分析每个手势
for gesture in V OK Palm Fist Idx; do
  python analyze_gesture_log.py \
    --log-file ${gesture}_gesture.log \
    --gt-gesture $gesture \
    --output-dir ./${gesture}_analysis
done

# 汇总所有手势的特征范围
cat */stats_summary.md | grep "mean=" > all_gestures_summary.txt
```

## 输出文件解读

### gesture_parsed.csv

完整的解析数据，包含：
- 原始特征：lenIdx, lenMid, lenRing, lenLit, gapIdxMid, gapThumbIdx
- 比例特征：ratio_idx_mid, ratio_ring_mid, ratio_lit_mid
- 得分：score_v, score_ok, score_palm, score_fist, score_idx
- 派生特征：scale, pred_by_score, scale_group
- GT相关：gt_gesture, is_correct_by_score（如果指定了GT）

可以用Excel、Pandas或其他工具进一步分析。

### stats_summary.md

Markdown格式的统计报告，包含：
1. 全局统计（样本数、标签分布）
2. 准确率表格（总体、按距离分组）
3. 各手势特征统计（mean/std/分位数）
4. 正确vs错误样本对比

### 图表文件

1. **hist_scale_by_group.png**
   - 显示far/mid/near三组的scale分布
   - 用于判断数据是否覆盖了足够的距离范围

2. **scatter_scale_vs_score_v.png**
   - x轴：scale（距离）
   - y轴：score_v（V手势得分）
   - 颜色：最终识别的手势
   - 用于观察"距离变远时，V得分是否下降"

3. **scatter_idxmidratio_vs_score_v_correct_wrong.png**（仅GT=V）
   - x轴：ratio_idx_mid（食指/中指长度比）
   - y轴：score_v
   - 颜色：绿色=正确，红色=错误
   - 用于找出正确/错误样本的特征边界

## 常见问题

### Q: 脚本提示"未能解析到任何有效数据"

A: 检查日志格式是否正确，确保包含完整的特征字段。日志行必须包含：
- `[HandGestureDebug]`
- `lenIdx:` `lenMid:` `lenRing:` `lenLit:`
- `gapIdxMid:` `gapThumbIdx:`
- `ratio idx/mid:` `ring/mid:` `lit/mid:`
- `score V/OK/Palm/Fist/Idx =`

### Q: far组样本数太少

A: 录制视频时要确保手部从近到远移动，覆盖足够的距离范围。

### Q: 如何确定新的阈值

A: 
1. 查看stats_summary.md中"正确vs错误样本对比"表
2. 找出差异最大的特征
3. 使用正确样本的10%分位数作为新阈值的参考
4. 确保新阈值不会与其他手势的范围重叠

### Q: 图表中文显示为方框

A: 
- macOS: 脚本已配置 'Arial Unicode MS'
- 可以手动编辑脚本，在 plot_distributions() 开头添加：
  ```python
  plt.rcParams['font.sans-serif'] = ['你的中文字体名称']
  ```

## 实际案例

### 案例：优化远距离V手势识别

**初始状态：**
```
far组准确率: 15%
mid组准确率: 68%  
near组准确率: 92%
```

**分析发现：**
- far组错误样本的平均 gapIdxMid = 0.018（远小于0.025）
- far组错误样本的平均 score_fist = 7，score_v = 2
- far组正确样本的 gapIdxMid 平均值 = 0.032

**优化方案：**
1. 降低 `VThreshold.indexMiddleGapMin` 从 0.025 → 0.018
2. 增加V手势在gapIdxMid的权重：+2 → +4
3. 添加Fist强制减分：当gapIdxMid > 0.025时，scoreFist -= 4

**优化后：**
```
far组准确率: 78%（提升63个百分点）
mid组准确率: 85%
near组准确率: 95%
```

## 进阶技巧

### 1. 批量分析多个日志

```bash
#!/bin/bash
for log in *.log; do
  gesture=$(basename $log .log)
  python analyze_gesture_log.py \
    --log-file $log \
    --output-dir ./analysis_$gesture
done
```

### 2. 提取关键统计量

```bash
# 提取所有手势的gapIdxMid统计
grep "gapIdxMid" */stats_summary.md > gapIdxMid_all.txt
```

### 3. 使用Python进一步分析

```python
import pandas as pd

# 读取解析后的数据
df = pd.read_csv('gesture_parsed.csv')

# 自定义分析
far_v = df[(df['scale_group'] == 'far') & (df['gt_gesture'] == 'V')]
print(far_v[['gapIdxMid', 'score_v', 'is_correct_by_score']].describe())
```

## 贡献

欢迎提出改进建议或报告问题。

## 许可

MIT License
