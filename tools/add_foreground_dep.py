# -*- coding: utf-8 -*-
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "mobile_app"

pubspec = APP / "pubspec.yaml"
content = pubspec.read_text(encoding="utf-8")
if "flutter_foreground_task" not in content:
    content = content.replace(
        "  intl: ^0.19.0\n",
        "  intl: ^0.19.0\n  flutter_foreground_task: ^8.17.0\n"
    )
    pubspec.write_text(content, encoding="utf-8")
    print("flutter_foreground_task added to pubspec.yaml")
else:
    print("already present")
