#!/usr/bin/env python3
"""
交互式手势分析CLI - 引导式操作

功能:
- 📋 引导式菜单选择
- 🎯 智能建议和提示
- 📊 实时预览分析结果
- 💾 历史记录管理
- 🔄 批量分析支持

使用方法:
    python interactive_analyzer.py
"""

import os
import sys
import json
from pathlib import Path
from datetime import datetime
import subprocess

try:
    import pandas as pd
except ImportError:
    print("❌ 缺少pandas依赖，请运行: pip install pandas")
    sys.exit(1)


class InteractiveAnalyzer:
    """交互式分析器"""
    
    def __init__(self):
        self.history_file = Path.home() / '.gesture_analysis_history.json'
        self.history = self._load_history()
        
    def run(self):
        """运行交互式CLI"""
        while True:
            self._clear_screen()
            self._print_header()
            choice = self._show_menu()
            
            if choice == '1':
                self._analyze_single()
            elif choice == '2':
                self._analyze_batch()
            elif choice == '3':
                self._view_history()
            elif choice == '4':
                self._compare_results()
            elif choice == '5':
                self._show_help()
            elif choice == '0':
                print("\n👋 再见！")
                break
            else:
                print("\n❌ 无效选择，请重试")
                input("\n按Enter继续...")
    
    def _print_header(self):
        """打印头部"""
        print("=" * 80)
        print(" " * 25 + "🤖 交互式手势分析工具")
        print("=" * 80)
        print()
    
    def _show_menu(self) -> str:
        """显示菜单"""
        print("请选择操作：\n")
        print("  [1] 📊 分析单个日志文件")
        print("  [2] 📦 批量分析多个日志")
        print("  [3] 📜 查看历史记录")
        print("  [4] 🔄 对比分析结果")
        print("  [5] ❓ 帮助和教程")
        print("  [0] 🚪 退出")
        print()
        return input("👉 请输入选项: ").strip()
    
    def _analyze_single(self):
        """分析单个文件"""
        self._clear_screen()
        print("=" * 80)
        print("📊 单文件分析")
        print("=" * 80)
        print()
        
        # 1. 获取日志文件
        log_file = self._select_log_file()
        if not log_file:
            return
        
        # 2. 选择分析模式
        print("\n选择分析模式：")
        print("  [1] 🤖 智能分析（自动检测手势类型）")
        print("  [2] 🎯 指定手势分析")
        print("  [3] 📈 完整分析（包含所有统计）")
        
        mode = input("\n👉 选择模式 [1]: ").strip() or '1'
        
        gesture = None
        if mode == '2':
            print("\n选择目标手势：")
            print("  [1] V手势")
            print("  [2] OK手势")
            print("  [3] 手掌张开")
            print("  [4] 拳头")
            print("  [5] 食指")
            
            gesture_choice = input("\n👉 选择手势: ").strip()
            gesture_map = {'1': 'V', '2': 'OK', '3': 'Palm', '4': 'Fist', '5': 'Idx'}
            gesture = gesture_map.get(gesture_choice)
        
        # 3. 运行分析
        print("\n" + "=" * 80)
        print("开始分析...")
        print("=" * 80 + "\n")
        
        if mode == '1':
            # 智能分析
            cmd = ['python3', 'smart_analyzer.py', log_file]
        else:
            # 完整分析
            cmd = ['python3', 'analyze_gesture_log.py', '--log-file', log_file]
            if gesture:
                cmd.extend(['--gt-gesture', gesture])
        
        try:
            result = subprocess.run(cmd, timeout=120)
            
            if result.returncode == 0:
                # 记录到历史
                self._add_to_history(log_file, gesture, mode)
                
                print("\n✅ 分析完成！")
                
                # 询问是否打开报告
                if input("\n是否打开分析报告？[Y/n]: ").strip().lower() != 'n':
                    self._open_latest_report(log_file)
            else:
                print("\n❌ 分析失败")
        
        except subprocess.TimeoutExpired:
            print("\n⏱  分析超时")
        except Exception as e:
            print(f"\n❌ 错误: {e}")
        
        input("\n按Enter继续...")
    
    def _analyze_batch(self):
        """批量分析"""
        self._clear_screen()
        print("=" * 80)
        print("📦 批量分析")
        print("=" * 80)
        print()
        
        # 获取目录
        dir_path = input("请输入包含日志文件的目录路径: ").strip()
        
        if not os.path.isdir(dir_path):
            print("\n❌ 目录不存在")
            input("\n按Enter继续...")
            return
        
        # 查找所有.log文件
        log_files = list(Path(dir_path).glob('*.log'))
        
        if not log_files:
            print("\n❌ 未找到日志文件")
            input("\n按Enter继续...")
            return
        
        print(f"\n找到 {len(log_files)} 个日志文件：")
        for i, f in enumerate(log_files, 1):
            print(f"  [{i}] {f.name}")
        
        if input("\n是否分析所有文件？[Y/n]: ").strip().lower() == 'n':
            return
        
        # 批量分析
        print("\n开始批量分析...\n")
        
        for i, log_file in enumerate(log_files, 1):
            print(f"[{i}/{len(log_files)}] 分析 {log_file.name}...")
            
            cmd = ['python3', 'smart_analyzer.py', str(log_file)]
            
            try:
                subprocess.run(cmd, timeout=60, capture_output=True)
                print(f"  ✓ 完成")
            except:
                print(f"  ✗ 失败")
        
        print(f"\n✅ 批量分析完成！共处理 {len(log_files)} 个文件")
        input("\n按Enter继续...")
    
    def _view_history(self):
        """查看历史记录"""
        self._clear_screen()
        print("=" * 80)
        print("📜 分析历史记录")
        print("=" * 80)
        print()
        
        if not self.history:
            print("暂无历史记录")
        else:
            for i, record in enumerate(reversed(self.history[-10:]), 1):
                print(f"{i}. [{record['timestamp']}]")
                print(f"   文件: {record['file']}")
                print(f"   手势: {record.get('gesture', '自动检测')}")
                print(f"   模式: {record.get('mode', 'N/A')}")
                print()
        
        input("\n按Enter继续...")
    
    def _compare_results(self):
        """对比分析结果"""
        self._clear_screen()
        print("=" * 80)
        print("🔄 对比分析结果")
        print("=" * 80)
        print()
        
        print("请输入两个要对比的CSV文件：")
        file1 = input("  文件1: ").strip()
        file2 = input("  文件2: ").strip()
        
        if not os.path.exists(file1) or not os.path.exists(file2):
            print("\n❌ 文件不存在")
            input("\n按Enter继续...")
            return
        
        try:
            df1 = pd.read_csv(file1)
            df2 = pd.read_csv(file2)
            
            print("\n" + "=" * 80)
            print("对比结果")
            print("=" * 80)
            
            print(f"\n文件1样本数: {len(df1)}")
            print(f"文件2样本数: {len(df2)}")
            
            if 'is_correct' in df1.columns and 'is_correct' in df2.columns:
                acc1 = df1['is_correct'].mean() * 100
                acc2 = df2['is_correct'].mean() * 100
                
                print(f"\n准确率对比:")
                print(f"  文件1: {acc1:.1f}%")
                print(f"  文件2: {acc2:.1f}%")
                print(f"  差异: {acc2 - acc1:+.1f}%")
        
        except Exception as e:
            print(f"\n❌ 对比失败: {e}")
        
        input("\n按Enter继续...")
    
    def _show_help(self):
        """显示帮助"""
        self._clear_screen()
        print("=" * 80)
        print("❓ 帮助和教程")
        print("=" * 80)
        print()
        
        print("""
📚 快速入门

1️⃣  准备日志文件
   - 在iOS应用中录制手势视频
   - 从Xcode控制台复制日志
   - 保存为 .log 文件

2️⃣  运行分析
   - 选择"分析单个日志文件"
   - 使用智能分析模式（推荐新手）
   - 等待分析完成

3️⃣  查看结果
   - 自动打开HTML报告
   - 查看准确率和问题诊断
   - 根据建议优化代码

💡 高级技巧

- 批量分析：适合对比多个手势
- 历史记录：快速访问之前的分析
- 对比功能：验证优化效果

📖 相关文档

- 数据分析实战指南.md
- LOG_ANALYSIS_GUIDE.md
- PYTHON_TOOL_SUMMARY.md

🔗 工具链

1. interactive_analyzer.py (当前)
2. smart_analyzer.py (智能分析)
3. analyze_gesture_log.py (完整分析)
4. auto_workflow.py (自动化监控)
        """)
        
        input("\n按Enter继续...")
    
    def _select_log_file(self) -> str:
        """选择日志文件"""
        # 显示最近的文件
        recent_files = self._get_recent_files()
        
        if recent_files:
            print("最近使用的文件：")
            for i, f in enumerate(recent_files[:5], 1):
                print(f"  [{i}] {f}")
            print(f"  [0] 手动输入路径")
            
            choice = input("\n👉 选择文件 [0]: ").strip() or '0'
            
            if choice != '0' and choice.isdigit():
                idx = int(choice) - 1
                if 0 <= idx < len(recent_files):
                    return recent_files[idx]
        
        # 手动输入
        log_file = input("\n请输入日志文件路径: ").strip()
        
        if not os.path.exists(log_file):
            print("\n❌ 文件不存在")
            return None
        
        return log_file
    
    def _get_recent_files(self) -> list:
        """获取最近的文件"""
        if not self.history:
            return []
        
        files = [r['file'] for r in self.history[-10:]]
        return list(dict.fromkeys(reversed(files)))  # 去重保持顺序
    
    def _load_history(self) -> list:
        """加载历史记录"""
        if not self.history_file.exists():
            return []
        
        try:
            with open(self.history_file, 'r', encoding='utf-8') as f:
                return json.load(f)
        except:
            return []
    
    def _save_history(self):
        """保存历史记录"""
        with open(self.history_file, 'w', encoding='utf-8') as f:
            json.dump(self.history, f, indent=2, ensure_ascii=False)
    
    def _add_to_history(self, log_file: str, gesture: str, mode: str):
        """添加到历史"""
        self.history.append({
            'timestamp': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
            'file': log_file,
            'gesture': gesture,
            'mode': mode
        })
        self._save_history()
    
    def _open_latest_report(self, log_file: str):
        """打开最新的报告"""
        # 尝试找到最新的HTML报告
        base_name = Path(log_file).stem
        search_dirs = [
            Path(log_file).parent / f'smart_analysis_{base_name}',
            Path.cwd() / f'smart_analysis_{base_name}'
        ]
        
        for d in search_dirs:
            if d.exists():
                html_file = d / 'report.html'
                if html_file.exists():
                    try:
                        subprocess.run(['open', str(html_file)])
                        return
                    except:
                        pass
    
    def _clear_screen(self):
        """清屏"""
        os.system('clear' if os.name == 'posix' else 'cls')


def main():
    analyzer = InteractiveAnalyzer()
    analyzer.run()


if __name__ == "__main__":
    main()
