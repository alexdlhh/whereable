# -*- coding: utf-8 -*-
from pathlib import Path

p = Path(__file__).resolve().parents[1] / "firmware" / "src" / "wifi_server.cpp"
t = p.read_text(encoding="utf-8")
start = t.find('server.on("/mic_sample"')
end = t.find("server.on(\"/camera_config\"")
if start < 0 or end < 0:
    raise SystemExit(f"markers not found start={start} end={end}")
replacement = '''server.on("/mic_sample", HTTP_GET, [](AsyncWebServerRequest* request) {
        static int16_t micBuf[8000];
        const size_t samples = 8000;
        size_t got = AudioDriver::readMicSamples(micBuf, samples);
        AsyncWebServerResponse* response = request->beginResponse_P(
            200, "application/octet-stream", (uint8_t*)micBuf, got * sizeof(int16_t));
        addCors(response);
        request->send(response);
    });

    '''
t = t[:start] + replacement + t[end:]
p.write_text(t, encoding="utf-8")
print("fixed mic_sample")

p2 = Path(__file__).resolve().parents[1] / "mobile_app" / "lib" / "features" / "assistant_screen" / "assistant_view.dart"
t2 = p2.read_text(encoding="utf-8").replace("withValues(alpha: 0.35)", "withOpacity(0.35)")
p2.write_text(t2, encoding="utf-8")
print("fixed withOpacity")
