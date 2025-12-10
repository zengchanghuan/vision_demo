#!/usr/bin/env python3
"""
简化版日志解析测试脚本（不需要pandas/matplotlib）
用于快速验证正则表达式是否能正确解析日志
"""

import re
import sys


def test_parse_log(log_path):
    """测试日志解析功能"""
    
    # 正则表达式模式
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
    
    print(f"测试文件: {log_path}")
    print("="*80)
    
    success_count = 0
    fail_count = 0
    
    with open(log_path, 'r', encoding='utf-8') as f:
        for line_num, line in enumerate(f, 1):
            if '[HandGestureDebug]' not in line:
                continue
                
            match = re.search(pattern, line)
            if match:
                success_count += 1
                data = match.groupdict()
                
                # 打印前3条解析结果
                if success_count <= 3:
                    print(f"\n行 {line_num} 解析成功:")
                    print(f"  标签: {data['raw_label']}")
                    print(f"  scale: {(float(data['lenIdx']) + float(data['lenMid']) + float(data['lenRing']) + float(data['lenLit'])) / 4:.3f}")
                    print(f"  gapIdxMid: {data['gapIdxMid']}")
                    print(f"  scores: V={data['score_v']}, Fist={data['score_fist']}")
            else:
                fail_count += 1
                print(f"\n行 {line_num} 解析失败:")
                print(f"  内容: {line.strip()[:100]}")
    
    print("\n" + "="*80)
    print(f"解析结果: 成功 {success_count} 条, 失败 {fail_count} 条")
    print("="*80)
    
    if success_count > 0:
        print("\n✓ 正则表达式工作正常！")
        print(f"建议: 安装完整依赖后运行 analyze_gesture_log.py 进行完整分析")
    else:
        print("\n✗ 未能解析任何数据，请检查日志格式")
        return False
    
    return True


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("用法: python test_parse.py <log_file>")
        print("示例: python test_parse.py test_gesture.log")
        sys.exit(1)
    
    log_file = sys.argv[1]
    success = test_parse_log(log_file)
    sys.exit(0 if success else 1)
