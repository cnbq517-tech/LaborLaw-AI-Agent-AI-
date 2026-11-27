package com.laborlaw.aiassistant;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.Iterator;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Minimal native HTTPS SSE streaming bridge for Android WebView.
 * Runs HttpURLConnection off the main thread so OpenAI-compatible APIs
 * (DeepSeek, Qwen, SiliconFlow, etc.) stream reliably without WebView CORS blocks.
 */
@CapacitorPlugin(name = "NativeStream")
public class NativeStreamPlugin extends Plugin {
    private final ExecutorService executor = Executors.newCachedThreadPool();
    private final ConcurrentHashMap<String, HttpURLConnection> active = new ConcurrentHashMap<>();

    @PluginMethod
    public void startStream(PluginCall call) {
        final String requestId = call.getString("requestId", "");
        final String urlStr = call.getString("url", "");
        final String body = call.getString("body", "");
        final JSObject headers = call.getObject("headers", new JSObject());
        final int timeoutMs = call.getInt("timeoutMs", 90000);

        if (requestId.isEmpty() || urlStr.isEmpty()) {
            call.reject("Missing requestId or url");
            return;
        }

        // Resolve immediately; stream progress arrives via plugin events.
        call.resolve();

        executor.execute(() -> {
            HttpURLConnection conn = null;
            int status = 0;
            try {
                URL url = new URL(urlStr);
                conn = (HttpURLConnection) url.openConnection();
                active.put(requestId, conn);

                conn.setRequestMethod("POST");
                conn.setConnectTimeout(20000);
                conn.setReadTimeout(timeoutMs);
                conn.setDoInput(true);
                conn.setDoOutput(true);
                conn.setUseCaches(false);

                Iterator<String> keys = headers.keys();
                while (keys.hasNext()) {
                    String key = keys.next();
                    String val = headers.getString(key);
                    if (val != null) {
                        conn.setRequestProperty(key, val);
                    }
                }

                byte[] payload = body.getBytes(StandardCharsets.UTF_8);
                try (OutputStream os = conn.getOutputStream()) {
                    os.write(payload);
                    os.flush();
                }

                status = conn.getResponseCode();
                InputStream stream = (status >= 200 && status < 300)
                        ? conn.getInputStream()
                        : conn.getErrorStream();

                if (status < 200 || status >= 300) {
                    String errBody = readAll(stream);
                    emitError(requestId, status, errBody.isEmpty() ? conn.getResponseMessage() : errBody);
                    return;
                }

                if (stream != null) {
                    try (BufferedReader reader = new BufferedReader(
                            new InputStreamReader(stream, StandardCharsets.UTF_8))) {
                        String line;
                        while ((line = reader.readLine()) != null) {
                            JSObject ev = new JSObject();
                            ev.put("requestId", requestId);
                            ev.put("chunk", line + "\n");
                            notifyListeners("streamChunk", ev);
                        }
                    }
                }

                JSObject endEv = new JSObject();
                endEv.put("requestId", requestId);
                endEv.put("status", status);
                notifyListeners("streamEnd", endEv);
            } catch (Exception ex) {
                emitError(requestId, status, ex.getMessage() != null ? ex.getMessage() : ex.toString());
            } finally {
                active.remove(requestId);
                if (conn != null) {
                    try {
                        conn.disconnect();
                    } catch (Exception ignored) {
                    }
                }
            }
        });
    }

    @PluginMethod
    public void abortStream(PluginCall call) {
        String requestId = call.getString("requestId", "");
        HttpURLConnection conn = active.remove(requestId);
        if (conn != null) {
            executor.execute(() -> {
                try {
                    conn.disconnect();
                } catch (Exception ignored) {
                }
            });
        }
        call.resolve();
    }

    private void emitError(String requestId, int status, String message) {
        JSObject ev = new JSObject();
        ev.put("requestId", requestId);
        ev.put("status", status);
        ev.put("message", message != null && message.length() > 300 ? message.substring(0, 300) : message);
        notifyListeners("streamError", ev);
    }

    private static String readAll(InputStream is) {
        if (is == null) return "";
        StringBuilder sb = new StringBuilder();
        try (BufferedReader br = new BufferedReader(new InputStreamReader(is, StandardCharsets.UTF_8))) {
            String line;
            while ((line = br.readLine()) != null && sb.length() < 512) {
                sb.append(line);
            }
        } catch (Exception ignored) {
        }
        return sb.toString();
    }
}
