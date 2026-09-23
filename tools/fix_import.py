from pathlib import Path
p = Path(__file__).resolve().parents[1] / "mobile_app" / "lib" / "features" / "assistant_screen" / "assistant_view.dart"
t = p.read_text(encoding="utf-8")
t = t.replace("import 'dart:typed_data';\n", "")
p.write_text(t, encoding="utf-8")
print("removed unused import")
