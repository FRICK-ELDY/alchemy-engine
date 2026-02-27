"""
Step 22: ダミー音声ファイル生成スクリプト
=========================================
Python 標準ライブラリのみで WAV ファイルを生成する。
BGM 用の OGG は pydub / ffmpeg が必要なため、ここでは WAV で代替する。

使い方:
    python gen_audio.py [出力ディレクトリ]
    出力ディレクトリ省略時はスクリプトと同じディレクトリ。例:
        python assets/_shared/gen_audio.py assets/vampire_survivor/audio

生成されるファイル:
    assets/audio/bgm.wav         ループ BGM（低音サイン波 8 秒）
    assets/audio/hit.wav         ヒット音（短いノイズバースト）
    assets/audio/death.wav       撃破音（下降音）
    assets/audio/level_up.wav    レベルアップ音（上昇アルペジオ）
    assets/audio/player_hurt.wav プレイヤーダメージ音（低音インパクト）
    assets/audio/item_pickup.wav アイテム収集音（高音チャイム）
"""

import math
import struct
import wave
import os
import sys

SAMPLE_RATE = 44100
OUTPUT_DIR  = (
    os.path.abspath(sys.argv[1])
    if len(sys.argv) > 1
    else os.path.dirname(os.path.abspath(__file__))
)


def write_wav(filename: str, samples: list[float], sample_rate: int = SAMPLE_RATE) -> None:
    """float サンプル列（-1.0〜1.0）を 16bit WAV として書き出す。"""
    path = os.path.join(OUTPUT_DIR, filename)
    with wave.open(path, "w") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sample_rate)
        raw = struct.pack(f"<{len(samples)}h",
                          *(int(s * 32767) for s in samples))
        wf.writeframes(raw)
    print(f"  生成: {path}")


def sine(freq: float, duration: float, amp: float = 0.5,
         sample_rate: int = SAMPLE_RATE) -> list[float]:
    n = int(sample_rate * duration)
    return [amp * math.sin(2 * math.pi * freq * i / sample_rate) for i in range(n)]


def envelope(samples: list[float], attack: float, release: float,
             sample_rate: int = SAMPLE_RATE) -> list[float]:
    """線形アタック・リリースエンベロープを適用する。"""
    n     = len(samples)
    atk_n = int(sample_rate * attack)
    rel_n = int(sample_rate * release)
    out   = list(samples)
    for i in range(min(atk_n, n)):
        out[i] *= i / atk_n
    for i in range(min(rel_n, n)):
        idx = n - 1 - i
        if idx >= 0:
            out[idx] *= i / rel_n
    return out


def mix(*tracks: list[float]) -> list[float]:
    """複数トラックをミックスする（長さは最短に揃える）。"""
    length = min(len(t) for t in tracks)
    return [sum(t[i] for t in tracks) / len(tracks) for i in range(length)]


def concat(*tracks: list[float]) -> list[float]:
    result: list[float] = []
    for t in tracks:
        result.extend(t)
    return result


def noise(duration: float, amp: float = 0.3,
          sample_rate: int = SAMPLE_RATE) -> list[float]:
    """疑似ランダムノイズ（線形合同法）。"""
    n   = int(sample_rate * duration)
    out = []
    x   = 12345
    for _ in range(n):
        x = (x * 1664525 + 1013904223) & 0xFFFFFFFF
        out.append(amp * ((x / 0x7FFFFFFF) - 1.0))
    return out


# ── BGM: 低音ドローン + 上音メロディ（8 秒ループ） ──────────────────
def gen_bgm() -> None:
    drone  = sine(55.0,  8.0, amp=0.25)   # A1
    mid    = sine(110.0, 8.0, amp=0.15)   # A2
    high   = sine(220.0, 8.0, amp=0.10)   # A3
    track  = [drone[i] + mid[i] + high[i] for i in range(len(drone))]
    # フェードイン・フェードアウト
    track  = envelope(track, attack=0.5, release=0.5)
    write_wav("bgm.wav", track)


# ── ヒット音: 短いノイズバースト ────────────────────────────────────
def gen_hit() -> None:
    n_seg  = noise(0.08, amp=0.6)
    n_seg  = envelope(n_seg, attack=0.002, release=0.05)
    write_wav("hit.wav", n_seg)


# ── 撃破音: 下降音 ──────────────────────────────────────────────────
def gen_death() -> None:
    freqs  = [440.0, 330.0, 220.0, 110.0]
    parts  = [envelope(sine(f, 0.08, amp=0.4), attack=0.005, release=0.05)
              for f in freqs]
    track  = concat(*parts)
    write_wav("death.wav", track)


# ── レベルアップ音: 上昇アルペジオ ─────────────────────────────────
def gen_level_up() -> None:
    freqs  = [261.63, 329.63, 392.00, 523.25]  # C4, E4, G4, C5
    parts  = [envelope(sine(f, 0.12, amp=0.45), attack=0.01, release=0.06)
              for f in freqs]
    track  = concat(*parts)
    write_wav("level_up.wav", track)


# ── プレイヤーダメージ音: 低音インパクト ────────────────────────────
def gen_player_hurt() -> None:
    impact = sine(80.0, 0.15, amp=0.5)
    n_seg  = noise(0.15, amp=0.3)
    track  = mix(impact, n_seg)
    track  = envelope(track, attack=0.003, release=0.10)
    write_wav("player_hurt.wav", track)


# ── アイテム収集音: 高音チャイム ────────────────────────────────────
def gen_item_pickup() -> None:
    freqs  = [880.0, 1046.50]  # A5, C6
    parts  = [envelope(sine(f, 0.10, amp=0.35), attack=0.005, release=0.07)
              for f in freqs]
    track  = concat(*parts)
    write_wav("item_pickup.wav", track)


if __name__ == "__main__":
    print("音声ファイルを生成中...")
    gen_bgm()
    gen_hit()
    gen_death()
    gen_level_up()
    gen_player_hurt()
    gen_item_pickup()
    print("完了！")
