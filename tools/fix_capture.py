# -*- coding: utf-8 -*-
from pathlib import Path

p = Path(__file__).resolve().parents[1] / "firmware" / "src" / "wifi_server.cpp"
t = p.read_text(encoding="utf-8")
start = t.find('server.on("/capture"')
end = t.find('server.on("/play_audio"')
if start < 0 or end < 0:
    raise SystemExit(f"markers not found start={start} end={end}")
replacement = r'''server.on("/capture", HTTP_GET, [](AsyncWebServerRequest* request) {
        camera_fb_t* fb = CameraDriver::captureFrame();
        if (!fb) {
            AsyncWebServerResponse* response = request->beginResponse(
                503, "application/json", "{\"error\":\"camera_busy_or_unavailable\",\"status\":\"fail\"}");
            addCors(response);
            request->send(response);
            return;
        }

        const size_t len = fb->len;
        uint8_t* copy = (uint8_t*)malloc(len);
        if (!copy) {
            CameraDriver::releaseFrame(fb);
            request->send(500, "application/json", "{\"error\":\"oom\"}");
            return;
        }
        memcpy(copy, fb->buf, len);
        CameraDriver::releaseFrame(fb);

        AsyncWebServerResponse* response = request->beginResponse(
            "image/jpeg",
            len,
            [copy, len](uint8_t* buffer, size_t maxLen, size_t index) -> size_t {
                if (index >= len) return 0;
                size_t chunk = min(maxLen, len - index);
                memcpy(buffer, copy + index, chunk);
                if (index + chunk >= len) {
                    free(copy);
                }
                return chunk;
            }
        );
        addCors(response);
        request->send(response);
    });

    '''
p.write_text(t[:start] + replacement + t[end:], encoding="utf-8")
print("fixed /capture copy-out")
