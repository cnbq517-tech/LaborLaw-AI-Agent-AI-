package com.laborlaw.aiassistant;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Rect;
import android.graphics.pdf.PdfRenderer;
import android.os.ParcelFileDescriptor;
import android.util.Base64;

import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import com.google.android.gms.tasks.Tasks;
import com.google.mlkit.vision.common.InputImage;
import com.google.mlkit.vision.text.Text;
import com.google.mlkit.vision.text.TextRecognition;
import com.google.mlkit.vision.text.TextRecognizer;
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions;

import java.io.File;
import java.io.FileOutputStream;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * On-device ML Kit Chinese OCR, scanned PDF renderer + OCR, and incoming system share image queue.
 * Images never leave the device.
 */
@CapacitorPlugin(name = "OnDeviceOcr")
public class OnDeviceOcrPlugin extends Plugin {
    private static final List<JSObject> pendingShares = Collections.synchronizedList(new ArrayList<>());
    private static volatile OnDeviceOcrPlugin activeInstance = null;

    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private TextRecognizer recognizer;

    @Override
    public void load() {
        super.load();
        activeInstance = this;
    }

    @Override
    protected void handleOnDestroy() {
        if (activeInstance == this) {
            activeInstance = null;
        }
        if (recognizer != null) {
            try {
                recognizer.close();
            } catch (Exception ignored) {
            }
            recognizer = null;
        }
        super.handleOnDestroy();
    }

    private synchronized TextRecognizer getRecognizer() {
        if (recognizer == null) {
            recognizer = TextRecognition.getClient(new ChineseTextRecognizerOptions.Builder().build());
        }
        return recognizer;
    }

    public static void enqueueSharedImage(String name, String dataUrl, int width, int height) {
        JSObject item = new JSObject();
        item.put("name", name);
        item.put("dataUrl", dataUrl);
        item.put("width", width);
        item.put("height", height);
        pendingShares.add(item);

        OnDeviceOcrPlugin instance = activeInstance;
        if (instance != null) {
            JSObject payload = new JSObject();
            JSArray arr = new JSArray();
            arr.put(item);
            payload.put("images", arr);
            instance.notifyListeners("sharedImagesReceived", payload, true);
        }
    }

    @PluginMethod
    public void takePendingSharedImages(PluginCall call) {
        JSArray arr = new JSArray();
        synchronized (pendingShares) {
            for (JSObject item : pendingShares) {
                arr.put(item);
            }
            pendingShares.clear();
        }
        JSObject ret = new JSObject();
        ret.put("images", arr);
        call.resolve(ret);
    }

    @PluginMethod
    public void recognizeImage(PluginCall call) {
        final String base64 = call.getString("base64", "");
        if (base64.isEmpty()) {
            call.reject("Missing base64 image data");
            return;
        }

        executor.execute(() -> {
            Bitmap bitmap = null;
            try {
                String pure = stripDataUrlPrefix(base64);
                byte[] bytes = Base64.decode(pure, Base64.DEFAULT);
                bitmap = decodeScaledBitmap(bytes, 2048);
                if (bitmap == null) {
                    call.reject("无法解码图片");
                    return;
                }

                InputImage image = InputImage.fromBitmap(bitmap, 0);
                Text result = Tasks.await(getRecognizer().process(image));

                JSArray lines = new JSArray();
                StringBuilder fullText = new StringBuilder();
                for (Text.TextBlock block : result.getTextBlocks()) {
                    for (Text.Line line : block.getLines()) {
                        String t = line.getText();
                        if (t == null || t.trim().isEmpty()) continue;
                        if (fullText.length() > 0) fullText.append('\n');
                        fullText.append(t.trim());

                        Rect box = line.getBoundingBox();
                        JSObject lineObj = new JSObject();
                        lineObj.put("text", t.trim());
                        lineObj.put("left", box != null ? box.left : 0);
                        lineObj.put("centerY", box != null ? (box.top + box.bottom) / 2.0 : 0);
                        lineObj.put("height", box != null ? Math.max(1, box.height()) : 20);
                        lines.put(lineObj);
                    }
                }

                JSObject ret = new JSObject();
                ret.put("text", fullText.toString());
                ret.put("lines", lines);
                ret.put("width", bitmap.getWidth());
                ret.put("height", bitmap.getHeight());
                call.resolve(ret);
            } catch (Exception ex) {
                call.reject("端侧 OCR 识别失败：" + (ex.getMessage() != null ? ex.getMessage() : ex.toString()));
            } finally {
                if (bitmap != null && !bitmap.isRecycled()) {
                    bitmap.recycle();
                }
            }
        });
    }

    @PluginMethod
    public void extractPdfText(PluginCall call) {
        final String base64 = call.getString("base64", "");
        final int maxPages = Math.min(25, Math.max(1, call.getInt("maxPages", 15)));
        if (base64.isEmpty()) {
            call.reject("Missing base64 PDF data");
            return;
        }

        executor.execute(() -> {
            File tmp = null;
            ParcelFileDescriptor pfd = null;
            PdfRenderer renderer = null;
            try {
                byte[] bytes = Base64.decode(stripDataUrlPrefix(base64), Base64.DEFAULT);
                tmp = File.createTempFile("contract_", ".pdf", getContext().getCacheDir());
                try (FileOutputStream fos = new FileOutputStream(tmp)) {
                    fos.write(bytes);
                }

                pfd = ParcelFileDescriptor.open(tmp, ParcelFileDescriptor.MODE_READ_ONLY);
                renderer = new PdfRenderer(pfd);
                int totalPages = renderer.getPageCount();
                int pagesToRead = Math.min(totalPages, maxPages);
                StringBuilder combined = new StringBuilder();

                for (int i = 0; i < pagesToRead; i++) {
                    PdfRenderer.Page page = renderer.openPage(i);
                    Bitmap bmp = null;
                    try {
                        int targetW = Math.min(1800, Math.max(1200, page.getWidth() * 2));
                        int targetH = (int) Math.round((double) page.getHeight() * targetW / Math.max(1, page.getWidth()));
                        bmp = Bitmap.createBitmap(targetW, targetH, Bitmap.Config.ARGB_8888);
                        Canvas canvas = new Canvas(bmp);
                        canvas.drawColor(Color.WHITE);
                        page.render(bmp, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY);

                        InputImage image = InputImage.fromBitmap(bmp, 0);
                        Text result = Tasks.await(getRecognizer().process(image));
                        String pageText = result.getText();
                        if (pageText != null && !pageText.trim().isEmpty()) {
                            if (combined.length() > 0) combined.append("\n\n");
                            combined.append(pageText.trim());
                        }
                    } finally {
                        if (bmp != null && !bmp.isRecycled()) {
                            bmp.recycle();
                        }
                        page.close();
                    }
                }

                JSObject ret = new JSObject();
                ret.put("text", combined.toString());
                ret.put("pageCount", totalPages);
                ret.put("processedPages", pagesToRead);
                ret.put("truncated", totalPages > maxPages);
                call.resolve(ret);
            } catch (Exception ex) {
                call.reject("PDF 端侧识别失败：" + (ex.getMessage() != null ? ex.getMessage() : ex.toString()));
            } finally {
                if (renderer != null) {
                    try {
                        renderer.close();
                    } catch (Exception ignored) {
                    }
                }
                if (pfd != null) {
                    try {
                        pfd.close();
                    } catch (Exception ignored) {
                    }
                }
                if (tmp != null && tmp.exists()) {
                    tmp.delete();
                }
            }
        });
    }

    private static String stripDataUrlPrefix(String s) {
        int idx = s.indexOf(',');
        return (idx >= 0 && s.startsWith("data:")) ? s.substring(idx + 1) : s;
    }

    private static Bitmap decodeScaledBitmap(byte[] bytes, int maxSide) {
        BitmapFactory.Options bounds = new BitmapFactory.Options();
        bounds.inJustDecodeBounds = true;
        BitmapFactory.decodeByteArray(bytes, 0, bytes.length, bounds);
        int sample = 1;
        int longest = Math.max(bounds.outWidth, bounds.outHeight);
        while (longest / sample > maxSide) {
            sample *= 2;
        }
        BitmapFactory.Options opts = new BitmapFactory.Options();
        opts.inSampleSize = sample;
        return BitmapFactory.decodeByteArray(bytes, 0, bytes.length, opts);
    }
}
