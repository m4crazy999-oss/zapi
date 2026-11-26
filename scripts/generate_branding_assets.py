#!/usr/bin/env python3
"""
Gerador determinístico de assets PNG para ícone adaptativo e splash screen do Zapi.
Usa apenas biblioteca padrão do Python (sem dependências externas), com antialiasing 2x.
"""

import math
import os
import struct
import zlib


def write_png(filepath: str, width: int, height: int, rgba_bytes: bytes) -> None:
    os.makedirs(os.path.dirname(filepath), exist_ok=True)

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack("!I", len(data))
            + tag
            + data
            + struct.pack("!I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)
        start = y * stride
        raw.extend(rgba_bytes[start : start + stride])

    ihdr = struct.pack("!IIBBBBB", width, height, 8, 6, 0, 0, 0)
    compressed = zlib.compress(bytes(raw), level=6)
    png_data = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", compressed)
        + chunk(b"IEND", b"")
    )
    with open(filepath, "wb") as f:
        f.write(png_data)


def sd_rounded_box(px: float, py: float, cx: float, cy: float, hx: float, hy: float, r: float) -> float:
    dx = abs(px - cx) - hx + r
    dy = abs(py - cy) - hy + r
    return math.hypot(max(dx, 0.0), max(dy, 0.0)) + min(max(dx, dy), 0.0) - r


def sd_segment(px: float, py: float, ax: float, ay: float, bx: float, by: float, radius: float) -> float:
    pax = px - ax
    pay = py - ay
    bax = bx - ax
    bay = by - ay
    h = max(0.0, min(1.0, (pax * bax + pay * bay) / (bax * bax + bay * bay)))
    return math.hypot(pax - bax * h, pay - bay * h) - radius


def sd_triangle(px: float, py: float, x0: float, y0: float, x1: float, y1: float, x2: float, y2: float) -> float:
    def edge(ax: float, ay: float, bx: float, by: float) -> tuple[float, float]:
        ex, ey = bx - ax, by - ay
        wx, wy = px - ax, py - ay
        t = max(0.0, min(1.0, (wx * ex + wy * ey) / (ex * ex + ey * ey)))
        dx, dy = wx - ex * t, wy - ey * t
        return dx * dx + dy * dy, ex * wy - ey * wx

    d0, c0 = edge(x0, y0, x1, y1)
    d1, c1 = edge(x1, y1, x2, y2)
    d2, c2 = edge(x2, y2, x0, y0)
    d = min(d0, d1, d2)
    s = (x1 - x0) * (y2 - y0) - (y1 - y0) * (x2 - x0)
    inside = min(c0 * s, c1 * s, c2 * s) >= 0.0
    return (-math.sqrt(d)) if inside else math.sqrt(d)


def smoothstep_alpha(dist: float, aa: float = 1.4) -> float:
    if dist <= -aa:
        return 1.0
    if dist >= aa:
        return 0.0
    t = (aa - dist) / (2.0 * aa)
    return t * t * (3.0 - 2.0 * t)


def blend(dst: tuple[float, float, float, float], src: tuple[float, float, float, float]) -> tuple[float, float, float, float]:
    sr, sg, sb, sa = src
    dr, dg, db, da = dst
    out_a = sa + dr * 0.0 + da * (1.0 - sa)
    if out_a <= 1e-6:
        return (0.0, 0.0, 0.0, 0.0)
    r = (sr * sa + dr * da * (1.0 - sa)) / out_a
    g = (sg * sa + dg * da * (1.0 - sa)) / out_a
    b = (sb * sa + db * da * (1.0 - sa)) / out_a
    return (r, g, b, out_a)


def render_zapi_mark(
    size: int,
    scale_ratio: float,
    with_background: bool,
    bubble_rgb: tuple[float, float, float],
    z_rgb: tuple[float, float, float],
) -> bytes:
    buf = bytearray(size * size * 4)
    cx = size * 0.5
    cy = size * 0.5
    u = size * scale_ratio

    # Dimensões normalizadas do balão e da letra Z (centralizado considerando a cauda)
    hx = 0.34 * u
    hy = 0.28 * u
    br = 0.16 * u
    bubble_cy = cy - 0.06 * u

    # Cauda do balão no canto inferior esquerdo
    tx0, ty0 = cx - 0.22 * u, bubble_cy + hy - 0.05 * u
    tx1, ty1 = cx - 0.31 * u, bubble_cy + hy + 0.12 * u
    tx2, ty2 = cx - 0.05 * u, bubble_cy + hy - 0.01 * u

    # Coordenadas do Z geométrico dentro do balão
    zx_l = cx - 0.135 * u
    zx_r = cx + 0.135 * u
    zy_t = bubble_cy - 0.115 * u
    zy_b = bubble_cy + 0.115 * u
    stroke_r = 0.036 * u

    for y in range(size):
        row_offset = y * size * 4
        for x in range(size):
            px = x + 0.5
            py = y + 0.5

            if with_background:
                t = ((x / size) * 0.55 + (y / size) * 0.45)
                bg_r = 0.0
                bg_g = 200.0 * (1.0 - t) + 142.0 * t
                bg_b = 151.0 * (1.0 - t) + 111.0 * t
                color = (bg_r, bg_g, bg_b, 1.0)
            else:
                color = (0.0, 0.0, 0.0, 0.0)

            d_box = sd_rounded_box(px, py, cx, bubble_cy, hx, hy, br)
            d_tail = sd_triangle(px, py, tx0, ty0, tx1, ty1, tx2, ty2)
            d_bubble = min(d_box, d_tail)
            a_bubble = smoothstep_alpha(d_bubble, aa=1.5)

            if a_bubble > 0.0:
                color = blend(color, (bubble_rgb[0], bubble_rgb[1], bubble_rgb[2], a_bubble))

                # Letra Z com 3 segmentos arredondados
                d_top = sd_segment(px, py, zx_l, zy_t, zx_r, zy_t, stroke_r)
                d_diag = sd_segment(px, py, zx_r, zy_t, zx_l, zy_b, stroke_r)
                d_bot = sd_segment(px, py, zx_l, zy_b, zx_r, zy_b, stroke_r)
                d_z = min(d_top, d_diag, d_bot)
                a_z = smoothstep_alpha(d_z, aa=1.3) * a_bubble
                if a_z > 0.0:
                    color = blend(color, (z_rgb[0], z_rgb[1], z_rgb[2], a_z))

            idx = row_offset + x * 4
            buf[idx] = max(0, min(255, int(round(color[0]))))
            buf[idx + 1] = max(0, min(255, int(round(color[1]))))
            buf[idx + 2] = max(0, min(255, int(round(color[2]))))
            buf[idx + 3] = max(0, min(255, int(round(color[3] * 255.0))))

    return bytes(buf)


def main() -> None:
    root_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    emerald = (0.0, 168.0, 132.0)
    bright_emerald = (0.0, 200.0, 151.0)
    white = (255.0, 255.0, 255.0)

    # 1. Ícone completo (1024x1024)
    write_png(
        os.path.join(root_dir, "assets/icon/app_icon.png"),
        1024,
        1024,
        render_zapi_mark(1024, scale_ratio=0.92, with_background=True, bubble_rgb=white, z_rgb=emerald),
    )

    # 2. Camada foreground do ícone adaptativo (zona segura de 62%, <= 66%)
    write_png(
        os.path.join(root_dir, "assets/icon/icon_foreground.png"),
        1024,
        1024,
        render_zapi_mark(1024, scale_ratio=0.90, with_background=False, bubble_rgb=white, z_rgb=emerald),
    )

    # 3. Splash claro e escuro (Android < 12, marca proporcional centralizada)
    write_png(
        os.path.join(root_dir, "assets/splash/splash_logo.png"),
        512,
        512,
        render_zapi_mark(512, scale_ratio=0.72, with_background=False, bubble_rgb=emerald, z_rgb=white),
    )
    write_png(
        os.path.join(root_dir, "assets/splash/splash_logo_dark.png"),
        512,
        512,
        render_zapi_mark(512, scale_ratio=0.72, with_background=False, bubble_rgb=bright_emerald, z_rgb=white),
    )

    # 4. Splash Android 12+ (1152x1152 com logo ocupando ~57.8% <= 60% na zona circular segura)
    write_png(
        os.path.join(root_dir, "assets/splash/android12_splash_icon.png"),
        1152,
        1152,
        render_zapi_mark(1152, scale_ratio=0.85, with_background=False, bubble_rgb=emerald, z_rgb=white),
    )
    write_png(
        os.path.join(root_dir, "assets/splash/android12_splash_icon_dark.png"),
        1152,
        1152,
        render_zapi_mark(1152, scale_ratio=0.85, with_background=False, bubble_rgb=bright_emerald, z_rgb=white),
    )

    print("Assets PNG do Zapi gerados com sucesso.")


if __name__ == "__main__":
    main()
