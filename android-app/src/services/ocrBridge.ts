import { Capacitor, registerPlugin, type PluginListenerHandle } from '@capacitor/core';

export interface OcrLineResult {
  text: string;
  left: number;
  centerY: number;
  height: number;
}

export interface OcrImageResult {
  text: string;
  lines: OcrLineResult[];
  width: number;
  height: number;
}

export interface PdfExtractResult {
  text: string;
  pageCount: number;
  processedPages: number;
  truncated: boolean;
}

export interface SharedImagePayload {
  name: string;
  dataUrl: string;
  width: number;
  height: number;
}

interface OnDeviceOcrPlugin {
  recognizeImage(options: { base64: string }): Promise<OcrImageResult>;
  extractPdfText(options: { base64: string; maxPages?: number }): Promise<PdfExtractResult>;
  takePendingSharedImages(): Promise<{ images: SharedImagePayload[] }>;
  addListener(
    eventName: 'sharedImagesReceived',
    listenerFunc: (data: { images: SharedImagePayload[] }) => void
  ): Promise<PluginListenerHandle>;
}

const OnDeviceOcr = registerPlugin<OnDeviceOcrPlugin>('OnDeviceOcr');

export async function recognizeImageOnDevice(dataUrl: string): Promise<OcrImageResult> {
  if (!Capacitor.isNativePlatform()) {
    throw new Error('端侧中文 OCR 需要在 Android 真机上运行');
  }
  return OnDeviceOcr.recognizeImage({ base64: dataUrl });
}

export async function extractPdfTextOnDevice(
  base64: string,
  maxPages = 15
): Promise<PdfExtractResult> {
  if (!Capacitor.isNativePlatform()) {
    throw new Error('PDF 扫描件端侧识别需要在 Android 真机上运行');
  }
  return OnDeviceOcr.extractPdfText({ base64, maxPages });
}

export async function takePendingSharedImages(): Promise<SharedImagePayload[]> {
  if (!Capacitor.isNativePlatform()) return [];
  try {
    const res = await OnDeviceOcr.takePendingSharedImages();
    return Array.isArray(res.images) ? res.images : [];
  } catch {
    return [];
  }
}

export async function listenSharedImages(
  callback: (images: SharedImagePayload[]) => void
): Promise<() => void> {
  if (!Capacitor.isNativePlatform()) return () => {};
  try {
    const handle = await OnDeviceOcr.addListener('sharedImagesReceived', (data) => {
      if (Array.isArray(data.images) && data.images.length > 0) {
        callback(data.images);
      }
    });
    return () => {
      handle.remove().catch(() => {});
    };
  } catch {
    return () => {};
  }
}

export async function fileToCompressedDataUrl(
  file: File,
  maxSide = 1600
): Promise<{ dataUrl: string; width: number; height: number }> {
  const objectUrl = URL.createObjectURL(file);
  try {
    const img = await new Promise<HTMLImageElement>((resolve, reject) => {
      const el = new Image();
      el.onload = () => resolve(el);
      el.onerror = () => reject(new Error('无法读取所选图片'));
      el.src = objectUrl;
    });

    const longest = Math.max(img.naturalWidth, img.naturalHeight);
    const scale = longest > maxSide ? maxSide / longest : 1;
    const width = Math.max(1, Math.round(img.naturalWidth * scale));
    const height = Math.max(1, Math.round(img.naturalHeight * scale));

    const canvas = document.createElement('canvas');
    canvas.width = width;
    canvas.height = height;
    const ctx = canvas.getContext('2d');
    if (!ctx) throw new Error('无法创建图片画布');
    ctx.fillStyle = '#FFFFFF';
    ctx.fillRect(0, 0, width, height);
    ctx.drawImage(img, 0, 0, width, height);
    const dataUrl = canvas.toDataURL('image/jpeg', 0.86);
    return { dataUrl, width, height };
  } finally {
    URL.revokeObjectURL(objectUrl);
  }
}

export function arrayBufferToBase64(buffer: ArrayBuffer): string {
  const bytes = new Uint8Array(buffer);
  let binary = '';
  const chunkSize = 0x8000;
  for (let i = 0; i < bytes.length; i += chunkSize) {
    const sub = bytes.subarray(i, i + chunkSize);
    binary += String.fromCharCode(...sub);
  }
  return btoa(binary);
}
