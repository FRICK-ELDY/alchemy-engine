"""
音声ファイル生成スクリプト（共通・assets/_shared）
出力先を第1引数で指定可能。例:
    python assets/_shared/gen_audio.py assets/vampire_survivor/audio
"""
import subprocess
import sys
import os

target = os.path.join(os.path.dirname(__file__), '..', 'audio', 'gen_audio.py')
subprocess.run([sys.executable, target] + sys.argv[1:], check=True)
