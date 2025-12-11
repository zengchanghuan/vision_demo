#!/usr/bin/env python3
"""
自动化工作流 - 监控Xcode日志并实时分析

功能:
- 🔍 实时监控指定日志文件
- 📊 自动触发分析（达到样本数阈值）
- 🔔 桌面通知（macOS）
- 📈 实时准确率显示
- 💾 自动保存分析报告

使用方法:
    # 监控特定日志文件
    python auto_workflow.py --log-file /tmp/gesture.log
    
    # 监控并指定手势类型
    python auto_workflow.py --log-file /tmp/gesture.log --gesture V
    
    # 自定义触发阈值
    python auto_workflow.py --log-file /tmp/gesture.log --threshold 50
"""

import argparse
import os
import sys
import time
import subprocess
from datetime import datetime
from pathlib import Path

try:
    import pandas as pd
except ImportError:
    print("❌ 缺少pandas依赖，请运行: pip install pandas")
    sys.exit(1)


class AutoWorkflow:
    """自动化工作流管理器"""
    
    def __init__(self, log_file: str, gesture: str = None, 
                 threshold: int = 30, output_dir: str = None):
        self.log_file = Path(log_file)
        self.gesture = gesture
        self.threshold = threshold
        self.output_dir = Path(output_dir) if output_dir else Path.cwd() / 'auto_analysis'
        self.output_dir.mkdir(exist_ok=True)
        
        self.last_line_count = 0
        self.analysis_count = 0
        
    def run(self):
        """运行自动化工作流"""
        print("=" * 80)
        print("🤖 自动化手势分析工作流")
        print("=" * 80)
        print(f"📁 监控文件: {self.log_file}")
        print(f"🎯 目标手势: {self.gesture or '自动检测'}")
        print(f"📊 触发阈值: {self.threshold} 条日志")
        print(f"📂 输出目录: {self.output_dir}")
        print("\n开始监控... (按 Ctrl+C 停止)")
        print("=" * 80 + "\n")
        
        try:
            while True:
                self._check_and_analyze()
                time.sleep(2)  # 每2秒检查一次
        except KeyboardInterrupt:
            print("\n\n⏸  监控已停止")
            print(f"✓ 共完成 {self.analysis_count} 次分析")
    
    def _check_and_analyze(self):
        """检查并分析"""
        if not self.log_file.exists():
            return
        
        # 统计日志行数
        with open(self.log_file, 'r', encoding='utf-8') as f:
            lines = [l for l in f if '[HandGestureDebug]' in l]
            current_count = len(lines)
        
        # 如果新增日志数达到阈值，触发分析
        new_lines = current_count - self.last_line_count
        
        if new_lines >= self.threshold:
            print(f"\n📊 检测到 {new_lines} 条新日志，触发分析...")
            self._run_analysis()
            self.last_line_count = current_count
            self.analysis_count += 1
        else:
            # 实时显示进度
            progress = min(new_lines / self.threshold * 100, 100)
            bar_length = 40
            filled = int(bar_length * progress / 100)
            bar = '█' * filled + '░' * (bar_length - filled)
            
            print(f"\r进度: [{bar}] {new_lines}/{self.threshold} 条日志", end='', flush=True)
    
    def _run_analysis(self):
        """运行分析"""
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        output_subdir = self.output_dir / f'analysis_{timestamp}'
        
        # 调用smart_analyzer
        cmd = [
            'python3',
            'smart_analyzer.py',
            str(self.log_file),
            '-o', str(output_subdir)
        ]
        
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
            
            if result.returncode == 0:
                print(f"\n✅ 分析完成！")
                print(f"📁 报告: {output_subdir / 'report.html'}")
                
                # 发送macOS通知
                self._send_notification(
                    "手势分析完成",
                    f"分析结果已保存到 {output_subdir.name}"
                )
                
                # 尝试打开HTML报告
                try:
                    subprocess.run(['open', str(output_subdir / 'report.html')])
                except:
                    pass
            else:
                print(f"\n❌ 分析失败: {result.stderr}")
        
        except subprocess.TimeoutExpired:
            print("\n⏱  分析超时")
        except Exception as e:
            print(f"\n❌ 分析出错: {e}")
    
    def _send_notification(self, title: str, message: str):
        """发送macOS通知"""
        try:
            script = f'''
            display notification "{message}" with title "{title}" sound name "Glass"
            '''
            subprocess.run(['osascript', '-e', script], capture_output=True)
        except:
            pass


def main():
    parser = argparse.ArgumentParser(
        description='自动化手势分析工作流 - 实时监控和分析',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    
    parser.add_argument(
        '--log-file',
        required=True,
        help='要监控的日志文件路径'
    )
    
    parser.add_argument(
        '--gesture',
        choices=['V', 'OK', 'Palm', 'Fist', 'Idx'],
        help='目标手势（可选，不指定则自动检测）'
    )
    
    parser.add_argument(
        '--threshold',
        type=int,
        default=30,
        help='触发分析的日志条数阈值（默认30）'
    )
    
    parser.add_argument(
        '--output-dir',
        help='输出目录（默认：./auto_analysis）'
    )
    
    args = parser.parse_args()
    
    workflow = AutoWorkflow(
        args.log_file,
        args.gesture,
        args.threshold,
        args.output_dir
    )
    
    workflow.run()


if __name__ == "__main__":
    main()
