#!/usr/bin/env python3
"""
智能手势日志分析器 - 自动化版本
自动检测手势类型、识别问题、生成优化建议

使用方法:
    python smart_analyzer.py /path/to/log/file

特性:
- 🤖 自动检测主要手势（无需手动指定GT）
- 🔍 自动识别问题区域（低准确率距离段）
- 💡 自动生成优化建议（包括Swift代码）
- 📊 生成友好的HTML交互式报告
- 🚀 一键运行，零配置
"""

import argparse
import os
import sys
import re
from typing import Dict, List, Tuple, Optional
from collections import Counter
import json

# 尝试导入pandas，如果失败给出友好提示
try:
    import pandas as pd
    import numpy as np
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
except ImportError as e:
    print("❌ 缺少必要的依赖包")
    print("\n请运行以下命令安装：")
    print("  pip install pandas numpy matplotlib")
    print("\n或使用虚拟环境：")
    print("  python3 -m venv venv")
    print("  source venv/bin/activate")
    print("  pip install -r requirements.txt")
    sys.exit(1)


class SmartGestureAnalyzer:
    """智能手势分析器"""
    
    # 中文标签映射
    LABEL_MAP = {
        '拳头': 'Fist',
        '手掌张开': 'Palm',
        'OK手势': 'OK',
        '食指': 'Idx',
        'V手势': 'V',
        'V 手势': 'V',
        '未知': 'Unknown'
    }
    
    # 阈值配置模板
    THRESHOLD_RANGES = {
        'V': {
            'gapIdxMid': (0.015, 0.030),
            'ratio_idx_mid': (0.85, 1.05),
            'ratio_ring_mid': (0.50, 0.85),
            'minScore': 4
        },
        'OK': {
            'gapThumbIdx': (0.005, 0.025),
            'ratio_ring_mid': (1.10, 1.50),
            'minScore': 5
        },
        'Palm': {
            'gapIdxMid': (0.040, 0.100),
            'ratio_idx_mid': (0.65, 0.95),
            'ratio_ring_mid': (0.85, 1.05),
            'minScore': 6
        },
        'Fist': {
            'gapIdxMid': (0.005, 0.025),
            'ratio_ring_mid': (1.00, 1.40),
            'minScore': 5
        }
    }
    
    def __init__(self, log_file: str, output_dir: str = None):
        self.log_file = log_file
        self.output_dir = output_dir or os.path.join(
            os.path.dirname(log_file), 
            'smart_analysis_' + os.path.basename(log_file).replace('.log', '')
        )
        os.makedirs(self.output_dir, exist_ok=True)
        
        self.df = None
        self.dominant_gesture = None
        self.issues = []
        self.recommendations = []
        
    def run(self):
        """运行完整的智能分析流程"""
        print("=" * 80)
        print("🤖 智能手势日志分析器")
        print("=" * 80)
        print(f"📁 日志文件: {self.log_file}")
        print(f"📂 输出目录: {self.output_dir}")
        print()
        
        # 步骤1: 解析日志
        print("【步骤 1/6】解析日志文件...")
        self.df = self._parse_log()
        print(f"  ✓ 成功解析 {len(self.df)} 条记录")
        
        # 步骤2: 自动检测主要手势
        print("\n【步骤 2/6】自动检测主要手势...")
        self.dominant_gesture = self._detect_dominant_gesture()
        print(f"  ✓ 检测到主要手势: {self.dominant_gesture}")
        
        # 步骤3: 添加派生特征
        print("\n【步骤 3/6】计算派生特征...")
        self._add_derived_features()
        print(f"  ✓ 计算完成")
        
        # 步骤4: 诊断问题
        print("\n【步骤 4/6】诊断识别问题...")
        self._diagnose_issues()
        if self.issues:
            print(f"  ⚠️  发现 {len(self.issues)} 个问题")
            for issue in self.issues[:3]:
                print(f"     - {issue['type']}: {issue['description']}")
        else:
            print(f"  ✓ 未发现明显问题")
        
        # 步骤5: 生成优化建议
        print("\n【步骤 5/6】生成优化建议...")
        self._generate_recommendations()
        print(f"  ✓ 生成 {len(self.recommendations)} 条建议")
        
        # 步骤6: 生成报告
        print("\n【步骤 6/6】生成分析报告...")
        self._save_results()
        self._generate_html_report()
        print(f"  ✓ 报告已保存")
        
        # 显示总结
        self._print_summary()
        
    def _parse_log(self) -> pd.DataFrame:
        """解析日志文件"""
        pattern = (
            r'\[HandGestureDebug\]\s+'
            r'(?P<raw_label>.*?)\s+✓.*?'
            r'lenIdx:(?P<lenIdx>[\d.]+).*?'
            r'lenMid:(?P<lenMid>[\d.]+).*?'
            r'lenRing:(?P<lenRing>[\d.]+).*?'
            r'lenLit:(?P<lenLit>[\d.]+).*?'
            r'gapIdxMid:(?P<gapIdxMid>[\d.]+).*?'
            r'gapThumbIdx:(?P<gapThumbIdx>[\d.]+).*?'
            r'ratio idx/mid:(?P<ratio_idx_mid>[\d.]+).*?'
            r'ring/mid:(?P<ratio_ring_mid>[\d.]+).*?'
            r'lit/mid:(?P<ratio_lit_mid>[\d.]+).*?'
            r'score V/OK/Palm/Fist/Idx = '
            r'(?P<score_v>-?\d+)/'
            r'(?P<score_ok>-?\d+)/'
            r'(?P<score_palm>-?\d+)/'
            r'(?P<score_fist>-?\d+)/'
            r'(?P<score_idx>-?\d+)'
        )
        
        records = []
        with open(self.log_file, 'r', encoding='utf-8') as f:
            for line in f:
                if '[HandGestureDebug]' not in line:
                    continue
                match = re.search(pattern, line)
                if match:
                    record = match.groupdict()
                    for key in record:
                        if key != 'raw_label':
                            record[key] = float(record[key])
                    records.append(record)
        
        if not records:
            raise ValueError("未能从日志文件中解析到任何有效数据")
        
        return pd.DataFrame(records)
    
    def _detect_dominant_gesture(self) -> str:
        """自动检测主要手势"""
        # 标准化标签
        self.df['label_norm'] = self.df['raw_label'].map(self.LABEL_MAP).fillna('Unknown')
        
        # 排除Unknown，统计最常见的手势
        valid_labels = self.df[self.df['label_norm'] != 'Unknown']['label_norm']
        
        if len(valid_labels) == 0:
            return 'Unknown'
        
        gesture_counts = valid_labels.value_counts()
        dominant = gesture_counts.index[0]
        
        # 如果最常见的手势占比超过40%，认为是主要手势
        if gesture_counts.iloc[0] / len(valid_labels) > 0.4:
            return dominant
        
        # 否则返回None，表示混合手势
        return 'Mixed'
    
    def _add_derived_features(self):
        """添加派生特征"""
        # scale: 手部远近
        self.df['scale'] = (
            self.df['lenIdx'] + self.df['lenMid'] + 
            self.df['lenRing'] + self.df['lenLit']
        ) / 4.0
        
        # pred_by_score: 根据得分推断的手势
        score_cols = ['score_v', 'score_ok', 'score_palm', 'score_fist', 'score_idx']
        score_map = {
            'score_v': 'V', 'score_ok': 'OK', 'score_palm': 'Palm',
            'score_fist': 'Fist', 'score_idx': 'Idx'
        }
        self.df['pred_by_score'] = self.df[score_cols].idxmax(axis=1).map(score_map)
        
        # scale_group: 距离分组
        q33 = self.df['scale'].quantile(0.33)
        q66 = self.df['scale'].quantile(0.66)
        self.df['scale_group'] = pd.cut(
            self.df['scale'],
            bins=[-np.inf, q33, q66, np.inf],
            labels=['far', 'mid', 'near']
        )
        
        # 如果检测到主要手势，计算准确率
        if self.dominant_gesture and self.dominant_gesture != 'Mixed':
            self.df['gt_gesture'] = self.dominant_gesture
            self.df['is_correct'] = (self.df['pred_by_score'] == self.dominant_gesture)
    
    def _diagnose_issues(self):
        """诊断识别问题"""
        self.issues = []
        
        if not self.dominant_gesture or self.dominant_gesture == 'Mixed':
            self.issues.append({
                'type': '混合手势',
                'description': '日志包含多种手势，建议分别采集单一手势数据',
                'severity': 'info'
            })
            return
        
        # 检查整体准确率
        if 'is_correct' in self.df.columns:
            overall_acc = self.df['is_correct'].mean()
            if overall_acc < 0.7:
                self.issues.append({
                    'type': '整体准确率低',
                    'description': f'整体准确率仅 {overall_acc*100:.1f}%，需要优化',
                    'severity': 'high',
                    'metric': 'overall_accuracy',
                    'value': overall_acc
                })
            
            # 检查各距离段准确率
            for group in ['far', 'mid', 'near']:
                group_df = self.df[self.df['scale_group'] == group]
                if len(group_df) > 5:
                    acc = group_df['is_correct'].mean()
                    if acc < 0.5:
                        self.issues.append({
                            'type': f'{group}组准确率过低',
                            'description': f'{group}距离段准确率仅 {acc*100:.1f}%',
                            'severity': 'high',
                            'metric': f'{group}_accuracy',
                            'value': acc,
                            'distance_group': group
                        })
        
        # 检查特征异常
        gesture_data = self.df[self.df['pred_by_score'] == self.dominant_gesture]
        wrong_data = self.df[self.df['is_correct'] == False] if 'is_correct' in self.df.columns else pd.DataFrame()
        
        if len(wrong_data) > 0:
            # 找出错误样本的主要特征差异
            key_features = ['gapIdxMid', 'gapThumbIdx', 'ratio_idx_mid', 'ratio_ring_mid']
            for feat in key_features:
                if feat in self.df.columns:
                    correct_mean = gesture_data[feat].mean()
                    wrong_mean = wrong_data[feat].mean()
                    diff = abs(correct_mean - wrong_mean)
                    
                    if diff > correct_mean * 0.3:  # 差异超过30%
                        self.issues.append({
                            'type': f'{feat}特征差异大',
                            'description': f'错误样本的{feat}与正确样本差异{diff:.3f}',
                            'severity': 'medium',
                            'metric': feat,
                            'correct_mean': correct_mean,
                            'wrong_mean': wrong_mean
                        })
    
    def _generate_recommendations(self):
        """生成优化建议"""
        self.recommendations = []
        
        if not self.dominant_gesture or self.dominant_gesture == 'Mixed':
            return
        
        # 基于问题生成建议
        for issue in self.issues:
            if issue['type'] == '整体准确率低':
                self.recommendations.append({
                    'priority': 'high',
                    'category': '算法优化',
                    'description': '整体识别率需要提升，建议重新标定阈值',
                    'action': '使用统计标定界面采集更多数据'
                })
            
            elif 'far组准确率过低' in issue['type']:
                # 分析far组的特征
                far_data = self.df[self.df['scale_group'] == 'far']
                correct_far = far_data[far_data['is_correct'] == True] if 'is_correct' in far_data.columns else pd.DataFrame()
                
                if len(correct_far) > 0:
                    # 生成具体的阈值建议
                    rec = self._generate_threshold_recommendation(
                        self.dominant_gesture, 
                        correct_far,
                        distance_group='far'
                    )
                    self.recommendations.append(rec)
            
            elif 'mid组准确率过低' in issue['type']:
                mid_data = self.df[self.df['scale_group'] == 'mid']
                correct_mid = mid_data[mid_data['is_correct'] == True] if 'is_correct' in mid_data.columns else pd.DataFrame()
                
                if len(correct_mid) > 0:
                    rec = self._generate_threshold_recommendation(
                        self.dominant_gesture,
                        correct_mid,
                        distance_group='mid'
                    )
                    self.recommendations.append(rec)
        
        # 如果没有明显问题，给出优化建议
        if len(self.recommendations) == 0 and 'is_correct' in self.df.columns:
            overall_acc = self.df['is_correct'].mean()
            if overall_acc > 0.85:
                self.recommendations.append({
                    'priority': 'low',
                    'category': '性能优化',
                    'description': f'当前识别率已达 {overall_acc*100:.1f}%，可考虑优化边界情况',
                    'action': '采集更多边界样本（如手部倾斜、遮挡等）'
                })
    
    def _generate_threshold_recommendation(self, gesture: str, data: pd.DataFrame, distance_group: str) -> Dict:
        """生成具体的阈值推荐"""
        rec = {
            'priority': 'high',
            'category': '阈值调整',
            'description': f'优化{gesture}手势在{distance_group}距离段的识别',
            'gesture': gesture,
            'distance_group': distance_group,
            'swift_code': []
        }
        
        if gesture == 'V':
            # V手势推荐
            gapIdxMid_10pct = data['gapIdxMid'].quantile(0.1)
            ratio_idx_mid_10pct = data['ratio_idx_mid'].quantile(0.1)
            ratio_ring_mid_90pct = data['ratio_ring_mid'].quantile(0.9)
            
            rec['swift_code'].append(
                f"// 基于{distance_group}组统计分析的推荐阈值\n"
                f"struct VThreshold {{\n"
                f"    static let indexMiddleGapMin: CGFloat = {gapIdxMid_10pct:.3f}  // 原阈值可能过高\n"
                f"    static let indexToMiddleRatioMin: CGFloat = {ratio_idx_mid_10pct:.3f}\n"
                f"    static let ringToMiddleRatioMax: CGFloat = {ratio_ring_mid_90pct:.3f}\n"
                f"}}"
            )
            
            rec['action'] = (
                f"修改 HandGestureClassifier.swift 中的 VThreshold，"
                f"将 indexMiddleGapMin 降低至 {gapIdxMid_10pct:.3f}"
            )
        
        elif gesture == 'OK':
            gapThumbIdx_90pct = data['gapThumbIdx'].quantile(0.9)
            rec['swift_code'].append(
                f"// OK手势阈值建议\n"
                f"struct OKThreshold {{\n"
                f"    static let thumbIndexGapMax: CGFloat = {gapThumbIdx_90pct:.3f}\n"
                f"}}"
            )
        
        return rec
    
    def _save_results(self):
        """保存结果"""
        # 保存CSV
        csv_path = os.path.join(self.output_dir, 'parsed_data.csv')
        self.df.to_csv(csv_path, index=False, encoding='utf-8')
        
        # 保存JSON报告
        report = {
            'log_file': self.log_file,
            'total_samples': len(self.df),
            'dominant_gesture': self.dominant_gesture,
            'issues': self.issues,
            'recommendations': self.recommendations
        }
        
        if 'is_correct' in self.df.columns:
            report['overall_accuracy'] = float(self.df['is_correct'].mean())
            report['accuracy_by_distance'] = {
                group: float(self.df[self.df['scale_group'] == group]['is_correct'].mean())
                for group in ['far', 'mid', 'near']
                if len(self.df[self.df['scale_group'] == group]) > 0
            }
        
        json_path = os.path.join(self.output_dir, 'analysis_report.json')
        with open(json_path, 'w', encoding='utf-8') as f:
            json.dump(report, f, indent=2, ensure_ascii=False)
        
        # 生成图表
        self._generate_plots()
    
    def _generate_plots(self):
        """生成可视化图表"""
        plt.rcParams['font.sans-serif'] = ['Arial Unicode MS', 'SimHei', 'DejaVu Sans']
        plt.rcParams['axes.unicode_minus'] = False
        
        # 图1: scale分布
        plt.figure(figsize=(10, 6))
        for group, color in [('far', 'red'), ('mid', 'orange'), ('near', 'green')]:
            subset = self.df[self.df['scale_group'] == group]
            if len(subset) > 0:
                plt.hist(subset['scale'], alpha=0.5, label=group, bins=20, color=color)
        plt.xlabel('Scale')
        plt.ylabel('Frequency')
        plt.legend()
        plt.title('Hand Scale Distribution')
        plt.savefig(os.path.join(self.output_dir, 'scale_distribution.png'), dpi=150)
        plt.close()
        
        # 图2: 准确率对比（如果有GT）
        if 'is_correct' in self.df.columns:
            fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 6))
            
            # 左图：准确率条形图
            acc_by_group = self.df.groupby('scale_group')['is_correct'].mean()
            colors_map = {'far': 'red', 'mid': 'orange', 'near': 'green'}
            colors = [colors_map[g] for g in acc_by_group.index]
            ax1.bar(range(len(acc_by_group)), acc_by_group.values, color=colors)
            ax1.set_xticks(range(len(acc_by_group)))
            ax1.set_xticklabels(acc_by_group.index)
            ax1.set_ylabel('Accuracy')
            ax1.set_title('Accuracy by Distance Group')
            ax1.set_ylim([0, 1])
            for i, v in enumerate(acc_by_group.values):
                ax1.text(i, v + 0.02, f'{v*100:.1f}%', ha='center')
            
            # 右图：scale vs score散点图
            for is_correct, color, label in [(True, 'green', 'Correct'), (False, 'red', 'Wrong')]:
                subset = self.df[self.df['is_correct'] == is_correct]
                score_col = f'score_{self.dominant_gesture.lower()}' if self.dominant_gesture.lower() in ['v', 'ok', 'palm', 'fist', 'idx'] else 'score_v'
                if score_col in subset.columns:
                    ax2.scatter(subset['scale'], subset[score_col], 
                               alpha=0.6, s=30, color=color, label=label)
            ax2.set_xlabel('Scale')
            ax2.set_ylabel(f'Score {self.dominant_gesture}')
            ax2.set_title(f'{self.dominant_gesture} Gesture: Scale vs Score')
            ax2.legend()
            ax2.grid(alpha=0.3)
            
            plt.tight_layout()
            plt.savefig(os.path.join(self.output_dir, 'accuracy_analysis.png'), dpi=150)
            plt.close()
    
    def _generate_html_report(self):
        """生成HTML交互式报告"""
        html = f"""
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>智能手势分析报告</title>
    <style>
        * {{ margin: 0; padding: 0; box-sizing: border-box; }}
        body {{ 
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
            background: #f5f7fa;
            padding: 20px;
        }}
        .container {{ max-width: 1200px; margin: 0 auto; }}
        .header {{
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 40px;
            border-radius: 10px;
            margin-bottom: 30px;
        }}
        .header h1 {{ font-size: 32px; margin-bottom: 10px; }}
        .header p {{ opacity: 0.9; }}
        .card {{
            background: white;
            border-radius: 10px;
            padding: 30px;
            margin-bottom: 20px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }}
        .card h2 {{
            font-size: 24px;
            margin-bottom: 20px;
            color: #2d3748;
            border-bottom: 2px solid #667eea;
            padding-bottom: 10px;
        }}
        .stats {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }}
        .stat-box {{
            background: #f7fafc;
            padding: 20px;
            border-radius: 8px;
            border-left: 4px solid #667eea;
        }}
        .stat-box .label {{ color: #718096; font-size: 14px; margin-bottom: 5px; }}
        .stat-box .value {{ font-size: 28px; font-weight: bold; color: #2d3748; }}
        .issue {{
            background: #fff5f5;
            border-left: 4px solid #fc8181;
            padding: 15px;
            margin-bottom: 15px;
            border-radius: 4px;
        }}
        .issue.high {{ border-left-color: #fc8181; background: #fff5f5; }}
        .issue.medium {{ border-left-color: #f6ad55; background: #fffaf0; }}
        .issue.info {{ border-left-color: #4299e1; background: #ebf8ff; }}
        .issue-title {{ font-weight: bold; margin-bottom: 5px; color: #2d3748; }}
        .issue-desc {{ color: #4a5568; font-size: 14px; }}
        .recommendation {{
            background: #f0fff4;
            border-left: 4px solid #48bb78;
            padding: 15px;
            margin-bottom: 15px;
            border-radius: 4px;
        }}
        .rec-title {{ font-weight: bold; margin-bottom: 10px; color: #2d3748; }}
        .rec-action {{ color: #4a5568; margin-bottom: 10px; }}
        .code-block {{
            background: #2d3748;
            color: #e2e8f0;
            padding: 15px;
            border-radius: 6px;
            font-family: 'Monaco', 'Courier New', monospace;
            font-size: 13px;
            overflow-x: auto;
            margin-top: 10px;
        }}
        .chart {{ margin: 20px 0; text-align: center; }}
        .chart img {{ max-width: 100%; height: auto; border-radius: 8px; }}
        .badge {{
            display: inline-block;
            padding: 4px 12px;
            border-radius: 12px;
            font-size: 12px;
            font-weight: bold;
            margin-right: 10px;
        }}
        .badge.high {{ background: #fc8181; color: white; }}
        .badge.medium {{ background: #f6ad55; color: white; }}
        .badge.low {{ background: #4299e1; color: white; }}
        .footer {{
            text-align: center;
            color: #718096;
            margin-top: 40px;
            padding: 20px;
        }}
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🤖 智能手势分析报告</h1>
            <p>📁 {os.path.basename(self.log_file)}</p>
            <p>📅 {pd.Timestamp.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
        </div>
        
        <div class="card">
            <h2>📊 整体统计</h2>
            <div class="stats">
                <div class="stat-box">
                    <div class="label">总样本数</div>
                    <div class="value">{len(self.df)}</div>
                </div>
                <div class="stat-box">
                    <div class="label">主要手势</div>
                    <div class="value">{self.dominant_gesture}</div>
                </div>
"""
        
        if 'is_correct' in self.df.columns:
            overall_acc = self.df['is_correct'].mean() * 100
            html += f"""
                <div class="stat-box">
                    <div class="label">整体准确率</div>
                    <div class="value">{overall_acc:.1f}%</div>
                </div>
"""
        
        html += """
            </div>
        </div>
"""
        
        # 准确率详情
        if 'is_correct' in self.df.columns:
            html += """
        <div class="card">
            <h2>🎯 准确率详情</h2>
            <div class="stats">
"""
            for group in ['far', 'mid', 'near']:
                group_df = self.df[self.df['scale_group'] == group]
                if len(group_df) > 0:
                    acc = group_df['is_correct'].mean() * 100
                    html += f"""
                <div class="stat-box">
                    <div class="label">{group.upper()}组 ({len(group_df)}样本)</div>
                    <div class="value">{acc:.1f}%</div>
                </div>
"""
            html += """
            </div>
            <div class="chart">
                <img src="accuracy_analysis.png" alt="准确率分析">
            </div>
        </div>
"""
        
        # 问题诊断
        if self.issues:
            html += """
        <div class="card">
            <h2>⚠️ 问题诊断</h2>
"""
            for issue in self.issues:
                severity = issue.get('severity', 'info')
                html += f"""
            <div class="issue {severity}">
                <div class="issue-title">
                    <span class="badge {severity}">{severity.upper()}</span>
                    {issue['type']}
                </div>
                <div class="issue-desc">{issue['description']}</div>
            </div>
"""
            html += """
        </div>
"""
        
        # 优化建议
        if self.recommendations:
            html += """
        <div class="card">
            <h2>💡 优化建议</h2>
"""
            for rec in self.recommendations:
                html += f"""
            <div class="recommendation">
                <div class="rec-title">
                    <span class="badge {rec['priority']}">{rec['priority'].upper()}</span>
                    {rec['category']}
                </div>
                <div class="rec-action">📝 {rec['description']}</div>
"""
                if 'action' in rec:
                    html += f"""
                <div class="rec-action">🔧 <strong>操作：</strong>{rec['action']}</div>
"""
                if 'swift_code' in rec and rec['swift_code']:
                    for code in rec['swift_code']:
                        html += f"""
                <div class="code-block">{code}</div>
"""
                html += """
            </div>
"""
            html += """
        </div>
"""
        
        # 可视化图表
        html += """
        <div class="card">
            <h2>📈 数据可视化</h2>
            <div class="chart">
                <img src="scale_distribution.png" alt="距离分布">
            </div>
        </div>
        
        <div class="footer">
            <p>🤖 由智能手势分析器自动生成</p>
            <p>Vision Demo Project © 2025</p>
        </div>
    </div>
</body>
</html>
"""
        
        html_path = os.path.join(self.output_dir, 'report.html')
        with open(html_path, 'w', encoding='utf-8') as f:
            f.write(html)
    
    def _print_summary(self):
        """打印分析总结"""
        print("\n" + "=" * 80)
        print("✅ 分析完成！")
        print("=" * 80)
        print(f"\n📁 结果文件：")
        print(f"  - HTML报告: {os.path.join(self.output_dir, 'report.html')}")
        print(f"  - JSON数据: {os.path.join(self.output_dir, 'analysis_report.json')}")
        print(f"  - CSV数据: {os.path.join(self.output_dir, 'parsed_data.csv')}")
        
        if self.issues:
            print(f"\n⚠️  发现 {len(self.issues)} 个问题")
            for issue in self.issues[:5]:
                print(f"  • {issue['type']}")
        
        if self.recommendations:
            print(f"\n💡 生成 {len(self.recommendations)} 条优化建议")
            for rec in self.recommendations[:3]:
                print(f"  • {rec['description']}")
        
        print(f"\n🌐 查看完整报告：")
        print(f"  open {os.path.join(self.output_dir, 'report.html')}")
        print("=" * 80)


def main():
    parser = argparse.ArgumentParser(
        description='智能手势日志分析器 - 自动检测、诊断、优化',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例用法:
  # 分析单个日志文件
  python smart_analyzer.py ~/Desktop/v_gesture.log
  
  # 指定输出目录
  python smart_analyzer.py ~/Desktop/v_gesture.log -o ~/Desktop/analysis
  
特性:
  ✓ 自动检测主要手势（无需手动指定）
  ✓ 自动识别问题区域
  ✓ 自动生成优化建议和Swift代码
  ✓ 生成漂亮的HTML交互式报告
  ✓ 一键运行，零配置
        """
    )
    
    parser.add_argument(
        'log_file',
        help='手势日志文件路径'
    )
    
    parser.add_argument(
        '-o', '--output-dir',
        help='输出目录（默认：日志文件同目录下的smart_analysis_*文件夹）'
    )
    
    args = parser.parse_args()
    
    # 检查文件是否存在
    if not os.path.exists(args.log_file):
        print(f"❌ 文件不存在: {args.log_file}")
        sys.exit(1)
    
    try:
        analyzer = SmartGestureAnalyzer(args.log_file, args.output_dir)
        analyzer.run()
    except Exception as e:
        print(f"\n❌ 分析过程中出错: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
