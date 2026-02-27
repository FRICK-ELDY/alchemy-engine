"""
アトラス画像生成スクリプト（共通・assets/_shared）
出力先を第1引数で指定可能。例:
    python assets/_shared/gen_atlas.py assets/vampire_survivor/sprites
"""
import subprocess
import sys
import os

target = os.path.join(os.path.dirname(__file__), '..', 'sprites', 'gen_atlas.py')
subprocess.run([sys.executable, target] + sys.argv[1:], check=True)
