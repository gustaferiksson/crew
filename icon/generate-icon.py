#!/usr/bin/env python3
import json
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent
BUNDLE = ROOT.parent / "Sources" / "AppIcon.icon"
ICTOOL = "/Applications/Icon Composer.app/Contents/Executables/ictool"
CANVAS = 1024
SIZE = 640
ORIGIN = (CANVAS - SIZE) / 2


def point(x, y):
    return f"{ORIGIN + x * SIZE:.1f} {ORIGIN + y * SIZE:.1f}"


blob = (
    f"M {point(0.2, 0.17)} "
    f"C {point(0.4, 0)} {point(0.78, 0.02)} {point(0.86, 0.2)} "
    f"C {point(1, 0.4)} {point(1, 0.72)} {point(0.78, 0.86)} "
    f"C {point(0.55, 1)} {point(0.2, 1)} {point(0.12, 0.78)} "
    f"C {point(0, 0.6)} {point(0, 0.3)} {point(0.2, 0.17)} Z"
)

eye_width = SIZE * 0.085
eye_height = SIZE * 0.235
eye_gap = SIZE * 0.104
eyes_center = (CANVAS / 2 + SIZE * 0.12, CANVAS / 2 - SIZE * 0.08)
eyes = "".join(
    f'<rect x="{cx - eye_width / 2:.1f}" y="{eyes_center[1] - eye_height / 2:.1f}" width="{eye_width:.1f}" height="{eye_height:.1f}" '
    f'rx="{eye_width / 2:.1f}" transform="rotate(-18 {cx:.1f} {eyes_center[1]:.1f})"/>'
    for cx in (eyes_center[0] - (eye_gap + eye_width) / 2, eyes_center[0] + (eye_gap + eye_width) / 2)
)


def svg(body, fill):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{CANVAS}" height="{CANVAS}" viewBox="0 0 {CANVAS} {CANVAS}"><g fill="{fill}">{body}</g></svg>\n'


PINK = "display-p3:0.925,0.282,0.600,1.00000"
DEEP = "display-p3:0.380,0.055,0.220,1.00000"
WHITE = "display-p3:1.00000,1.00000,1.00000,1.00000"

icon = {
    "fill": {"automatic-gradient": PINK},
    "fill-specializations": [
        {"value": {"automatic-gradient": PINK}},
        {"appearance": "dark", "value": {"automatic-gradient": "display-p3:0.160,0.040,0.100,1.00000"}},
    ],
    "groups": [
        {
            "name": "Eyes",
            "layers": [
                {
                    "name": "eyes",
                    "image-name": "eyes.svg",
                    "fill-specializations": [
                        {"value": {"solid": DEEP}},
                        {"appearance": "dark", "value": {"solid": WHITE}},
                    ],
                }
            ],
            "shadow": {"kind": "neutral", "opacity": 0.3},
            "translucency": {"enabled": False, "value": 0},
            "specular": True,
        },
        {
            "name": "Blob",
            "layers": [
                {
                    "name": "blob",
                    "image-name": "blob.svg",
                    "fill-specializations": [
                        {"value": {"solid": WHITE}},
                        {"appearance": "dark", "value": {"solid": PINK}},
                    ],
                }
            ],
            "shadow": {"kind": "neutral", "opacity": 0.5},
            "translucency": {"enabled": True, "value": 0.2},
            "specular": True,
        },
    ],
    "supported-platforms": {"circles": ["watchOS"], "squares": "shared"},
}

(BUNDLE / "Assets").mkdir(parents=True, exist_ok=True)
(BUNDLE / "Assets" / "blob.svg").write_text(svg(f'<path d="{blob}"/>', "#ffffff"))
(BUNDLE / "Assets" / "eyes.svg").write_text(svg(eyes, "#610e38"))
(BUNDLE / "icon.json").write_text(json.dumps(icon, indent=2) + "\n")

previews = ROOT / "previews"
previews.mkdir(exist_ok=True)
for platform in ("iOS", "macOS"):
    for rendition in ("Default", "Dark", "TintedLight", "TintedDark", "ClearLight", "ClearDark"):
        subprocess.run(
            [ICTOOL, str(BUNDLE), "--export-image", "--output-file", str(previews / f"{platform}-{rendition}.png"),
             "--platform", platform, "--rendition", rendition, "--width", "512", "--height", "512", "--scale", "1"],
            check=True,
        )
print(f"Wrote {BUNDLE} and previews in {previews}")
