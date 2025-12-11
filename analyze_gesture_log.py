#!/usr/bin/env python3
"""
手势识别日志分析脚本
用于解析调试日志、生成统计报告和可视化图表，优化远距离V手势识别
"""

import argparse
import os
import re
import sys
from typing import Optional, Tuple

import pandas as pd
import numpy as np
import matplotlib
matplotlib.use('Agg')  # 非交互式后端
import matplotlib.pyplot as plt


def parse_args():
    """解析命令行参数"""
    parser = argparse.ArgumentParser(
        description='分析手势识别调试日志，生成统计报告和可视化图表'
    )
    parser.add_argument(
        '--log-file',
        required=True,
        help='输入日志文件路径'
    )
    parser.add_argument(
        '--output-dir',
        default='.',
        help='输出结果目录（默认：当前目录）'
    )
    parser.add_argument(
        '--gt-gesture',
        choices=['V', 'OK', 'Palm', 'Fist', 'Idx'],
        help='本次日志对应的Ground Truth手势'
    )
    parser.add_argument(
        '--save-plots',
        action='store_true',
        default=True,
        help='是否生成并保存图表（默认：True）'
    )
    parser.add_argument(
        '--no-plots',
        action='store_false',
        dest='save_plots',
        help='不生成图表'
    )
    
    return parser.parse_args()


def parse_log_file(log_path: str) -> pd.DataFrame:
    """
    解析日志文件，提取手势识别特征
    
    Args:
        log_path: 日志文件路径
        
    Returns:
        包含所有解析字段的DataFrame
    """
    print(f"正在解析日志文件: {log_path}")
    
    # 检查文件是否存在
    if not os.path.exists(log_path):
        raise FileNotFoundError(f"日志文件不存在: {log_path}")
    
    # 正则表达式模式 - 匹配日志格式
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
    
    # 读取日志文件
    with open(log_path, 'r', encoding='utf-8') as f:
        for line_num, line in enumerate(f, 1):
            if '[HandGestureDebug]' not in line:
                continue
                
            match = re.search(pattern, line)
            if match:
                record = match.groupdict()
                
                # 转换数值类型
                for key in record:
                    if key != 'raw_label':
                        record[key] = float(record[key])
                
                records.append(record)
            else:
                print(f"警告: 第{line_num}行无法解析: {line.strip()[:100]}")
    
    if not records:
        raise ValueError(f"未能从日志文件中解析到任何有效数据")
    
    df = pd.DataFrame(records)
    print(f"成功解析 {len(df)} 条记录")
    
    return df


def add_derived_features(df: pd.DataFrame, gt_gesture: Optional[str] = None) -> pd.DataFrame:
    """
    添加派生特征字段
    
    Args:
        df: 原始DataFrame
        gt_gesture: Ground Truth手势（可选）
        
    Returns:
        添加了派生特征的DataFrame
    """
    print("正在计算派生特征...")
    
    # 1. scale: 手部远近尺度（平均手指长度）
    df['scale'] = (df['lenIdx'] + df['lenMid'] + df['lenRing'] + df['lenLit']) / 4.0
    
    # 2. pred_by_score: 根据得分推断的主导手势
    score_cols = ['score_v', 'score_ok', 'score_palm', 'score_fist', 'score_idx']
    score_map = {
        'score_v': 'V',
        'score_ok': 'OK',
        'score_palm': 'Palm',
        'score_fist': 'Fist',
        'score_idx': 'Idx'
    }
    df['pred_by_score'] = df[score_cols].idxmax(axis=1).map(score_map)
    
    # 3. raw_label_norm: 中文标签标准化
    label_map = {
        '拳头': 'Fist_label',
        '手掌张开': 'Palm_label',
        'OK手势': 'OK_label',
        '食指': 'Idx_label',
        '未知': 'Unknown_label',
        'V手势': 'V_label',
        'V 手势': 'V_label'
    }
    df['raw_label_norm'] = df['raw_label'].map(label_map).fillna('Unknown_label')
    
    # 4. scale_group: 远近分类（根据分位数）
    q33 = df['scale'].quantile(0.33)
    q66 = df['scale'].quantile(0.66)
    df['scale_group'] = pd.cut(
        df['scale'],
        bins=[-np.inf, q33, q66, np.inf],
        labels=['far', 'mid', 'near']
    )
    
    # 5. Ground Truth相关字段
    if gt_gesture:
        df['gt_gesture'] = gt_gesture
        df['is_correct_by_score'] = (df['pred_by_score'] == gt_gesture)
        
        # raw_label匹配逻辑：检查raw_label_norm是否包含GT手势
        gesture_label_map = {
            'V': 'V_label',
            'OK': 'OK_label',
            'Palm': 'Palm_label',
            'Fist': 'Fist_label',
            'Idx': 'Idx_label'
        }
        expected_label = gesture_label_map.get(gt_gesture, 'Unknown_label')
        df['is_correct_by_raw_label'] = (df['raw_label_norm'] == expected_label)
    
    print(f"派生特征计算完成")
    print(f"  - scale范围: [{df['scale'].min():.3f}, {df['scale'].max():.3f}]")
    print(f"  - far组 (scale < {q33:.3f}): {(df['scale_group'] == 'far').sum()} 样本")
    print(f"  - mid组 ({q33:.3f} <= scale < {q66:.3f}): {(df['scale_group'] == 'mid').sum()} 样本")
    print(f"  - near组 (scale >= {q66:.3f}): {(df['scale_group'] == 'near').sum()} 样本")
    
    return df


def print_and_save_stats(df: pd.DataFrame, output_dir: str, gt_gesture: Optional[str] = None):
    """
    打印并保存统计分析结果
    
    Args:
        df: 完整的DataFrame
        output_dir: 输出目录
        gt_gesture: Ground Truth手势（可选）
    """
    print("\n" + "="*80)
    print("统计分析报告")
    print("="*80)
    
    # 创建Markdown报告
    md_lines = []
    md_lines.append("# 手势识别日志统计分析报告\n")
    
    # ========== 1. 全局统计 ==========
    print("\n【1. 全局统计】")
    md_lines.append("## 1. 全局统计\n")
    
    total_samples = len(df)
    print(f"  总样本数: {total_samples}")
    md_lines.append(f"- **总样本数**: {total_samples}\n")
    
    print("\n  raw_label_norm 分布:")
    md_lines.append("\n### raw_label_norm 分布\n")
    label_dist = df['raw_label_norm'].value_counts()
    for label, count in label_dist.items():
        pct = count / total_samples * 100
        print(f"    {label}: {count} ({pct:.1f}%)")
        md_lines.append(f"- {label}: {count} ({pct:.1f}%)\n")
    
    print("\n  pred_by_score 分布:")
    md_lines.append("\n### pred_by_score 分布\n")
    pred_dist = df['pred_by_score'].value_counts()
    for gesture, count in pred_dist.items():
        pct = count / total_samples * 100
        print(f"    {gesture}: {count} ({pct:.1f}%)")
        md_lines.append(f"- {gesture}: {count} ({pct:.1f}%)\n")
    
    # ========== 2. Ground Truth准确率 ==========
    if gt_gesture and 'is_correct_by_score' in df.columns:
        print("\n【2. Ground Truth 准确率分析】")
        md_lines.append("\n## 2. Ground Truth 准确率分析\n")
        md_lines.append(f"**Ground Truth**: {gt_gesture}\n")
        
        # 总体准确率
        overall_acc = df['is_correct_by_score'].mean() * 100
        print(f"  总体准确率 (by score): {overall_acc:.2f}%")
        md_lines.append(f"\n- **总体准确率 (by score)**: {overall_acc:.2f}%\n")
        
        # 按距离分组的准确率
        print("\n  按距离分组的准确率:")
        md_lines.append("\n### 按距离分组的准确率\n")
        md_lines.append("\n| 距离组 | 样本数 | 准确率 |\n")
        md_lines.append("|--------|--------|--------|\n")
        
        for group in ['far', 'mid', 'near']:
            group_df = df[df['scale_group'] == group]
            if len(group_df) > 0:
                group_acc = group_df['is_correct_by_score'].mean() * 100
                print(f"    {group}: {len(group_df)} 样本, 准确率 {group_acc:.2f}%")
                md_lines.append(f"| {group} | {len(group_df)} | {group_acc:.2f}% |\n")
    
    # ========== 3. 各手势特征统计 ==========
    print("\n【3. 各手势特征统计】")
    md_lines.append("\n## 3. 各手势特征统计\n")
    
    feature_cols = ['lenIdx', 'lenMid', 'lenRing', 'lenLit', 
                    'gapIdxMid', 'gapThumbIdx',
                    'ratio_idx_mid', 'ratio_ring_mid', 'ratio_lit_mid', 'scale']
    
    for gesture in sorted(df['pred_by_score'].unique()):
        subset = df[df['pred_by_score'] == gesture]
        if len(subset) == 0:
            continue
            
        print(f"\n  === {gesture} 手势 (n={len(subset)}) ===")
        md_lines.append(f"\n### {gesture} 手势 (n={len(subset)})\n")
        
        stats = subset[feature_cols].describe(percentiles=[0.1, 0.25, 0.5, 0.75, 0.9])
        
        # 选择关键统计量
        key_stats = stats.loc[['mean', 'std', 'min', '10%', '50%', '90%', 'max']]
        
        print(key_stats.to_string())
        md_lines.append("\n```\n")
        md_lines.append(key_stats.to_string())
        md_lines.append("\n```\n")
    
    # ========== 4. 正确vs错误样本对比 ==========
    if gt_gesture and 'is_correct_by_score' in df.columns:
        correct = df[df['is_correct_by_score'] == True]
        wrong = df[df['is_correct_by_score'] == False]
        
        if len(correct) > 0 and len(wrong) > 0:
            print(f"\n【4. {gt_gesture}手势: 正确 vs 错误样本对比】")
            md_lines.append(f"\n## 4. {gt_gesture}手势: 正确 vs 错误样本对比\n")
            
            print(f"  正确样本: {len(correct)}, 错误样本: {len(wrong)}")
            md_lines.append(f"\n- 正确样本: {len(correct)}\n")
            md_lines.append(f"- 错误样本: {len(wrong)}\n")
            
            # 对比关键特征
            comparison_features = ['scale', 'gapIdxMid', 'gapThumbIdx', 
                                   'ratio_idx_mid', 'ratio_ring_mid', 'ratio_lit_mid']
            
            md_lines.append("\n### 特征对比表\n")
            md_lines.append("\n| 特征 | 正确-均值 | 正确-中位数 | 错误-均值 | 错误-中位数 | 差异 |\n")
            md_lines.append("|------|-----------|-------------|-----------|-------------|------|\n")
            
            print("\n  特征对比:")
            for feat in comparison_features:
                if feat in correct.columns:
                    c_mean = correct[feat].mean()
                    c_median = correct[feat].median()
                    w_mean = wrong[feat].mean()
                    w_median = wrong[feat].median()
                    diff = c_mean - w_mean
                    
                    print(f"    {feat:20s}: 正确均值={c_mean:.3f}, 错误均值={w_mean:.3f}, 差异={diff:+.3f}")
                    md_lines.append(
                        f"| {feat} | {c_mean:.3f} | {c_median:.3f} | "
                        f"{w_mean:.3f} | {w_median:.3f} | {diff:+.3f} |\n"
                    )
    
    # 保存Markdown报告
    md_path = os.path.join(output_dir, 'stats_summary.md')
    with open(md_path, 'w', encoding='utf-8') as f:
        f.writelines(md_lines)
    
    print(f"\n统计报告已保存: {md_path}")


def plot_distributions(df: pd.DataFrame, output_dir: str, gt_gesture: Optional[str] = None):
    """
    生成可视化图表
    
    Args:
        df: 完整的DataFrame
        output_dir: 输出目录
        gt_gesture: Ground Truth手势（可选）
    """
    print("\n正在生成可视化图表...")
    
    # 设置中文字体
    plt.rcParams['font.sans-serif'] = ['Arial Unicode MS', 'SimHei', 'DejaVu Sans']
    plt.rcParams['axes.unicode_minus'] = False
    
    # ========== 1. scale分布直方图 ==========
    plt.figure(figsize=(10, 6))
    
    colors = {'far': 'red', 'mid': 'orange', 'near': 'green'}
    for group in ['far', 'mid', 'near']:
        subset = df[df['scale_group'] == group]
        if len(subset) > 0:
            plt.hist(subset['scale'], alpha=0.5, label=group, 
                    bins=30, color=colors[group], edgecolor='black')
    
    plt.xlabel('Scale (Average Finger Length)', fontsize=12)
    plt.ylabel('Frequency', fontsize=12)
    plt.legend(fontsize=11)
    plt.title('Distribution of Scale by Distance Group', fontsize=14)
    plt.grid(axis='y', alpha=0.3)
    
    hist_path = os.path.join(output_dir, 'hist_scale_by_group.png')
    plt.savefig(hist_path, dpi=150, bbox_inches='tight')
    plt.close()
    print(f"  已保存: {hist_path}")
    
    # ========== 2. scale vs score_v 散点图 ==========
    plt.figure(figsize=(10, 6))
    
    gesture_colors = {'V': 'blue', 'OK': 'green', 'Palm': 'orange', 
                     'Fist': 'red', 'Idx': 'purple'}
    
    for gesture in df['pred_by_score'].unique():
        subset = df[df['pred_by_score'] == gesture]
        color = gesture_colors.get(gesture, 'gray')
        plt.scatter(subset['scale'], subset['score_v'], 
                   label=gesture, alpha=0.6, s=30, color=color)
    
    plt.xlabel('Scale (Average Finger Length)', fontsize=12)
    plt.ylabel('Score V', fontsize=12)
    plt.legend(fontsize=10)
    plt.title('Scale vs Score V (colored by predicted gesture)', fontsize=14)
    plt.grid(alpha=0.3)
    
    scatter_path = os.path.join(output_dir, 'scatter_scale_vs_score_v.png')
    plt.savefig(scatter_path, dpi=150, bbox_inches='tight')
    plt.close()
    print(f"  已保存: {scatter_path}")
    
    # ========== 3. V手势特定分析图（仅GT=V时） ==========
    if gt_gesture == 'V' and 'is_correct_by_score' in df.columns:
        plt.figure(figsize=(10, 6))
        
        correct = df[df['is_correct_by_score'] == True]
        wrong = df[df['is_correct_by_score'] == False]
        
        if len(correct) > 0:
            plt.scatter(correct['ratio_idx_mid'], correct['score_v'],
                       c='green', label='Correct', alpha=0.6, s=50, edgecolors='darkgreen')
        
        if len(wrong) > 0:
            plt.scatter(wrong['ratio_idx_mid'], wrong['score_v'],
                       c='red', label='Wrong', alpha=0.6, s=50, edgecolors='darkred')
        
        plt.xlabel('ratio_idx_mid (Index/Middle Length Ratio)', fontsize=12)
        plt.ylabel('score_v', fontsize=12)
        plt.legend(fontsize=11)
        plt.title('V Gesture: idx/mid ratio vs score_v (Correct vs Wrong)', fontsize=14)
        plt.grid(alpha=0.3)
        
        v_scatter_path = os.path.join(output_dir, 'scatter_idxmidratio_vs_score_v_correct_wrong.png')
        plt.savefig(v_scatter_path, dpi=150, bbox_inches='tight')
        plt.close()
        print(f"  已保存: {v_scatter_path}")
    
    print("可视化图表生成完成")


def main():
    """主函数"""
    args = parse_args()
    
    print("="*80)
    print("手势识别日志分析工具")
    print("="*80)
    print(f"日志文件: {args.log_file}")
    print(f"输出目录: {args.output_dir}")
    if args.gt_gesture:
        print(f"Ground Truth: {args.gt_gesture}")
    print(f"生成图表: {'是' if args.save_plots else '否'}")
    print("="*80)
    
    # 创建输出目录
    os.makedirs(args.output_dir, exist_ok=True)
    
    try:
        # 1. 解析日志文件
        df = parse_log_file(args.log_file)
        
        # 2. 添加派生特征
        df = add_derived_features(df, args.gt_gesture)
        
        # 3. 保存解析后的CSV
        csv_path = os.path.join(args.output_dir, 'gesture_parsed.csv')
        df.to_csv(csv_path, index=False, encoding='utf-8')
        print(f"\n解析数据已保存: {csv_path}")
        
        # 4. 统计分析
        print_and_save_stats(df, args.output_dir, args.gt_gesture)
        
        # 5. 生成可视化图表
        if args.save_plots:
            plot_distributions(df, args.output_dir, args.gt_gesture)
        
        print("\n" + "="*80)
        print(f"✓ 分析完成！所有结果已保存到: {args.output_dir}")
        print("="*80)
        
    except Exception as e:
        print(f"\n错误: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()

