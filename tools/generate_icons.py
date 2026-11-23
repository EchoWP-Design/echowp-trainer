"""Erzeugt App-Symbole für EchoWP Trainer aus dem runden Elefanten-Logo.

Aufruf: python tools/generate_icons.py trainer/static/icons
        node tools/render_icons.js trainer/static/icons pruefbild.png  (PNG-Export, braucht Playwright)"""
import sys
from pathlib import Path

out = Path(sys.argv[1])
ELEPHANT = '''<g fill="none" stroke="#FFD400" stroke-width="22" stroke-linecap="round" stroke-linejoin="round"><path d="M104 62 C 60 34, 18 80, 34 130 C 44 160, 74 170, 98 150"/><path d="M104 62 C 132 40, 176 50, 182 92 C 186 120, 172 140, 160 160 C 150 178, 156 198, 176 196 C 192 194, 198 178, 194 164"/><path d="M216 180 A 32 32 0 0 0 220 138" stroke-width="14"/></g><circle cx="150" cy="90" r="11" fill="#FFD400"/>'''
# Produktzeichen: kleine Hantel rechts unter dem Echo-Bogen, mit schwarzer Lücke
# Kettlebell (Schwerpunkt Functional Fitness)
DUMBBELL = '''<path d="M214 228 C 206 196, 256 196, 248 228" fill="none" stroke="#FFD400" stroke-width="8" stroke-linecap="round"/><path d="M209 236 a22 20 0 0 1 44 0 c0 9 -4 14 -8 16 h-28 c-4 -2 -8 -7 -8 -16z" fill="#FFD400"/>'''

def svg(bg: str, scale: float, round_bg: bool) -> str:
    # Inhalt (Elefant + Hantel) um die Bildmitte skalieren
    inner_scale = 1.6 * scale
    # Motiv (Gruppenkoordinaten x 23..250, y 40..251) mittig setzen
    cx, cy = 136, 146
    tx = 256 - cx * inner_scale
    ty = 256 - cy * inner_scale
    back = '<circle cx="256" cy="256" r="256" fill="#0A0A0A"/>' if round_bg else (f'<rect width="512" height="512" fill="{bg}"/>' if bg else '')
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">{back}'
            f'<g transform="translate({tx:.1f},{ty:.1f}) scale({inner_scale:.3f})">{ELEPHANT}{DUMBBELL}</g></svg>')

out.mkdir(parents=True, exist_ok=True)
(out / "app-icon.svg").write_text(svg("", 0.92, True))          # rund, für Browser/Desktop
(out / "app-icon-maskable.svg").write_text(svg("#0A0A0A", 0.68, False))  # Android-Sicherheitszone
print("ok")
