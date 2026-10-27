"""Generate the original gold gear as an uncompressed 128px RGBA WoW texture."""
import math
from pathlib import Path
import struct

SIZE = 128
SAMPLES = 4


def render():
    pixels = bytearray()
    for y in range(SIZE):
        for x in range(SIZE):
            red = green = blue = alpha = 0
            for sy in range(SAMPLES):
                for sx in range(SAMPLES):
                    px = (x + (sx + 0.5) / SAMPLES) / SIZE - 0.5
                    py = (y + (sy + 0.5) / SAMPLES) / SIZE - 0.5
                    radius = math.hypot(px, py)
                    phase = abs((math.atan2(py, px) / (2 * math.pi) * 8 + 0.5) % 1 - 0.5)
                    tooth = max(0, min(1, (0.34 - phase) / 0.12))
                    edge = 0.325 + 0.115 * tooth
                    if not 0.135 <= radius <= edge:
                        continue
                    if radius < 0.153 or radius > edge - 0.015:
                        color = (139, 83, 7)
                    else:
                        t = max(0, min(1, py + 0.5))
                        color = (255, int(235 - 62 * t), int(107 - 87 * t))
                    red += color[0]
                    green += color[1]
                    blue += color[2]
                    alpha += 255
            coverage = SAMPLES * SAMPLES
            count = alpha // 255
            if count:
                pixels.extend((blue // count, green // count, red // count, alpha // coverage))
            else:
                pixels.extend((255, 255, 255, 0))
    # Top-left origin, eight alpha bits, BGRA pixels. No RLE for WoW compatibility.
    header = struct.pack('<BBBHHBHHHHBB', 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x28)
    return header + pixels


if __name__ == '__main__':
    path = Path(__file__).resolve().parents[1] / 'img' / 'settings_gear.tga'
    path.write_bytes(render())
    print(f'{path.name}: {SIZE}x{SIZE}, 32-bit RGBA')
