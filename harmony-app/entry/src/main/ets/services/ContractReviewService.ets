import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { fileIo, picker } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { pdfService } from '@kit.PDFKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ContractAi, ParsedBatch, ReviewLaw } from '../contract/ContractAi';
import { ContractLaws, LawLocation } from '../contract/ContractLaws';
import { ContractRules } from '../contract/ContractRules';
import { ContractStructure } from '../contract/ContractStructure';
import {
  ClauseAnchor,
  ContractTerms,
  FactSheet,
  Finding,
  RuleResult,
  StructureAudit,
  StructureWarning,
  WHOLE_CONTRACT
} from '../contract/ContractTypes';
import { ApiConfig, ChatMessage, ChatRole, FileAttachment, KnowledgeResult, LawCitation } from '../models/AppModels';
import { AiApiClient, StreamHandle, StreamResult } from './AiApiClient';
import { AttachmentService } from './AttachmentService';
import { EvidencePipeline } from './EvidencePipeline';
import { KnowledgeService } from './KnowledgeService';
import { TASK_STRUCTURED } from './ModelTuning';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'ContractReview';
const STORE_FILE: string = 'contract_reviews.json';
const MAX_REPORTS: number = 20;
const MAX_CONTRACT_CHARS: number = 60000;
const MAX_PDF_BYTES: number = 20 * 1024 * 1024;
// Pages with less text than this are treated as scanned and recognized.
const SCANNED_PAGE_CHARS: number = 40;
const MAX_RETRIES: number = 2;

export const AI_NONE: string = 'none';
export const AI_DONE: string = 'done';
export const AI_PARTIAL: string = 'partial';
export const AI_FAILED: string = 'failed';

export class ContractSource {
  name: string;
  text: string;
  // Text from images or scanned pages: OCR mistakes are likely, so no
  // rewritten clauses are offered.
  scanned: boolean;
  note: string;

  constructor(name: string, text: string, scanned: boolean, note: string = '') {
    this.name = name;
    this.text = text;
    this.scanned = scanned;
    this.note = note;
  }
}

export class ContractReport {
  id: string = '';
  fileName: string = '';
  createdAt: number = 0;
  text: string = '';
  scanned: boolean = false;
  facts: FactSheet = new FactSheet();
  terms: ContractTerms = new ContractTerms();
  anchors: ClauseAnchor[] = [];
  warnings: StructureWarning[] = [];
  findings: Finding[] = [];
  aiState: string = AI_NONE;
  aiNote: string = '';
  aiBatches: AiBatch[] = [];
}

const MAX_BATCH_REASONING: number = 8000;

// One AI pass: which clauses it covered and the reasoning the model returned.
export class AiBatch {
  label: string = '';
  reasoning: string = '';
  seconds: number = 0;
}

export class ReviewProgress {
  stage: string;
  done: number;
  total: number;

  constructor(stage: string, done: number, total: number) {
    this.stage = stage;
    this.done = done;
    this.total = total;
  }
}

class StoredReports {
  reports: ContractReport[] = [];
}

// Contract review on the phone: structure audit and rules run locally; the
// optional AI pass sends masked clause text to the user's own model.
export class ContractReviewService {
  private static writing: Promise<void> = Promise.resolve();

  static async pick(context: common.UIAbilityContext): Promise<ContractSource> {
    const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
    const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.fileSuffixFilters = ['劳动合同|.docx,.pdf,.txt'];
    const uris: string[] = await documentPicker.select(options);
    if (uris.length === 0) {
      throw new Error('未选择文件');
    }
    const uri: string = uris[0];
    if (uri.toLowerCase().split('?')[0].endsWith('.pdf')) {
      return ContractReviewService.readPdf(context, uri);
    }
    const attachment: FileAttachment = await AttachmentService.read(context, uri, MAX_CONTRACT_CHARS);
    return new ContractSource(attachment.name, attachment.text, false,
      attachment.truncated ? `合同超过 ${MAX_CONTRACT_CHARS} 字，只审查了前面部分` : '');
  }

  // Text layer first; pages without one are rendered and recognized.
  private static async readPdf(context: common.UIAbilityContext, uri: string): Promise<ContractSource> {
    const name: string = ContractReviewService.fileName(uri);
    const path: string = context.cacheDir + '/contract_' + Date.now().toString() + '.pdf';
    const source: fileIo.File = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    try {
      const stat: fileIo.Stat = await fileIo.stat(source.fd);
      if (stat.size > MAX_PDF_BYTES) {
        throw new Error('PDF 不能超过 20 MB');
      }
      await fileIo.copyFile(source.fd, path);
    } finally {
      await fileIo.close(source);
    }
    const document: pdfService.PdfDocument = new pdfService.PdfDocument();
    try {
      const result: pdfService.ParseResult = document.loadDocument(path);
      if (result !== pdfService.ParseResult.PARSE_SUCCESS) {
        throw new Error(result === pdfService.ParseResult.PARSE_ERROR_PASSWORD ? 'PDF 有密码保护，请先解除密码' : 'PDF 无法打开');
      }
      const pages: string[] = [];
      let scannedPages: number = 0;
      const count: number = document.getPageCount();
      for (let i: number = 0; i < count; i++) {
        const page: pdfService.PdfPage = document.getPage(i);
        let text: string = page.getTextContent().trim();
        if (text.length < SCANNED_PAGE_CHARS) {
          const pixelMap: image.PixelMap = page.getPagePixelMap();
          try {
            text = await EvidencePipeline.recognizePixelMap(pixelMap);
            scannedPages++;
          } finally {
            pixelMap.release();
          }
        }
        pages.push(text);
      }
      const text: string = pages.join('\n').trim();
      if (text.length === 0) {
        throw new Error('没有从 PDF 中读取到文字');
      }
      return new ContractSource(name, text.substring(0, MAX_CONTRACT_CHARS), scannedPages > 0,
        scannedPages > 0 ? `${scannedPages} 页为扫描件，已识别文字` : '');
    } finally {
      document.releaseDocument();
      fileIo.unlink(path).catch(() => {
        // The cache is cleared by the system eventually.
      });
    }
  }

  // Structure audit and rules, on the phone. Fast enough for the UI thread:
  // a contract is a few thousand characters.
  static local(source: ContractSource, facts: FactSheet): ContractReport {
    const audit: StructureAudit = ContractStructure.audit(source.text, source.scanned);
    const rules: RuleResult = ContractRules.run(audit.anchors, source.text, facts);
    const report: ContractReport = new ContractReport();
    report.id = 'CR-' + Date.now().toString() + '-' + util.generateRandomUUID(false).substring(0, 4);
    report.fileName = source.name;
    report.createdAt = Date.now();
    report.text = ContractStructure.normalize(source.text);
    report.scanned = source.scanned;
    report.facts = facts;
    report.terms = rules.terms;
    report.anchors = audit.anchors;
    report.warnings = audit.warnings;
    report.findings = rules.findings;
    return report;
  }

  // AI pass over the clauses in batches, then a whole-contract pass. Failed
  // batches are skipped; the rule findings always stay.
  static async withAi(report: ContractReport, config: ApiConfig, handle: StreamHandle,
    onProgress: (progress: ReviewProgress) => void): Promise<ContractReport> {
    const batches: ClauseAnchor[][] = ContractAi.batches(report.anchors);
    const total: number = batches.length + 1;
    const model: Finding[] = [];
    let failed: number = 0;
    let misplaced: number = 0;
    for (let i: number = 0; i < batches.length && !handle.cancelled; i++) {
      onProgress(new ReviewProgress('AI 逐条审查', i, total));
      const batch: ClauseAnchor[] = batches[i];
      const ids: string[] = batch.map((a: ClauseAnchor) => a.anchorId);
      const laws: ReviewLaw[] = await ContractReviewService.laws(ContractAi.lawQuery(batch));
      const known: Finding[] = report.findings.filter((f: Finding) => ids.includes(f.anchorId));
      let correction: string = '';
      for (let attempt: number = 0; attempt <= MAX_RETRIES && !handle.cancelled; attempt++) {
        const startedAt: number = Date.now();
        const parsed: ParsedBatch | undefined = await ContractReviewService.ask(config, handle,
          ContractAi.reviewPrompt(report.facts, laws, batch, known, correction), ids, laws);
        if (parsed === undefined || !parsed.ok) {
          failed++;
          break;
        }
        const label: string = ContractReviewService.anchorLabel(report, ids[0]) +
          (ids.length > 1 ? '至' + ContractReviewService.anchorLabel(report, ids[ids.length - 1]) : '');
        ContractReviewService.keepBatch(report, parsed, label, startedAt);
        model.push(...parsed.findings);
        if (parsed.misplaced === 0) {
          break;
        }
        misplaced += parsed.misplaced;
        correction = ContractAi.correction(parsed.misplaced);
      }
    }
    if (!handle.cancelled) {
      onProgress(new ReviewProgress('反向推演与漏项检查', batches.length, total));
      const laws: ReviewLaw[] = await ContractReviewService.laws('劳动合同 调岗 解除 规章制度 严重违纪 工资 加班费');
      const startedAt: number = Date.now();
      const parsed: ParsedBatch | undefined = await ContractReviewService.ask(config, handle,
        ContractAi.reversePrompt(report.facts, laws, report.anchors, report.findings),
        report.anchors.map((a: ClauseAnchor) => a.anchorId), laws);
      if (parsed === undefined || !parsed.ok) {
        failed++;
      } else {
        ContractReviewService.keepBatch(report, parsed, '全文反向推演与漏项检查', startedAt);
        model.push(...parsed.findings);
      }
    }
    onProgress(new ReviewProgress('完成', total, total));
    report.findings = ContractAi.merge(report.findings.filter((f: Finding) => f.ruleId !== 'AI'), model);
    report.aiState = handle.cancelled ? AI_PARTIAL : failed === 0 ? AI_DONE : failed >= total ? AI_FAILED : AI_PARTIAL;
    const notes: string[] = [];
    if (handle.cancelled) {
      notes.push('已停止，AI 只审查了部分条款');
    }
    if (failed > 0) {
      notes.push(`${failed} 批 AI 审查未返回可用结果，已跳过`);
    }
    if (misplaced > 0) {
      notes.push(`已剔除 ${misplaced} 条挂错条款的 AI 意见`);
    }
    report.aiNote = notes.join('；');
    return report;
  }

  // Keeps a pass's reasoning, tags its findings with it, and places each
  // finding's quote in the contract text.
  private static keepBatch(report: ContractReport, parsed: ParsedBatch, label: string, startedAt: number): void {
    const batch: AiBatch = new AiBatch();
    batch.label = label;
    batch.reasoning = parsed.reasoning.length > MAX_BATCH_REASONING ?
      parsed.reasoning.substring(0, MAX_BATCH_REASONING) + '…' : parsed.reasoning;
    batch.seconds = Math.round((Date.now() - startedAt) / 1000);
    report.aiBatches.push(batch);
    parsed.findings.forEach((f: Finding) => {
      f.batch = report.aiBatches.length - 1;
      ContractReviewService.placeQuote(report, f);
    });
  }

  // The model was sent masked text, so a quote with a placeholder is not
  // found and the finding marks its whole clause instead.
  private static placeQuote(report: ContractReport, f: Finding): void {
    const anchor: ClauseAnchor | undefined = report.anchors.find((a: ClauseAnchor) => a.anchorId === f.anchorId);
    const quote: string = f.quote.replace(/[…。]+$/, '');
    if (anchor === undefined || quote.length < 2) {
      return;
    }
    const at: number = report.text.indexOf(quote, anchor.start);
    if (at >= 0 && at + quote.length <= anchor.end) {
      f.start = at;
      f.end = at + quote.length;
    }
  }

  private static async ask(config: ApiConfig, handle: StreamHandle, prompt: string, ids: string[],
    laws: ReviewLaw[]): Promise<ParsedBatch | undefined> {
    const messages: ChatMessage[] = [
      new ChatMessage(ChatRole.SYSTEM, ContractAi.systemPrompt()),
      new ChatMessage(ChatRole.USER, prompt)
    ];
    try {
      // Streaming keeps slow reasoning models from hitting the read timeout.
      const result: StreamResult = await AiApiClient.stream(config, messages, () => {
      }, handle, TASK_STRUCTURED);
      const parsed: ParsedBatch = ContractAi.parse(result.answer, ids, laws);
      parsed.reasoning = result.reasoning;
      return parsed;
    } catch (error) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'AI batch failed: %{public}s',
        error instanceof Error ? error.message : 'unknown');
      if (error instanceof Error && /API|Key|密钥|401|403|余额|配置/.test(error.message)) {
        throw error;
      }
      return undefined;
    }
  }

  private static async laws(query: string): Promise<ReviewLaw[]> {
    if (!KnowledgeService.isReady()) {
      return [];
    }
    try {
      const result: KnowledgeResult = await KnowledgeService.search(query, 6);
      return result.citations.map((c: LawCitation) => new ReviewLaw(c.id, c.title, c.article, c.excerpt));
    } catch (error) {
      return [];
    }
  }

  // Original text of the articles a report cites, keyed by reference label.
  static async articles(findings: Finding[]): Promise<Map<string, LawCitation>> {
    const keys: string[] = [];
    findings.forEach((f: Finding) => f.lawRefs.forEach((ref: string) => {
      const at: LawLocation | undefined = ContractReviewService.locate(ref);
      if (at !== undefined && at.article.length > 0) {
        const key: string = at.title + '\u0000' + at.article + '\u0000' + ref;
        if (!keys.includes(key)) {
          keys.push(key);
        }
      }
    }));
    const out: Map<string, LawCitation> = new Map<string, LawCitation>();
    try {
      (await KnowledgeService.articles(keys)).forEach((c: LawCitation) => out.set(c.id, c));
    } catch (error) {
      // Without the index the references stay plain text.
    }
    return out;
  }

  // Rule references use short names; AI references already carry the index
  // title, as 《title》article.
  static locate(ref: string): LawLocation | undefined {
    const short: LawLocation | undefined = ContractLaws.resolve(ref);
    if (short !== undefined) {
      return short;
    }
    const m: RegExpExecArray | null = /《([^》]+)》\s*(.*)$/.exec(ref);
    return m !== null ? new LawLocation(m[1], m[2].trim(), ref) : undefined;
  }

  static anchorLabel(report: ContractReport, anchorId: string): string {
    if (anchorId === WHOLE_CONTRACT) {
      return '全文';
    }
    const anchor: ClauseAnchor | undefined = report.anchors.find((a: ClauseAnchor) => a.anchorId === anchorId);
    return anchor !== undefined && anchor.rawNo.length > 0 ? anchor.rawNo : anchorId;
  }

  static async load(context: common.Context): Promise<ContractReport[]> {
    const path: string = context.filesDir + '/' + STORE_FILE;
    try {
      if (!fileIo.accessSync(path)) {
        return [];
      }
      const stored: StoredReports = JSON.parse(fileIo.readTextSync(path)) as StoredReports;
      const reports: ContractReport[] = Array.isArray(stored.reports) ? stored.reports : [];
      reports.forEach((report: ContractReport) => ContractReviewService.fillDefaults(report));
      return reports;
    } catch (error) {
      return [];
    }
  }

  // Reports saved before highlighting and AI reasoning lack those fields; give
  // them the "unknown" values, so their findings mark the whole clause.
  private static fillDefaults(report: ContractReport): void {
    if (!Array.isArray(report.aiBatches)) {
      report.aiBatches = [];
    }
    (Array.isArray(report.findings) ? report.findings : []).forEach((f: Finding) => {
      if (typeof f.start !== 'number' || typeof f.end !== 'number') {
        f.start = -1;
        f.end = -1;
      }
      if (!Array.isArray(f.trace)) {
        f.trace = [];
      }
      if (typeof f.quote !== 'string') {
        f.quote = '';
      }
      if (typeof f.batch !== 'number') {
        f.batch = -1;
      }
    });
  }

  // Newest first; keeps the latest MAX_REPORTS. Reports stay on the phone.
  static save(context: common.Context, reports: ContractReport[]): Promise<void> {
    const stored: StoredReports = new StoredReports();
    stored.reports = reports.slice(0, MAX_REPORTS);
    const content: string = JSON.stringify(stored);
    const path: string = context.filesDir + '/' + STORE_FILE;
    ContractReviewService.writing = ContractReviewService.writing.catch(() => {
    }).then(async () => {
      const temp: string = path + '.tmp';
      const file: fileIo.File = await fileIo.open(temp, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY |
        fileIo.OpenMode.TRUNC);
      try {
        await fileIo.write(file.fd, content);
      } finally {
        await fileIo.close(file);
      }
      await fileIo.rename(temp, path);
    });
    return ContractReviewService.writing;
  }

  private static fileName(uri: string): string {
    const clean: string = uri.split('?')[0];
    const encoded: string = clean.substring(clean.lastIndexOf('/') + 1);
    try {
      return decodeURIComponent(encoded);
    } catch (error) {
      return encoded;
    }
  }
}
