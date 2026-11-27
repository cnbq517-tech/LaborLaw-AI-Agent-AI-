package com.laborlaw.aiassistant;

import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.net.Uri;
import android.os.Bundle;
import android.util.Base64;

import com.getcapacitor.BridgeActivity;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.concurrent.Executors;

public class MainActivity extends BridgeActivity {
    @Override
    public void onCreate(Bundle savedInstanceState) {
        registerPlugin(NativeStreamPlugin.class);
        registerPlugin(OnDeviceOcrPlugin.class);
        super.onCreate(savedInstanceState);
        handleShareIntent(getIntent());
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        handleShareIntent(intent);
    }

    private void handleShareIntent(Intent intent) {
        if (intent == null) return;
        String action = intent.getAction();
        String type = intent.getType();
        if (type == null || !type.startsWith("image/")) return;

        final ArrayList<Uri> uris = new ArrayList<>();
        if (Intent.ACTION_SEND.equals(action)) {
            Uri uri = intent.getParcelableExtra(Intent.EXTRA_STREAM);
            if (uri != null) uris.add(uri);
        } else if (Intent.ACTION_SEND_MULTIPLE.equals(action)) {
            ArrayList<Uri> list = intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM);
            if (list != null) uris.addAll(list);
        }
        if (uris.isEmpty()) return;

        Executors.newSingleThreadExecutor().execute(() -> {
            int idx = 1;
            for (Uri uri : uris) {
                try (InputStream is = getContentResolver().openInputStream(uri)) {
                    if (is == null) continue;
                    Bitmap raw = BitmapFactory.decodeStream(is);
                    if (raw == null) continue;

                    Bitmap scaled = scaleDown(raw, 1600);
                    ByteArrayOutputStream baos = new ByteArrayOutputStream();
                    scaled.compress(Bitmap.CompressFormat.JPEG, 86, baos);
                    String b64 = Base64.encodeToString(baos.toByteArray(), Base64.NO_WRAP);
                    String name = "分享图片_" + idx + ".jpg";
                    OnDeviceOcrPlugin.enqueueSharedImage(
                            name,
                            "data:image/jpeg;base64," + b64,
                            scaled.getWidth(),
                            scaled.getHeight()
                    );
                    if (scaled != raw) scaled.recycle();
                    raw.recycle();
                    idx++;
                } catch (Exception ignored) {
                }
            }
        });
    }

    private static Bitmap scaleDown(Bitmap src, int maxSide) {
        int w = src.getWidth();
        int h = src.getHeight();
        int longest = Math.max(w, h);
        if (longest <= maxSide) return src;
        float ratio = (float) maxSide / longest;
        return Bitmap.createScaledBitmap(src, Math.round(w * ratio), Math.round(h * ratio), true);
    }
}
