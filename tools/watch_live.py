#!/usr/bin/env python3
"""实时监控Xcode终端日志"""
import time
import subprocess
from pathlib import Path

# 配置
TERMINAL_DIR = Path.home() / ".cursor/projects/Users-zengchanghuan-Desktop-workspace-swift-project-vision-demo/terminals"
LOG_OUT = Path.home() / "Desktop/workspace/swift_project/vision_demo/logs/live.log"
SCRIPT_DIR = Path(__file__).parent
PROJECT_DIR = SCRIPT_DIR.parent
VENV_PYTHON = Path.home() / ".cursor/worktrees/vision_demo/vwn/venv/bin/python3"

LOG_OUT.parent.mkdir(parents=True, exist_ok=True)

def find_latest_terminal():
    """找到最新的终端文件"""
    if not TERMINAL_DIR.exists():
        return None
    terminals = list(TERMINAL_DIR.glob("*.txt"))
    if not terminals:
        return None
    # 按修改时间排序，返回最新的
    return max(terminals, key=lambda p: p.stat().st_mtime)

# 找到最新的终端文件
TERMINAL = find_latest_terminal()

if not TERMINAL:
    print("❌ 未找到终端文件目录")
    print(f"   检查路径: {TERMINAL_DIR}")
    exit(1)

print("🎯 实时监控Xcode日志")
print(f"监控: {TERMINAL}")
print(f"输出: {LOG_OUT}")
print("按Ctrl+C停止\n")

last_count = 0
last_pos = 0  # 记录上次读取的位置

try:
    while True:
        # 检查是否有新的终端文件（可能切换了终端）
        new_terminal = find_latest_terminal()
        if new_terminal and new_terminal != TERMINAL:
            print(f"🔄 检测到新终端文件，切换到: {new_terminal.name}")
            TERMINAL = new_terminal
            last_pos = 0  # 重置位置
        
        if TERMINAL.exists():
            logs = []
            current_pos = 0
            
            try:
                with open(TERMINAL, 'r', errors='ignore') as f:
                    # 如果文件被截断（重新开始），重置位置
                    file_size = TERMINAL.stat().st_size
                    if last_pos > file_size:
                        last_pos = 0
                    
                    # 跳转到上次读取的位置
                    f.seek(last_pos)
                    
                    for line in f:
                        if '[HandGestureDebug]' in line:
                            logs.append(line.strip())
                        current_pos = f.tell()
            except (IOError, OSError) as e:
                print(f"⚠️  读取文件错误: {e}")
                time.sleep(1)
                continue
            
            if logs:
                new = len(logs)
                print(f"📝 +{new} 条新日志 (总:{last_count + new})")
                
                # 追加到日志文件
                try:
                    with open(LOG_OUT, 'a') as f:
                        f.write('\n'.join(logs) + '\n')
                except (IOError, OSError) as e:
                    print(f"⚠️  写入日志文件错误: {e}")
                
                last_count += new
                last_pos = current_pos
                
                # 每20条分析一次
                if last_count >= 20 and last_count % 20 == 0:
                    print("🔄 触发分析...")
                    cmd = [
                        str(VENV_PYTHON),
                        str(PROJECT_DIR / "analyze_gesture_log.py"),
                        "--log-file", str(LOG_OUT),
                        "--gt-gesture", "V",
                        "--output-dir", str(PROJECT_DIR / "live_analysis")
                    ]
                    result = subprocess.run(cmd, cwd=str(PROJECT_DIR),
                                          capture_output=True, text=True)
                    if result.returncode == 0:
                        print("✅ 分析完成")
                    else:
                        print(f"⚠️  分析失败: {result.stderr[:200]}")
        
        time.sleep(1)

except KeyboardInterrupt:
    print(f"\n⏹️  停止监控 (总计:{last_count}条)")
    if last_count > 0 and LOG_OUT.exists() and LOG_OUT.stat().st_size > 0:
        print("🔍 最终分析...")
        video_id = f"final_{int(time.time())}"
        cmd = [
            str(VENV_PYTHON),
            str(PROJECT_DIR / "analyze_gesture_log.py"),
            "--log-file", str(LOG_OUT),
            "--gt-gesture", "V",
            "--output-dir", str(PROJECT_DIR / "live_analysis")
        ]
        result = subprocess.run(cmd, cwd=str(PROJECT_DIR))
        if result.returncode == 0:
            print("✅ 最终分析完成")
        else:
            print("⚠️  最终分析失败")
