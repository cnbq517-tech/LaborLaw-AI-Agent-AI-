import { unzipSync, strFromU8 } from 'fflate';
import { arrayBufferToBase64, extractPdfTextOnDevice } from './ocrBridge';

export interface ParsedContractFile {
  name: string;
  format: 'TXT' | 'DOCX' | 'PDF';
  text: string;
  scanned?: boolean;
  pageNote?: string;
}

const MAX_FILE_BYTES = 18 * 1024 * 1024; // 18MB guard (PDF scans can be larger)

function extractDocxText(bytes: Uint8Array): string {
  const entries = unzipSync(bytes);
  const docEntry = entries['word/document.xml'];
  if (!docEntry) {
    throw new Error('DOCX 文件缺少正文内容（word/document.xml）');
  }
  const xml = strFromU8(docEntry);
  const parser = new DOMParser();
  const doc = parser.parseFromString(xml, 'application/xml');
  if (doc.querySelector('parsererror')) {
    throw new Error('DOCX 正文 XML 解析失败');
  }

  const paragraphs = Array.from(doc.getElementsByTagName('w:p'));
  const lines: string[] = [];
  for (const p of paragraphs) {
    const parts: string[] = [];
    const walker = doc.createTreeWalker(p, NodeFilter.SHOW_ELEMENT);
    let node = walker.nextNode() as Element | null;
    while (node) {
      const tag = node.tagName;
      if (tag === 'w:t') {
        parts.push(node.textContent ?? '');
      } else if (tag === 'w:tab') {
        parts.push('\t');
      } else if (tag === 'w:br' || tag === 'w:cr') {
        parts.push('\n');
      }
      node = walker.nextNode() as Element | null;
    }
    const line = parts.join('').replace(/\r\n?/g, '\n');
    if (line.trim().length > 0) {
      lines.push(line.trim());
    }
  }
  return lines.join('\n');
}

export async function parseContractFile(file: File): Promise<ParsedContractFile> {
  if (file.size > MAX_FILE_BYTES) {
    throw new Error('文件超过 18MB 限制，请精简后再导入');
  }
  const lower = file.name.toLowerCase();
  if (lower.endsWith('.pdf') || file.type === 'application/pdf') {
    const buf = await file.arrayBuffer();
    const b64 = arrayBufferToBase64(buf);
    const res = await extractPdfTextOnDevice(b64, 15);
    if (res.text.trim().length < 10) {
      throw new Error('未在 PDF 中识别到有效合同文字，请确认画面清晰');
    }
    const pageNote = res.truncated
      ? `共 ${res.pageCount} 页，已端侧识别前 ${res.processedPages} 页`
      : `已端侧识别全部 ${res.processedPages} 页`;
    return {
      name: file.name,
      format: 'PDF',
      text: res.text.trim(),
      scanned: true,
      pageNote,
    };
  }
  if (lower.endsWith('.docx')) {
    const buf = await file.arrayBuffer();
    const text = extractDocxText(new Uint8Array(buf));
    if (text.trim().length < 10) {
      throw new Error('未在 DOCX 中提取到有效合同文字');
    }
    return { name: file.name, format: 'DOCX', text };
  }
  if (lower.endsWith('.txt') || lower.endsWith('.md') || file.type.startsWith('text/')) {
    const text = (await file.text()).replace(/\r\n?/g, '\n').trim();
    if (text.length < 10) {
      throw new Error('文本内容过短，请确认是否为有效合同');
    }
    return { name: file.name, format: 'TXT', text };
  }
  throw new Error('暂支持 .docx、.pdf（含扫描件）和 .txt 格式');
}
