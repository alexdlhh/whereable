# -*- coding: utf-8 -*-
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "mobile_app"

pubspec = APP / "pubspec.yaml"
content = pubspec.read_text(encoding="utf-8")
print("current pubspec read")
