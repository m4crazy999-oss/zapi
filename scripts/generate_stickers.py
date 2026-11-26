#!/usr/bin/env python3
"""
Gerador determinístico de 12 figurinhas originais do Zapi (512x512 PNG com fundo transparente).
Usa apenas a biblioteca padrão do Python (sem dependências externas), garantindo
reprodução idêntica localmente e no GitHub Actions.
"""

import math
import os
import struct
import zlib

SIZE = 512


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


def sd_circle(px: float, py: float, cx: float, cy: float, r: float) -> float:
    return math.hypot(px - cx, py - cy) - r


def sd_rounded_box(px: float, py: float, cx: float, cy: float, hx: float, hy: float, r: float) -> float:
    dx = abs(px - cx) - hx + r
    dy = abs(py - cy) - hy + r
    return math.hypot(max(dx, 0.0), max(dy, 0.0)) + min(max(dx, dy), 0.0) - r


def sd_segment(px: float, py: float, ax: float, ay: float, bx: float, by: float, r: float) -> float:
    pax = px - ax
    pay = py - ay
    bax = bx - ax
    bay = by - ay
    denom = bax * bax + bay * bay
    h = max(0.0, min(1.0, (pax * bax + pay * bay) / denom)) if denom > 0 else 0.0
    return math.hypot(pax - bax * h, pay - bay * h) - r


def sd_heart(px: float, py: float, cx: float, cy: float, scale: float) -> float:
    x = abs(px - cx) / scale
    y = (cy - py) / scale + 0.35
    if y + x > 1.0:
        return (math.hypot(x - 0.25, y - 0.75) - 0.35355339) * scale
    d1 = math.hypot(x, y - 1.0)
    d2 = math.hypot(x - 0.5 * max(x + y, 0.0), y - 0.5 * max(x + y, 0.0))
    sign = -1.0 if (x - y < 0.0) else 1.0
    return (min(d1, d2) * sign) * scale


def sd_star5(px: float, py: float, cx: float, cy: float, r: float, rf: float = 0.46) -> float:
    x = abs(px - cx)
    y = py - cy
    k1x, k1y = 0.809016994375, -0.587785252292
    k2x, k2y = -0.809016994375, -0.587785252292
    dot1 = 2.0 * min(k1x * x + k1y * y, 0.0)
    x -= dot1 * k1x
    y -= dot1 * k1y
    dot2 = 2.0 * min(k2x * x + k2y * y, 0.0)
    x -= dot2 * k2x
    y -= dot2 * k2y
    x = abs(x)
    y -= r
    bax = rf * -k1y - 0.0
    bay = rf * k1x - 1.0
    # Aproximação limpa por segmento para ponta
    ex = rf * 0.587785252292 * r
    ey = rf * 0.809016994375 * r - (-r)
    return sd_segment(x, y + r, 0.0, -r, ex, -rf * 0.809016994375 * r, 4.0)


def sd_arc_smile(px: float, py: float, cx: float, cy: float, r: float, thick: float, open_mouth: bool = False) -> float:
    dx = px - cx
    dy = py - cy
    if dy < 0.0:
        return min(math.hypot(dx - r, dy), math.hypot(dx + r, dy)) - thick
    if open_mouth:
        return max(math.hypot(dx, dy) - r, -dy) - thick * 0.35
    return abs(math.hypot(dx, dy) - r) - thick


def alpha_from_sd(d: float, aa: float = 1.6) -> float:
    if d <= -aa:
        return 1.0
    if d >= aa:
        return 0.0
    t = (aa - d) / (2.0 * aa)
    return t * t * (3.0 - 2.0 * t)


def blend(dst: list[float], r: float, g: float, b: float, a: float) -> None:
    if a <= 0.0:
        return
    da = dst[3]
    out_a = a + da * (1.0 - a)
    if out_a <= 1e-6:
        return
    dst[0] = (r * a + dst[0] * da * (1.0 - a)) / out_a
    dst[1] = (g * a + dst[1] * da * (1.0 - a)) / out_a
    dst[2] = (b * a + dst[2] * da * (1.0 - a)) / out_a
    dst[3] = out_a


def render_sticker(pixel_fn) -> bytes:
    buf = bytearray(SIZE * SIZE * 4)
    for y in range(SIZE):
        row = y * SIZE * 4
        py = y + 0.5
        for x in range(SIZE):
            px = x + 0.5
            rgba = [0.0, 0.0, 0.0, 0.0]
            pixel_fn(px, py, rgba)
            idx = row + x * 4
            buf[idx] = max(0, min(255, int(round(rgba[0]))))
            buf[idx + 1] = max(0, min(255, int(round(rgba[1]))))
            buf[idx + 2] = max(0, min(255, int(round(rgba[2]))))
            buf[idx + 3] = max(0, min(255, int(round(rgba[3] * 255.0))))
    return bytes(buf)


def draw_face_base(px: float, py: float, rgba: list[float], fill_top: tuple[float, float, float], fill_bot: tuple[float, float, float]) -> bool:
    d_outer = sd_circle(px, py, 256.0, 256.0, 214.0)
    if d_outer > 2.0:
        return False
    a_border = alpha_from_sd(d_outer)
    blend(rgba, 255.0, 255.0, 255.0, a_border)
    d_inner = sd_circle(px, py, 256.0, 256.0, 196.0)
    a_fill = alpha_from_sd(d_inner)
    if a_fill > 0.0:
        t = max(0.0, min(1.0, (py - 60.0) / 392.0))
        r = fill_top[0] * (1.0 - t) + fill_bot[0] * t
        g = fill_top[1] * (1.0 - t) + fill_bot[1] * t
        b = fill_top[2] * (1.0 - t) + fill_bot[2] * t
        blend(rgba, r, g, b, a_fill)
    return True


def sticker_oi(px: float, py: float, rgba: list[float]) -> None:
    d_box = sd_rounded_box(px, py, 256.0, 240.0, 188.0, 146.0, 74.0)
    # Cauda esquerda
    d_tail = sd_segment(px, py, 148.0, 355.0, 96.0, 422.0, 24.0)
    d_shape = min(d_box, d_tail)
    a_white = alpha_from_sd(d_shape - 16.0)
    if a_white <= 0.0:
        return
    blend(rgba, 255.0, 255.0, 255.0, a_white)
    a_fill = alpha_from_sd(d_shape)
    if a_fill > 0.0:
        t = max(0.0, min(1.0, (px + py) / 1024.0))
        blend(rgba, 0.0, 196.0 * (1 - t) + 148.0 * t, 148.0 * (1 - t) + 114.0 * t, a_fill)
        # Letras "OI!" desenhadas por primitivas geométricas
        d_o = abs(sd_circle(px, py, 188.0, 240.0, 46.0)) - 13.0
        d_i = sd_segment(px, py, 276.0, 192.0, 276.0, 288.0, 14.0)
        d_bang_top = sd_segment(px, py, 336.0, 188.0, 336.0, 250.0, 13.0)
        d_bang_dot = sd_circle(px, py, 336.0, 282.0, 13.5)
        d_text = min(d_o, d_i, d_bang_top, d_bang_dot)
        blend(rgba, 255.0, 255.0, 255.0, alpha_from_sd(d_text) * a_fill)


def sticker_feliz(px: float, py: float, rgba: list[float]) -> None:
    if not draw_face_base(px, py, rgba, (255.0, 218.0, 82.0), (245.0, 166.0, 35.0)):
        return
    d_eyes = min(sd_circle(px, py, 192.0, 218.0, 20.0), sd_circle(px, py, 320.0, 218.0, 20.0))
    d_mouth = sd_arc_smile(px, py, 256.0, 266.0, 74.0, 13.0)
    d_blush = min(sd_circle(px, py, 146.0, 268.0, 22.0), sd_circle(px, py, 366.0, 268.0, 22.0))
    blend(rgba, 251.0, 113.0, 133.0, alpha_from_sd(d_blush) * 0.45)
    blend(rgba, 45.0, 34.0, 24.0, alpha_from_sd(min(d_eyes, d_mouth)))


def sticker_coracao(px: float, py: float, rgba: list[float]) -> None:
    d_h = sd_heart(px, py, 256.0, 272.0, 248.0)
    a_white = alpha_from_sd(d_h - 18.0)
    if a_white <= 0.0:
        return
    blend(rgba, 255.0, 255.0, 255.0, a_white)
    a_fill = alpha_from_sd(d_h)
    if a_fill > 0.0:
        t = max(0.0, min(1.0, (py - 90.0) / 330.0))
        blend(rgba, 255.0, 72.0 * (1 - t) + 32.0 * t, 108.0 * (1 - t) + 74.0 * t, a_fill)
        d_gloss = sd_circle(px, py, 192.0, 192.0, 26.0)
        blend(rgba, 255.0, 220.0, 230.0, alpha_from_sd(d_gloss) * 0.55 * a_fill)


def sticker_riso(px: float, py: float, rgba: list[float]) -> None:
    if not draw_face_base(px, py, rgba, (255.0, 222.0, 92.0), (244.0, 162.0, 32.0)):
        return
    # Olhos fechados felizes em ^ ^
    d_le = min(
        sd_segment(px, py, 166.0, 226.0, 192.0, 198.0, 10.0),
        sd_segment(px, py, 192.0, 198.0, 218.0, 226.0, 10.0),
    )
    d_re = min(
        sd_segment(px, py, 294.0, 226.0, 320.0, 198.0, 10.0),
        sd_segment(px, py, 320.0, 198.0, 346.0, 226.0, 10.0),
    )
    d_mouth = sd_arc_smile(px, py, 256.0, 262.0, 86.0, 12.0, open_mouth=True)
    blend(rgba, 45.0, 34.0, 24.0, alpha_from_sd(min(d_le, d_re, d_mouth)))
    # Língua coral dentro da boca
    d_tongue = max(sd_circle(px, py, 256.0, 336.0, 40.0), d_mouth + 4.0)
    blend(rgba, 244.0, 63.0, 94.0, alpha_from_sd(d_tongue))


def sticker_apaixonado(px: float, py: float, rgba: list[float]) -> None:
    if not draw_face_base(px, py, rgba, (255.0, 220.0, 90.0), (244.0, 165.0, 36.0)):
        return
    d_lh = sd_heart(px, py, 190.0, 220.0, 76.0)
    d_rh = sd_heart(px, py, 322.0, 220.0, 76.0)
    blend(rgba, 239.0, 48.0, 84.0, alpha_from_sd(min(d_lh, d_rh)))
    d_mouth = sd_arc_smile(px, py, 256.0, 276.0, 66.0, 12.0)
    blend(rgba, 45.0, 34.0, 24.0, alpha_from_sd(d_mouth))


def sticker_surpreso(px: float, py: float, rgba: list[float]) -> None:
    if not draw_face_base(px, py, rgba, (165.0, 243.0, 252.0), (56.0, 189.0, 248.0)):
        return
    d_eyes_bg = min(sd_circle(px, py, 192.0, 206.0, 34.0), sd_circle(px, py, 320.0, 206.0, 34.0))
    blend(rgba, 255.0, 255.0, 255.0, alpha_from_sd(d_eyes_bg))
    d_pupils = min(sd_circle(px, py, 192.0, 208.0, 16.0), sd_circle(px, py, 320.0, 208.0, 16.0))
    d_mouth = sd_circle(px, py, 256.0, 322.0, 38.0)
    blend(rgba, 17.0, 24.0, 39.0, alpha_from_sd(min(d_pupils, d_mouth)))


def sticker_piscadinha(px: float, py: float, rgba: list[float]) -> None:
    if not draw_face_base(px, py, rgba, (110.0, 231.0, 183.0), (0.0, 168.0, 132.0)):
        return
    d_eye_l = sd_circle(px, py, 192.0, 214.0, 21.0)
    d_wink = sd_segment(px, py, 294.0, 216.0, 346.0, 216.0, 11.0)
    d_mouth = sd_arc_smile(px, py, 256.0, 268.0, 70.0, 12.0)
    blend(rgba, 17.0, 27.0, 33.0, alpha_from_sd(min(d_eye_l, d_wink, d_mouth)))


def sticker_joinha(px: float, py: float, rgba: list[float]) -> None:
    if not draw_face_base(px, py, rgba, (253.0, 224.0, 71.0), (234.0, 179.0, 8.0)):
        return
    # Selo com polegar estilizado ("TOP")
    d_palm = sd_rounded_box(px, py, 272.0, 286.0, 76.0, 62.0, 24.0)
    d_thumb = sd_segment(px, py, 236.0, 236.0, 260.0, 142.0, 26.0)
    d_cuff = sd_rounded_box(px, py, 166.0, 296.0, 26.0, 56.0, 12.0)
    blend(rgba, 255.0, 255.0, 255.0, alpha_from_sd(min(d_palm, d_thumb)))
    blend(rgba, 0.0, 168.0, 132.0, alpha_from_sd(d_cuff))


def sticker_festa(px: float, py: float, rgba: list[float]) -> None:
    if not draw_face_base(px, py, rgba, (192.0, 132.0, 252.0), (124.0, 58.0, 237.0)):
        return
    # Confetes coloridos e brilho central
    d_c1 = sd_circle(px, py, 160.0, 170.0, 22.0)
    d_c2 = sd_circle(px, py, 348.0, 168.0, 20.0)
    d_c3 = sd_circle(px, py, 152.0, 324.0, 18.0)
    d_c4 = sd_circle(px, py, 356.0, 318.0, 22.0)
    blend(rgba, 250.0, 204.0, 21.0, alpha_from_sd(min(d_c1, d_c4)))
    blend(rgba, 52.0, 211.0, 153.0, alpha_from_sd(min(d_c2, d_c3)))
    # Cone de festa
    d_cone = min(
        sd_segment(px, py, 204.0, 346.0, 298.0, 218.0, 22.0),
        sd_segment(px, py, 204.0, 346.0, 328.0, 304.0, 22.0),
        sd_segment(px, py, 286.0, 256.0, 246.0, 298.0, 36.0),
    )
    blend(rgba, 255.0, 255.0, 255.0, alpha_from_sd(d_cone))


def sticker_cafe(px: float, py: float, rgba: list[float]) -> None:
    d_cup = sd_rounded_box(px, py, 240.0, 298.0, 108.0, 96.0, 36.0)
    d_handle = abs(sd_circle(px, py, 356.0, 296.0, 44.0)) - 14.0
    d_steam1 = sd_segment(px, py, 198.0, 174.0, 208.0, 122.0, 11.0)
    d_steam2 = sd_segment(px, py, 256.0, 166.0, 266.0, 112.0, 11.0)
    d_steam3 = sd_segment(px, py, 310.0, 174.0, 320.0, 126.0, 11.0)
    d_all = min(d_cup, d_handle, d_steam1, d_steam2, d_steam3)
    a_white = alpha_from_sd(d_all - 16.0)
    if a_white <= 0.0:
        return
    blend(rgba, 255.0, 255.0, 255.0, a_white)
    blend(rgba, 120.0, 74.0, 44.0, alpha_from_sd(min(d_cup, d_handle)))
    blend(rgba, 203.0, 213.0, 225.0, alpha_from_sd(min(d_steam1, d_steam2, d_steam3)))


def sticker_fogo(px: float, py: float, rgba: list[float]) -> None:
    d_outer = min(
        sd_circle(px, py, 256.0, 304.0, 134.0),
        sd_segment(px, py, 256.0, 300.0, 256.0, 98.0, 56.0),
        sd_segment(px, py, 194.0, 292.0, 176.0, 186.0, 38.0),
        sd_segment(px, py, 320.0, 292.0, 338.0, 198.0, 36.0),
    )
    a_white = alpha_from_sd(d_outer - 16.0)
    if a_white <= 0.0:
        return
    blend(rgba, 255.0, 255.0, 255.0, a_white)
    a_fire = alpha_from_sd(d_outer)
    if a_fire > 0.0:
        t = max(0.0, min(1.0, (py - 90.0) / 340.0))
        blend(rgba, 255.0, 165.0 * (1 - t) + 65.0 * t, 0.0, a_fire)
        d_core = min(
            sd_circle(px, py, 256.0, 326.0, 72.0),
            sd_segment(px, py, 256.0, 326.0, 256.0, 210.0, 28.0),
        )
        blend(rgba, 254.0, 240.0, 138.0, alpha_from_sd(d_core) * a_fire)


def sticker_ok(px: float, py: float, rgba: list[float]) -> None:
    if not draw_face_base(px, py, rgba, (0.0, 200.0, 151.0), (0.0, 143.0, 112.0)):
        return
    d_check = min(
        sd_segment(px, py, 168.0, 266.0, 232.0, 330.0, 22.0),
        sd_segment(px, py, 232.0, 330.0, 348.0, 190.0, 22.0),
    )
    blend(rgba, 255.0, 255.0, 255.0, alpha_from_sd(d_check))


STICKERS = [
    ("zapi_oi.png", sticker_oi),
    ("zapi_feliz.png", sticker_feliz),
    ("zapi_coracao.png", sticker_coracao),
    ("zapi_riso.png", sticker_riso),
    ("zapi_apaixonado.png", sticker_apaixonado),
    ("zapi_surpreso.png", sticker_surpreso),
    ("zapi_piscadinha.png", sticker_piscadinha),
    ("zapi_joinha.png", sticker_joinha),
    ("zapi_festa.png", sticker_festa),
    ("zapi_cafe.png", sticker_cafe),
    ("zapi_fogo.png", sticker_fogo),
    ("zapi_ok.png", sticker_ok),
]


def main() -> None:
    root_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_dir = os.path.join(root_dir, "assets", "stickers")
    for filename, fn in STICKERS:
        filepath = os.path.join(out_dir, filename)
        write_png(filepath, SIZE, SIZE, render_sticker(fn))
    print(f"{len(STICKERS)} figurinhas PNG 512x512 geradas em {out_dir}.")


if __name__ == "__main__":
    main()
