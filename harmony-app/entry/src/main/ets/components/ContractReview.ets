import { common } from '@kit.AbilityKit';
import { LengthMetrics } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { ContractAi } from '../contract/ContractAi';
import { ContractDocument, DocLine, DocSegment } from '../contract/ContractDocument';
import { ContractLaws } from '../contract/ContractLaws';
import { ContractPrivacy } from '../contract/ContractPrivacy';
import { ContractRules } from '../contract/ContractRules';
import { SAMPLE_CONTRACT_CITY, SAMPLE_CONTRACT_NAME, SAMPLE_CONTRACT_TEXT } from '../contract/SampleContract';
import {
  BARGAIN_MUST,
  BARGAIN_SHOULD,
  ClauseAnchor,
  FACT_NO,
  FACT_UNKNOWN,
  FACT_YES,
  FactSheet,
  Finding,
  NATURE_INVALID,
  SEVERITIES,
  SEVERITY_HIGH,
  SEVERITY_MEDIUM,
  SEVERITY_REDLINE,
  StructureWarning,
  TERM_OPEN,
  TERM_TASK,
  TERM_UNKNOWN,
  WHOLE_CONTRACT
} from '../contract/ContractTypes';
import { ApiConfig, LawCitation } from '../models/AppModels';
import { EvidenceItem } from '../models/Evidence';
import { AiApiClient, StreamHandle } from '../services/AiApiClient';
import {
  AI_DONE,
  AI_FAILED,
  AI_NONE,
  AI_PARTIAL,
  AiBatch,
  ContractReport,
  ContractReviewService,
  ContractSource,
  ReviewProgress
} from '../services/ContractReviewService';
import { CAT_CONTRACT } from '../services/EvidenceExtractor';
import { EvidenceStore } from '../services/EvidenceStore';
import { ThemeColors } from '../theme/Theme';
import { AskFab, READING_FAB_BOTTOM } from './chat/ChatViews';

export const CONTRACT_MODE_HOME: number = 0;
export const CONTRACT_MODE_FACTS: number = 1;
export const CONTRACT_MODE_REPORT: number = 2;
export const CONTRACT_MODE_CLAUSE: number = 3;

const DISCLAIMER: string = '本结果为规则审查与 AI 辅助审查，用于提示合同风险，不构成法律意见。各地裁审口径不一，' +
  '涉及重大权益时请咨询律师或当地劳动仲裁部门。';
const SHEET_NONE: number = 0;
const SHEET_PREVIEW: number = 1;
const SHEET_LAW: number = 2;
const SHEET_FINDING: number = 3;
const VIEW_TEXT: number = 0;
const VIEW_LIST: number = 1;
const DOC_SCROLL_ID: string = 'contractDoc';
const CORPUS_NOTE: string = '资料为机械收录，尚未完成全面法律效力审查，请以官方最新文本为准。';

interface PillParams {
  label: string;
  color: string;
  bg: string;
}

interface SectionParams {
  title: string;
  body: string;
}

interface ChoiceParams {
  label: string;
  value: string;
  current: string;
}

// 合同体检: imports a labor contract, reviews it with on-device rules and,
// optionally, the user's own model, and shows the result clause by clause.
@Component
export struct ContractReview {
  @Prop cx: ThemeColors;
  @Prop isDark: boolean = false;
  @Link @Watch('modeChanged') mode: number;
  // Shown as the 合同 section rather than as a cover: the home page has no
  // header of its own, and content leaves room for the floating tab bar.
  @Prop embedded: boolean = false;
  @Prop bottomInset: number = 0;
  // Changes when local records are cleared elsewhere; the reports reload.
  @Prop @Watch('reload') dataVersion: number = 0;
  onCountChange: (count: number) => void = (count: number) => {
  };
  // Reading mode: true while the report scrolls down (composer folded), so
  // the page hides the tab bar too; false when it unfolds or the report closes.
  onReadingChange: (reading: boolean) => void = (reading: boolean) => {
  };
  @Prop baseUrl: string = '';
  @Prop modelName: string = '';
  @Prop apiKey: string = '';
  @Prop defaultCity: string = '';
  onClose: () => void = () => {
  };
  // Asks about a clause (or the whole report) in 案件 with the findings
  // attached, and the user's question when they typed one.
  onAsk: (title: string, body: string, question: string) => void = (title: string, body: string,
    question: string) => {
  };
  @State reports: ContractReport[] = [];
  @State reportId: string = '';
  @State anchorId: string = '';
  @State source: ContractSource | undefined = undefined;
  @State city: string = '';
  @State jobTitle: string = '';
  @State confidential: string = FACT_UNKNOWN;
  @State signed: string = FACT_UNKNOWN;
  @State termText: string = '';
  @State probationText: string = '';
  // What the contract text gave for the two fields; left unchanged, they are
  // read from the text again so the reasoning says where they came from.
  private detectedTerm: string = '';
  private detectedProbation: string = '';
  @State useAi: boolean = true;
  @State busy: boolean = false;
  @State progress: string = '';
  @State notice: string = '';
  @State contractPhotos: number = 0;
  // One sheet for both the send preview and law text: a component holds one
  // bound sheet.
  @State sheet: number = SHEET_NONE;
  @State law: LawCitation | undefined = undefined;
  @State lawRef: string = '';
  @State articles: LawCitation[] = [];
  @State showWarnings: boolean = false;
  @State question: string = '';
  // The annotated contract text and its navigation.
  @State reportView: number = VIEW_TEXT;
  @State docLines: DocLine[] = [];
  @State wholeFindings: number[] = [];
  @State navOrder: number[] = [];
  @State navPos: number = -1;
  @State severityFilter: string = '';
  @State docViewport: number = 0;
  @State showThinking: boolean = false;
  @State lawFromFinding: boolean = false;
  // While reading, the composer folds into a small 问 AI button.
  @State askCollapsed: boolean = false;
  private docScroller: Scroller = new Scroller();
  private downScroll: number = 0;
  private navScrollUntil: number = 0;
  private askController: TextAreaController = new TextAreaController();
  private handle: StreamHandle | undefined = undefined;

  aboutToAppear(): void {
    this.city = this.defaultCity;
    this.reload();
    EvidenceStore.load(this.context()).then((items: EvidenceItem[]) => {
      this.contractPhotos = items.filter((item: EvidenceItem) => item.category === CAT_CONTRACT &&
        item.text.length > 0).length;
    }).catch(() => {
      this.contractPhotos = 0;
    });
  }

  reload(): void {
    this.mode = CONTRACT_MODE_HOME;
    this.reportId = '';
    ContractReviewService.load(this.context()).then((reports: ContractReport[]) => {
      this.reports = reports;
      this.onCountChange(reports.length);
    });
  }

  aboutToDisappear(): void {
    this.handle?.cancel();
    this.onReadingChange(false);
  }

  modeChanged(): void {
    if (this.mode !== CONTRACT_MODE_REPORT) {
      this.setFolded(false);
    }
  }

  private setFolded(folded: boolean): void {
    if (folded === this.askCollapsed) {
      return;
    }
    if (folded) {
      this.askController.stopEditing();
    }
    this.askCollapsed = folded;
    this.onReadingChange(folded);
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private config(): ApiConfig {
    return new ApiConfig(this.baseUrl, this.modelName, this.apiKey);
  }

  private aiReady(): boolean {
    return AiApiClient.validateConfig(this.config()).length === 0;
  }

  private report(): ContractReport | undefined {
    return this.reports.find((r: ContractReport) => r.id === this.reportId);
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message, duration: 1800 });
  }

  // Back from a clause goes to the report, from the report or facts to home.
  goBack(): void {
    if (this.busy) {
      return;
    }
    if (this.mode === CONTRACT_MODE_CLAUSE) {
      this.mode = CONTRACT_MODE_REPORT;
    } else if (this.mode === CONTRACT_MODE_HOME) {
      this.onClose();
    } else {
      this.mode = CONTRACT_MODE_HOME;
    }
  }

  private async pickFile(): Promise<void> {
    try {
      this.busy = true;
      this.progress = '正在读取合同…';
      this.startFacts(await ContractReviewService.pick(this.context()));
    } catch (error) {
      const message: string = error instanceof Error ? error.message : '读取失败';
      if (message !== '未选择文件') {
        this.notice = message;
      }
    } finally {
      this.busy = false;
      this.progress = '';
    }
  }

  // Photos in 证据库 classified as 合同, in import order, as one contract.
  private async fromEvidence(): Promise<void> {
    const items: EvidenceItem[] = (await EvidenceStore.load(this.context()))
      .filter((item: EvidenceItem) => item.category === CAT_CONTRACT && item.text.length > 0)
      .sort((a: EvidenceItem, b: EvidenceItem) => a.createdAt - b.createdAt);
    if (items.length === 0) {
      this.notice = '证据库里还没有识别为「合同」的照片';
      return;
    }
    const text: string = items.map((item: EvidenceItem) => item.text).join('\n');
    this.startFacts(new ContractSource(items.length > 1 ? `合同照片 ${items.length} 张` : items[0].title, text, true,
      `来自证据库的 ${items.length} 张合同照片`));
  }

  // The built-in fictional contract, for trying the review without a file.
  private trySample(): void {
    this.startFacts(new ContractSource(SAMPLE_CONTRACT_NAME, SAMPLE_CONTRACT_TEXT, false,
      '这是内置的虚构示例合同，用来体验审查流程'));
    this.city = SAMPLE_CONTRACT_CITY;
  }

  private startFacts(source: ContractSource): void {
    this.source = source;
    this.notice = source.note;
    const terms = ContractRules.extractTerms(ContractReviewService.local(source, new FactSheet()).text);
    this.termText = terms.termMonths === TERM_UNKNOWN ? '' : terms.termMonths === TERM_OPEN ? '无固定期限' :
      terms.termMonths === TERM_TASK ? '以完成工作任务为期限' : terms.termMonths.toString();
    this.probationText = terms.probationDays > 0 ?
      (terms.probationDays % 30 === 0 ? (terms.probationDays / 30).toString() : (terms.probationDays / 30).toFixed(1)) : '';
    this.detectedTerm = this.termText;
    this.detectedProbation = this.probationText;
    this.useAi = this.aiReady();
    this.mode = CONTRACT_MODE_FACTS;
  }

  private facts(): FactSheet {
    const facts: FactSheet = new FactSheet();
    facts.city = this.city.trim();
    facts.position = this.jobTitle.trim();
    facts.confidential = this.confidential;
    facts.signed = this.signed;
    // A field left as detected stays unset: the rules read it from the text.
    if (this.termText !== this.detectedTerm) {
      const term: number = Number(this.termText.trim());
      facts.termMonths = this.termText.includes('无固定') ? TERM_OPEN : this.termText.includes('任务') ? TERM_TASK :
        this.termText.trim().length > 0 && Number.isFinite(term) && term > 0 ? term : TERM_UNKNOWN;
    }
    if (this.probationText !== this.detectedProbation) {
      const probation: number = Number(this.probationText.trim());
      facts.probationMonths = this.probationText.trim().length > 0 && Number.isFinite(probation) && probation >= 0 ?
        probation : -1;
    }
    return facts;
  }

  private async start(): Promise<void> {
    if (this.source === undefined || this.busy) {
      return;
    }
    const report: ContractReport = ContractReviewService.local(this.source, this.facts());
    this.busy = true;
    this.progress = '本地规则审查完成';
    try {
      if (this.useAi && this.aiReady()) {
        this.handle = new StreamHandle();
        await ContractReviewService.withAi(report, this.config(), this.handle, (p: ReviewProgress) => {
          this.progress = p.stage + (p.total > 0 ? ` ${Math.min(p.done + 1, p.total)}/${p.total}` : '');
        });
      }
    } catch (error) {
      report.aiState = AI_FAILED;
      report.aiNote = error instanceof Error ? error.message : 'AI 审查失败';
    } finally {
      this.handle = undefined;
      this.busy = false;
      this.progress = '';
    }
    this.reports = [report].concat(this.reports.filter((r: ContractReport) => r.id !== report.id));
    this.onCountChange(this.reports.length);
    ContractReviewService.save(this.context(), this.reports).catch(() => {
      this.toast('报告保存失败');
    });
    this.source = undefined;
    this.openReport(report.id);
  }

  private openReport(id: string): void {
    this.reportId = id;
    this.notice = '';
    this.reportView = VIEW_TEXT;
    this.severityFilter = '';
    this.navPos = -1;
    this.setFolded(false);
    this.articles = [];
    const report: ContractReport | undefined = this.report();
    if (report !== undefined) {
      this.docLines = ContractDocument.lines(report.text, report.anchors, report.findings);
      this.wholeFindings = ContractDocument.wholeContract(report.findings);
      this.navOrder = ContractDocument.order(report.findings, report.anchors);
    }
    this.mode = CONTRACT_MODE_REPORT;
    this.modeChanged();
    if (report !== undefined) {
      ContractReviewService.articles(report.findings).then((map: Map<string, LawCitation>) => {
        const list: LawCitation[] = [];
        map.forEach((c: LawCitation) => list.push(c));
        this.articles = list;
      });
    }
  }

  private deleteReport(id: string): void {
    this.reports = this.reports.filter((r: ContractReport) => r.id !== id);
    this.onCountChange(this.reports.length);
    ContractReviewService.save(this.context(), this.reports).catch(() => {
    });
  }

  private openLaw(ref: string): void {
    this.lawRef = ref;
    this.law = this.articles.find((c: LawCitation) => c.id === ref);
    this.lawFromFinding = this.sheet === SHEET_FINDING;
    this.sheet = SHEET_LAW;
  }

  // Findings in reading order, limited to the severity filter.
  private visibleOrder(): number[] {
    const report: ContractReport | undefined = this.report();
    if (report === undefined) {
      return [];
    }
    return this.navOrder.filter((k: number) =>
      this.severityFilter.length === 0 || report.findings[k].severity === this.severityFilter);
  }

  private currentFinding(): Finding | undefined {
    const report: ContractReport | undefined = this.report();
    const order: number[] = this.visibleOrder();
    return report !== undefined && this.navPos >= 0 && this.navPos < order.length ?
      report.findings[order[this.navPos]] : undefined;
  }

  // Opens the finding sheet on a finding (an index into report.findings) and
  // scrolls the text to it.
  private openFinding(k: number): void {
    let order: number[] = this.visibleOrder();
    if (!order.includes(k)) {
      this.severityFilter = '';
      order = this.visibleOrder();
    }
    this.navPos = order.indexOf(k);
    this.showThinking = false;
    this.sheet = SHEET_FINDING;
    this.scrollToFinding(k);
  }

  // The finding sheet's 上一处 / 下一处 move the sheet along; the navigator
  // under the text only scrolls to the next one and marks it.
  // Back at the top unfolds the composer, unless the navigator scrolled there:
  // stepping to a finding near the top should keep it in reach.
  private unfoldAtTop(): void {
    if (Date.now() >= this.navScrollUntil) {
      this.setFolded(false);
    }
  }

  private step(delta: number, inSheet: boolean = true): void {
    const order: number[] = this.visibleOrder();
    if (order.length === 0) {
      return;
    }
    const next: number = this.navPos < 0 ? 0 : (this.navPos + delta + order.length) % order.length;
    if (inSheet) {
      this.openFinding(order[next]);
    } else {
      this.navPos = next;
      this.navScrollUntil = Date.now() + 800;
      this.scrollToFinding(order[next]);
    }
  }

  private scrollToFinding(k: number): void {
    const report: ContractReport | undefined = this.report();
    if (report === undefined || this.reportView !== VIEW_TEXT) {
      return;
    }
    const f: Finding = report.findings[k];
    const anchor: ClauseAnchor | undefined = report.anchors.find((a: ClauseAnchor) => a.anchorId === f.anchorId);
    const pos: number = f.start >= 0 ? f.start : (anchor !== undefined ? anchor.start : -1);
    if (pos < 0) {
      this.docScroller.scrollEdge(Edge.Top);
      return;
    }
    let line: number = 0;
    this.docLines.forEach((l: DocLine) => {
      if (l.start <= pos) {
        line = l.index;
      }
    });
    setTimeout(() => {
      try {
        const utils = this.getUIContext().getComponentUtils();
        const top: number = utils.getRectangleById(DOC_SCROLL_ID).windowOffset.y;
        const at: number = utils.getRectangleById('docline-' + line.toString()).windowOffset.y;
        const offset: number = this.docScroller.currentOffset().yOffset + this.getUIContext().px2vp(at - top) - 60;
        this.docScroller.scrollTo({ xOffset: 0, yOffset: Math.max(0, offset), animation: { duration: 260 } });
      } catch (error) {
        // The line may not be laid out yet; the sheet still shows the finding.
      }
    }, 60);
  }

  private highlightBg(seg: DocSegment): string {
    const report: ContractReport | undefined = this.report();
    if (seg.finding < 0 || report === undefined ||
      (this.severityFilter.length > 0 && seg.severity !== this.severityFilter)) {
      return '#00000000';
    }
    const current: Finding | undefined = this.currentFinding();
    const selected: boolean = current !== undefined && current === report.findings[seg.finding];
    if (seg.severity === SEVERITY_REDLINE) {
      return selected ? '#66D85A30' : (this.isDark ? '#40D85A30' : '#2ED85A30');
    }
    if (seg.severity === SEVERITY_HIGH || seg.severity === SEVERITY_MEDIUM) {
      return selected ? '#66EF9F27' : (this.isDark ? '#40EF9F27' : '#38EF9F27');
    }
    return selected ? '#4D888780' : '#26888780';
  }

  private batchOf(f: Finding): AiBatch | undefined {
    const report: ContractReport | undefined = this.report();
    return report !== undefined && f.batch >= 0 && f.batch < report.aiBatches.length ?
      report.aiBatches[f.batch] : undefined;
  }

  private copy(text: string, message: string): void {
    try {
      pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text))
        .then(() => this.toast(message)).catch(() => this.toast('复制失败，请重试'));
    } catch (error) {
      this.toast('复制失败，请重试');
    }
  }

  private ask(report: ContractReport, anchor: ClauseAnchor | undefined, findings: Finding[]): void {
    const clause: string = anchor !== undefined ? ContractPrivacy.mask(anchor.text).text :
      '（整份合同：' + report.fileName + '）';
    const lines: string[] = findings.map((f: Finding) =>
      `- ${f.topic}（${f.severity}·${f.nature}）：${f.reason}${f.lawRefs.length > 0 ? ' 依据：' + f.lawRefs.join('、') : ''}`);
    this.onAsk(`合同审查 · ${anchor !== undefined ? ContractReviewService.anchorLabel(report, anchor.anchorId) : report.fileName}`,
      `合同条款原文：\n${clause}\n\n审查发现：\n${lines.join('\n')}`, this.question);
    this.question = '';
  }

  // Sends from the pinned composer: about the open clause, or the whole report.
  private sendQuestion(): void {
    const report: ContractReport | undefined = this.report();
    if (report === undefined) {
      return;
    }
    this.askController.stopEditing();
    if (this.mode === CONTRACT_MODE_CLAUSE) {
      this.ask(report, report.anchors.find((a: ClauseAnchor) => a.anchorId === this.anchorId),
        report.findings.filter((f: Finding) => f.anchorId === this.anchorId));
    } else {
      this.ask(report, undefined, report.findings);
    }
  }

  // How a finding matters to the worker: before signing it is about what to
  // ask to change, after signing about what is void anyway.
  private stake(f: Finding, signed: string): string {
    if (f.nature === NATURE_INVALID) {
      return signed === FACT_YES ? '签了也无效' : signed === FACT_NO ? '签前要求删除' : '无效条款';
    }
    if (f.bargain === BARGAIN_MUST) {
      return signed === FACT_YES ? '注意保留证据' : signed === FACT_NO ? '签前要求修改' : '需要修改';
    }
    if (f.bargain === BARGAIN_SHOULD) {
      return signed === FACT_YES ? '留意' : '可以协商';
    }
    return '了解即可';
  }

  // 《中华人民共和国劳动合同法（2012修正）》第八十五条 → 《劳动合同法》第八十五条.
  private refLabel(ref: string): string {
    return ref.replace('中华人民共和国', '').replace(/（\d{4}修正）|（\d{4}修订）/, '');
  }

  private severityColor(severity: string): string {
    if (severity === SEVERITY_REDLINE) {
      return this.cx.danger;
    }
    if (severity === SEVERITY_HIGH) {
      return this.isDark ? '#F0A35A' : '#B8641C';
    }
    if (severity === SEVERITY_MEDIUM) {
      return this.cx.warn;
    }
    return this.cx.muted;
  }

  private severityBg(severity: string): string {
    if (severity === SEVERITY_REDLINE) {
      return this.cx.dangerBg;
    }
    if (severity === SEVERITY_HIGH || severity === SEVERITY_MEDIUM) {
      return this.isDark ? '#2A2416' : '#F8EBCF';
    }
    return this.cx.surface2;
  }

  private count(report: ContractReport, severity: string): number {
    return report.findings.filter((f: Finding) => f.severity === severity).length;
  }

  // Facts the findings wait on, rule facts first; long model phrasings are
  // left to the clause pages.
  private pendingFacts(report: ContractReport): string {
    const out: string[] = [];
    const ordered: Finding[] = report.findings.filter((f: Finding) => f.ruleId !== 'AI')
      .concat(report.findings.filter((f: Finding) => f.ruleId === 'AI'));
    ordered.forEach((f: Finding) => f.pendingFacts.forEach((p: string) => {
      if (!out.includes(p) && p.length <= 12) {
        out.push(p);
      }
    }));
    return out.length <= 4 ? out.join('、') : out.slice(0, 4).join('、') + ` 等 ${out.length} 项`;
  }

  private aiLabel(report: ContractReport): string {
    if (report.aiState === AI_DONE) {
      return 'AI 审查完成';
    }
    if (report.aiState === AI_PARTIAL) {
      return 'AI 部分完成';
    }
    if (report.aiState === AI_FAILED) {
      return 'AI 审查失败';
    }
    return '仅本地规则';
  }

  private preview(): string {
    if (this.source === undefined) {
      return '';
    }
    const report: ContractReport = ContractReviewService.local(this.source, this.facts());
    const batches: ClauseAnchor[][] = ContractAi.batches(report.anchors);
    if (batches.length === 0) {
      return '（没有识别到条款）';
    }
    return ContractAi.reviewPrompt(report.facts, [], batches[0], [], '').split('<clauses>')[1]?.replace('</clauses>', '')
      .trim() ?? '';
  }

  private maskSummary(): string {
    if (this.source === undefined) {
      return '';
    }
    const parts: string[] = [];
    ContractPrivacy.mask(this.source.text).counts.forEach((n: number, key: string) => {
      parts.push(`${key} ${n} 处`);
    });
    return parts.length > 0 ? '已替换：' + parts.join('、') : '没有发现需要替换的个人信息';
  }

  @Builder
  private Header() {
    Row({ space: 12 }) {
      Text('‹')
        .fontSize(24)
        .fontColor(this.cx.gold)
        .textAlign(TextAlign.Center)
        .width(40)
        .height(40)
        .backgroundColor(this.cx.tint)
        .borderRadius(20)
        .accessibilityText('返回')
        .onClick(() => {
          this.goBack();
        })
      Column({ space: 3 }) {
        Text(this.mode === CONTRACT_MODE_HOME ? '合同体检' : this.mode === CONTRACT_MODE_FACTS ? '补充几项事实' :
          this.mode === CONTRACT_MODE_CLAUSE && this.report() !== undefined ?
          ContractReviewService.anchorLabel(this.report()!, this.anchorId) : (this.report()?.fileName ?? '审查结果'))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.cx.text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.mode === CONTRACT_MODE_HOME ? '规则审查在手机上完成 · 报告仅保存在本机' :
          this.mode === CONTRACT_MODE_FACTS ? '缺了也能审，相关结论会标「待确认」' : '条款级审查 · 风险挂在具体条款上')
          .fontSize(11.5)
          .fontColor(this.cx.muted)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: this.embedded ? 4 : 52, bottom: 12 })
  }

  @Builder
  private Card(title: string, sub: string, res: Resource, action: () => void) {
    Row({ space: 11 }) {
      Column() {
        Image(res).width(18).height(18).fillColor(this.cx.gold)
      }
      .width(38)
      .height(38)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(this.cx.tint)
      .borderRadius(12)
      Column({ space: 3 }) {
        Text(title).fontSize(14).fontWeight(FontWeight.Bold).fontColor(this.cx.text)
        Text(sub).fontSize(11).fontColor(this.cx.muted)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text('›').fontSize(22).fontColor(this.cx.goldDeep)
    }
    .width('100%')
    .padding(13)
    .backgroundColor(this.cx.surface)
    .borderRadius(16)
    .border({ width: 1, color: this.cx.line })
    .enabled(!this.busy)
    .onClick(() => {
      action();
    })
  }

  @Builder
  private Home() {
    Scroll() {
      Column({ space: 12 }) {
        this.Card('选择合同文件', '支持 DOCX、PDF（含扫描件）、TXT', $r('app.media.ic_doc'), () => {
          this.pickFile();
        })
        if (this.contractPhotos > 0) {
          this.Card('用证据库里的合同照片', `${this.contractPhotos} 张已识别为「合同」的照片`, $r('app.media.ic_photo'), () => {
            this.fromEvidence();
          })
        }
        this.Card('用示例合同试试', '一份有典型问题的虚构合同，看看审查结果', $r('app.media.ic_shield'), () => {
          this.trySample();
        })
        Text('规则审查完全在手机上进行。开启 AI 深度审查时，只发送条款文字，姓名、身份证号、手机号、住址等会先替换成占位符。')
          .fontSize(11)
          .lineHeight(17)
          .fontColor(this.cx.muted)
          .width('100%')
        if (this.reports.length > 0) {
          Text('审查记录')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.cx.text)
            .width('100%')
            .margin({ top: 6 })
          ForEach(this.reports, (report: ContractReport) => {
            Row({ space: 10 }) {
              Column({ space: 4 }) {
                Text(report.fileName)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.cx.text)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(`${new Date(report.createdAt).toLocaleDateString()} · 红线 ${this.count(report, SEVERITY_REDLINE)} · ` +
                  `共 ${report.findings.length} 处 · ${this.aiLabel(report)}`)
                  .fontSize(11)
                  .fontColor(this.cx.muted)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Text('删除')
                .fontSize(11.5)
                .fontColor(this.cx.faint)
                .padding(6)
                .onClick(() => {
                  this.deleteReport(report.id);
                })
            }
            .width('100%')
            .padding(12)
            .backgroundColor(this.cx.surface)
            .borderRadius(14)
            .border({ width: 1, color: this.cx.line })
            .onClick(() => {
              this.openReport(report.id);
            })
          }, (report: ContractReport) => report.id)
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: this.embedded ? 12 : 0, bottom: 40 + this.bottomInset })
    }
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .layoutWeight(1)
  }

  @Builder
  private Choice(p: ChoiceParams, onPick: (value: string) => void) {
    Text(p.label)
      .fontSize(12)
      .fontColor(p.current === p.value ? this.cx.onBrand : this.cx.text)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .backgroundColor(p.current === p.value ? this.cx.brand : this.cx.surface2)
      .borderRadius(14)
      .onClick(() => {
        onPick(p.value);
      })
  }

  @Builder
  private Field(label: string, hint: string, value: string, onChange: (value: string) => void) {
    Column({ space: 5 }) {
      Text(label).fontSize(12).fontColor(this.cx.muted).width('100%')
      TextInput({ text: value, placeholder: hint })
        .fontSize(14)
        .fontColor(this.cx.text)
        .placeholderColor(this.cx.placeholder)
        .backgroundColor(this.cx.inputBg)
        .borderRadius(10)
        .height(40)
        .onChange((v: string) => {
          onChange(v);
        })
    }
    .width('100%')
  }

  @Builder
  private Facts() {
    Scroll() {
      Column({ space: 12 }) {
        if (this.source !== undefined) {
          Column({ space: 4 }) {
            Text(this.source.name)
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.cx.text)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
            Text(`${this.source.text.length} 字${this.source.scanned ? ' · 文字识别所得，可能有识别错误' : ''}`)
              .fontSize(11)
              .fontColor(this.cx.muted)
              .width('100%')
          }
          .padding(13)
          .backgroundColor(this.cx.surface)
          .borderRadius(16)
          .border({ width: 1, color: this.cx.line })
        }
        Column({ space: 12 }) {
          Column({ space: 6 }) {
            Text('合同签了吗').fontSize(12).fontColor(this.cx.muted).width('100%')
            Row({ space: 8 }) {
              this.Choice({ label: '还没签', value: FACT_NO, current: this.signed }, (v: string) => {
                this.signed = v;
              })
              this.Choice({ label: '已经签了', value: FACT_YES, current: this.signed }, (v: string) => {
                this.signed = v;
              })
              this.Choice({ label: '不确定', value: FACT_UNKNOWN, current: this.signed }, (v: string) => {
                this.signed = v;
              })
            }
            .width('100%')
          }
          this.Field('工作城市', '如：深圳', this.city, (v: string) => {
            this.city = v;
          })
          this.Field('岗位', '如：销售专员', this.jobTitle, (v: string) => {
            this.jobTitle = v;
          })
          Column({ space: 6 }) {
            Text('是否接触商业秘密').fontSize(12).fontColor(this.cx.muted).width('100%')
            Row({ space: 8 }) {
              this.Choice({ label: '是', value: FACT_YES, current: this.confidential }, (v: string) => {
                this.confidential = v;
              })
              this.Choice({ label: '否', value: FACT_NO, current: this.confidential }, (v: string) => {
                this.confidential = v;
              })
              this.Choice({ label: '不确定', value: FACT_UNKNOWN, current: this.confidential }, (v: string) => {
                this.confidential = v;
              })
            }
            .width('100%')
          }
          Row({ space: 10 }) {
            Column() {
              this.Field('合同期限（月）', '自动识别', this.termText, (v: string) => {
                this.termText = v;
              })
            }
            .layoutWeight(1)
            Column() {
              this.Field('试用期（月）', '自动识别', this.probationText, (v: string) => {
                this.probationText = v;
              })
            }
            .layoutWeight(1)
          }
          .width('100%')
          Text('期限和试用期已从合同正文识别，不对可以直接改。')
            .fontSize(10.5)
            .fontColor(this.cx.faint)
            .width('100%')
        }
        .padding(13)
        .backgroundColor(this.cx.surface)
        .borderRadius(16)
        .border({ width: 1, color: this.cx.line })

        Column({ space: 8 }) {
          Row() {
            Column({ space: 3 }) {
              Text('AI 深度审查').fontSize(14).fontWeight(FontWeight.Bold).fontColor(this.cx.text)
              Text(this.aiReady() ? '用你配置的模型逐条审查并做反向推演' : '未配置模型 API，只做本地规则审查')
                .fontSize(11)
                .fontColor(this.cx.muted)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.useAi && this.aiReady() })
              .enabled(this.aiReady())
              .selectedColor(this.cx.gold)
              .onChange((on: boolean) => {
                this.useAi = on;
              })
          }
          .width('100%')
          if (this.useAi && this.aiReady()) {
            Text(this.maskSummary())
              .fontSize(11)
              .fontColor(this.cx.ok)
              .width('100%')
            Text('查看将发送的内容 ›')
              .fontSize(12)
              .fontColor(this.cx.brand)
              .onClick(() => {
                this.sheet = SHEET_PREVIEW;
              })
          }
        }
        .padding(13)
        .backgroundColor(this.cx.surface)
        .borderRadius(16)
        .border({ width: 1, color: this.cx.line })
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 120 + this.bottomInset })
    }
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .layoutWeight(1)
  }

  @Builder
  // Object parameters are passed by reference, so a pill or section whose
  // values change (the finding sheet's 上一处 / 下一处) redraws.
  private Pill(p: PillParams) {
    Text(p.label)
      .fontSize(10)
      .fontWeight(FontWeight.Medium)
      .fontColor(p.color)
      .padding({ left: 7, right: 7, top: 2, bottom: 2 })
      .backgroundColor(p.bg)
      .borderRadius(8)
  }

  // A finding in the overview, laid flat on the page like a 普法 answer.
  @Builder
  private FindingRow(report: ContractReport, f: Finding) {
    Column({ space: 6 }) {
      Row({ space: 6 }) {
        Text(ContractReviewService.anchorLabel(report, f.anchorId) + ' · ' + f.topic)
          .fontSize(14.5)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.cx.text)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        this.Pill({ label: f.severity, color: this.severityColor(f.severity), bg: this.severityBg(f.severity) })
        this.Pill({ label: this.stake(f, report.facts.signed), color: this.cx.muted, bg: this.cx.surface2 })
      }
      .width('100%')
      Text(f.reason)
        .fontSize(13.5)
        .lineHeight(22)
        .fontColor(this.cx.muted)
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text((f.ruleId === 'AI' ? 'AI 审查意见' : '规则 ' + f.ruleId) + '  查看条款 ›')
        .fontSize(11)
        .fontColor(this.cx.faint)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ left: 2, right: 2, top: 12, bottom: 12 })
    .border({ width: { bottom: 1 }, color: { bottom: this.cx.line } })
    .onClick(() => {
      this.openFinding(this.report()!.findings.indexOf(f));
    })
  }

  @Builder
  private Report() {
    if (this.report() !== undefined) {
      Scroll() {
        Column({ space: 10 }) {
          Column({ space: 8 }) {
            Row() {
              Text(`发现 ${this.report()!.findings.length} 处问题`)
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.cx.text)
                .layoutWeight(1)
              this.Pill({ label: this.aiLabel(this.report()!), color: this.cx.ok, bg: this.cx.okBg })
            }
            .width('100%')
            Row({ space: 4 }) {
              ForEach(SEVERITIES, (s: string) => {
                if (this.count(this.report()!, s) > 0) {
                  Column()
                    .height(6)
                    .layoutWeight(this.count(this.report()!, s))
                    .backgroundColor(this.severityColor(s))
                    .borderRadius(3)
                }
              })
            }
            .width('100%')
            Text(SEVERITIES.filter((s: string) => this.count(this.report()!, s) > 0)
              .map((s: string) => `${s} ${this.count(this.report()!, s)}`).join(' · '))
              .fontSize(11.5)
              .fontColor(this.cx.muted)
              .width('100%')
            if (this.report()!.aiNote.length > 0) {
              Text(this.report()!.aiNote).fontSize(11).fontColor(this.cx.warn).width('100%')
            }
            if (this.report()!.scanned) {
              Text('合同来自文字识别，可能有识别错误；不提供改写条款，请对照原件核对。')
                .fontSize(11)
                .fontColor(this.cx.warn)
                .width('100%')
            }
          }
          .padding({ left: 2, right: 2, top: 4, bottom: 4 })

          if (this.pendingFacts(this.report()!).length > 0) {
            Text('⚠ 部分结论取决于：' + this.pendingFacts(this.report()!) + '，已标为待确认')
              .fontSize(11.5)
              .lineHeight(17)
              .fontColor(this.cx.warn)
              .padding(11)
              .width('100%')
              .backgroundColor(this.isDark ? '#2A2416' : '#FFF8EC')
              .borderRadius(12)
          }

          ForEach(this.visibleOrder(), (k: number) => {
            this.FindingRow(this.report()!, this.report()!.findings[k])
          }, (k: number) => this.reportId + '_' + k.toString())

          if (this.report()!.warnings.length > 0) {
            Column({ space: 6 }) {
              Text(`结构检查 ${this.report()!.warnings.length} 条 ${this.showWarnings ? '收起' : '展开'}`)
                .fontSize(12.5)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.cx.text)
                .width('100%')
                .onClick(() => {
                  this.showWarnings = !this.showWarnings;
                })
              if (this.showWarnings) {
                ForEach(this.report()!.warnings, (w: StructureWarning) => {
                  Text(`[${w.kind}] ${w.detail}`).fontSize(11).lineHeight(17).fontColor(this.cx.muted).width('100%')
                })
              }
            }
            .padding(12)
            .backgroundColor(this.cx.surface2)
            .borderRadius(14)
          }
          Text(DISCLAIMER).fontSize(10.5).lineHeight(16).fontColor(this.cx.faint).width('100%')
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 24 })
      }
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .layoutWeight(1)
      .onDidScroll((xOffset: number, yOffset: number) => {
        this.foldAsk(yOffset);
      })
      .onReachStart(() => {
        this.unfoldAtTop();
      })
    }
  }

  // Folds on a downward scroll. It unfolds only from the 问 AI button or at
  // the top: unfolding on any upward scroll shrinks the text area, which
  // scrolls it and folds it again.
  private foldAsk(delta: number): void {
    // Per-frame deltas of a slow scroll are small, so add them up.
    this.downScroll = delta > 0 ? this.downScroll + delta : 0;
    if (this.downScroll > 24) {
      this.setFolded(true);
    }
  }

  // Compact header for a report: back, name, position among the findings, then
  // the severity filters and the text / list switch.
  @Builder
  private ReportHeader() {
    Column({ space: 8 }) {
      Row({ space: 10 }) {
        Text('‹')
          .fontSize(22)
          .fontColor(this.cx.gold)
          .textAlign(TextAlign.Center)
          .width(34)
          .height(34)
          .backgroundColor(this.cx.tint)
          .borderRadius(17)
          .accessibilityText('返回')
          .onClick(() => {
            this.goBack();
          })
        Text(this.report()?.fileName ?? '审查结果')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.cx.text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (this.visibleOrder().length > 0) {
          Text(this.visibleOrder().length.toString() + ' 处问题')
            .fontSize(12)
            .fontColor(this.cx.muted)
        }
      }
      .width('100%')
      Row({ space: 6 }) {
        ForEach(SEVERITIES.filter((sev: string) => this.report() !== undefined && this.count(this.report()!, sev) > 0),
          (sev: string) => {
            Text(sev + ' ' + this.count(this.report()!, sev).toString())
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.severityFilter === sev ? this.cx.onBrand : this.severityColor(sev))
              .padding({ left: 9, right: 9, top: 4, bottom: 4 })
              .backgroundColor(this.severityFilter === sev ? this.severityColor(sev) : this.severityBg(sev))
              .borderRadius(11)
              .accessibilityText('只看' + sev)
              .onClick(() => {
                this.severityFilter = this.severityFilter === sev ? '' : sev;
                this.navPos = -1;
              })
          })
        Blank()
        Row() {
          Text('原文')
            .fontSize(11.5)
            .fontColor(this.reportView === VIEW_TEXT ? this.cx.text : this.cx.muted)
            .fontWeight(this.reportView === VIEW_TEXT ? FontWeight.Bold : FontWeight.Regular)
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .backgroundColor(this.reportView === VIEW_TEXT ? this.cx.surface : Color.Transparent)
            .borderRadius(9)
            .onClick(() => {
              this.reportView = VIEW_TEXT;
            })
          Text('清单')
            .fontSize(11.5)
            .fontColor(this.reportView === VIEW_LIST ? this.cx.text : this.cx.muted)
            .fontWeight(this.reportView === VIEW_LIST ? FontWeight.Bold : FontWeight.Regular)
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .backgroundColor(this.reportView === VIEW_LIST ? this.cx.surface : Color.Transparent)
            .borderRadius(9)
            .onClick(() => {
              this.reportView = VIEW_LIST;
            })
        }
        .padding(2)
        .backgroundColor(this.cx.surface2)
        .borderRadius(11)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 14, right: 12, top: this.embedded ? 40 : 52, bottom: 8 })
    .border({ width: { bottom: 1 }, color: { bottom: this.cx.line } })
  }

  @Builder
  private NavArrow(up: boolean) {
    Column() {
      Image($r('app.media.ic_arrow_down'))
        .width(18)
        .height(18)
        .fillColor(this.cx.text)
        .rotate({ angle: up ? 180 : 0 })
    }
    .width(40)
    .height(40)
    .justifyContent(FlexAlign.Center)
    .accessibilityText(up ? '上一处问题' : '下一处问题')
    .onClick(() => {
      this.step(up ? -1 : 1, false);
    })
  }

  // Under the text while reading, beside 问 AI: steps through the findings in
  // reading order (within the severity filter) and names the one marked.
  // Tapping the name opens it.
  @Builder
  private FindingNavigator() {
    Row() {
      this.NavArrow(true)
      Text(this.currentFinding() === undefined ? '从第 1 处看起' :
        this.currentFinding()!.severity + ' · 第 ' + (this.navPos + 1).toString() + '/' +
          this.visibleOrder().length.toString() + ' 处')
        .fontSize(12.5)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.currentFinding() === undefined ? this.cx.text : this.severityColor(this.currentFinding()!.severity))
        .maxLines(1)
        // A fixed width keeps the arrows in place as the label changes.
        .width(124)
        .textAlign(TextAlign.Center)
        .accessibilityText(this.currentFinding() === undefined ? '从第一处问题看起' : '打开这一处的详情')
        .onClick(() => {
          const order: number[] = this.visibleOrder();
          if (this.navPos < 0) {
            this.step(1, false);
          } else if (this.navPos < order.length) {
            this.openFinding(order[this.navPos]);
          }
        })
      this.NavArrow(false)
    }
    .height(40)
    .backgroundColor(this.cx.surface)
    .borderRadius(20)
    .border({ width: 1, color: this.cx.line })
    .shadow({ radius: 10, color: this.cx.softShadow, offsetY: 3 })
    .margin({ left: 16, bottom: READING_FAB_BOTTOM - 1 })
  }

  @Builder
  private DocLineView(line: DocLine) {
    Text() {
      ForEach(line.segments, (seg: DocSegment) => {
        Span(seg.text)
          .fontColor(this.cx.text)
          .textBackgroundStyle({ color: this.highlightBg(seg), radius: 3 })
          .decoration({
            type: seg.finding >= 0 && this.highlightBg(seg) !== '#00000000' ? TextDecorationType.Underline :
              TextDecorationType.None,
            color: this.severityColor(seg.severity),
            style: seg.severity === SEVERITY_REDLINE ? TextDecorationStyle.SOLID : TextDecorationStyle.DASHED
          })
          .onClick(() => {
            if (seg.finding >= 0) {
              this.openFinding(seg.finding);
            }
          })
      }, (seg: DocSegment, i: number) => i.toString() + '_' + seg.finding.toString() + '_' + seg.text.length.toString())
      if (line.clauseFindings.length > 0) {
        Span(`  ⚑ ${line.clauseFindings.length} 处`)
          .fontSize(11.5)
          .fontColor(this.cx.warn)
          .onClick(() => {
            this.openFinding(line.clauseFindings[0]);
          })
      }
    }
    .id('docline-' + line.index.toString())
    .fontSize(line.heading ? 15.5 : 15)
    .fontWeight(line.heading ? FontWeight.Bold : FontWeight.Regular)
    .lineHeight(26)
    .width('100%')
    .margin({ top: line.heading && line.index > 0 ? 10 : 0 })
  }

  // The contract with its problems marked where they are; tap one to open it.
  @Builder
  private DocView() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Scroll(this.docScroller) {
        Column({ space: 2 }) {
          if (this.report()!.aiNote.length > 0 || this.report()!.scanned || this.pendingFacts(this.report()!).length > 0) {
            Column({ space: 4 }) {
              if (this.report()!.aiNote.length > 0) {
                Text(this.report()!.aiNote).fontSize(11).fontColor(this.cx.warn).width('100%')
              }
              if (this.report()!.scanned) {
                Text('合同来自文字识别，可能有识别错误，请对照原件核对。').fontSize(11).fontColor(this.cx.warn).width('100%')
              }
              if (this.pendingFacts(this.report()!).length > 0) {
                Text('⚠ 部分结论取决于：' + this.pendingFacts(this.report()!)).fontSize(11).fontColor(this.cx.warn)
                  .width('100%')
              }
            }
            .width('100%')
            .margin({ bottom: 8 })
          }
          ForEach(this.wholeFindings, (k: number) => {
            Row({ space: 6 }) {
              this.Pill({
                label: this.report()!.findings[k].severity,
                color: this.severityColor(this.report()!.findings[k].severity),
                bg: this.severityBg(this.report()!.findings[k].severity)
              })
              Text('全文 · ' + this.report()!.findings[k].reason)
                .fontSize(12.5)
                .fontColor(this.cx.text)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              Text('›').fontSize(16).fontColor(this.cx.faint)
            }
            .width('100%')
            .padding({ top: 6, bottom: 6 })
            .onClick(() => {
              this.openFinding(k);
            })
          }, (k: number) => this.reportId + '_w' + k.toString())
          ForEach(this.docLines, (line: DocLine) => {
            this.DocLineView(line)
          }, (line: DocLine) => this.reportId + '_' + line.index.toString())
          Text(DISCLAIMER).fontSize(10.5).lineHeight(16).fontColor(this.cx.faint).width('100%').margin({ top: 16 })
        }
        .width('100%')
        .padding({ left: 16, right: 22, top: 10, bottom: this.askCollapsed ? 90 : 24 })
      }
      .id(DOC_SCROLL_ID)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .width('100%')
      .height('100%')
      .onAreaChange((oldValue: Area, newValue: Area) => {
        this.docViewport = newValue.height as number;
      })
      .onDidScroll((xOffset: number, yOffset: number) => {
        this.foldAsk(yOffset);
      })
      .onReachStart(() => {
        this.unfoldAtTop();
      })
      this.Minimap()
    }
    .layoutWeight(1)
  }

  // Ticks on the right edge for every finding, at its place in the text.
  @Builder
  private Minimap() {
    Stack() {
      ForEach(this.visibleOrder(), (k: number) => {
        Column()
          .width(4)
          .height(9)
          .borderRadius(2)
          .backgroundColor(this.severityColor(this.report()!.findings[k].severity))
          .position({ x: 4, y: 8 + this.tickRatio(k) * Math.max(0, this.docViewport - 30) })
          .responseRegion({ x: -6, y: -4, width: 18, height: 17 })
          .onClick(() => {
            this.openFinding(k);
          })
      }, (k: number) => this.reportId + '_t' + k.toString() + '_' + this.docViewport.toString())
    }
    .width(12)
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
  }

  private tickRatio(k: number): number {
    const report: ContractReport = this.report()!;
    const f: Finding = report.findings[k];
    const anchor: ClauseAnchor | undefined = report.anchors.find((a: ClauseAnchor) => a.anchorId === f.anchorId);
    const pos: number = f.start >= 0 ? f.start : (anchor !== undefined ? anchor.start : 0);
    return report.text.length > 0 ? Math.min(1, pos / report.text.length) : 0;
  }

  // Composer pinned at the bottom, as in 普法: the question goes to 案件 with
  // the clause (or the whole report) attached.
  @Builder
  private PinnedAsk() {
    Column() {
      Column()
        .width('100%')
        .height(22)
        .linearGradient({ angle: 180, colors: [['#00' + this.cx.bgBottom.substring(1), 0.0], [this.cx.bgBottom, 1.0]] })
        .hitTestBehavior(HitTestMode.Transparent)
      Column() {
        Row({ space: 6 }) {
          TextArea({
            text: this.question,
            placeholder: this.mode === CONTRACT_MODE_CLAUSE ? '就这一条继续问…' : '就这份合同继续问…',
            controller: this.askController
          })
            .layoutWeight(1)
            .constraintSize({ minHeight: 38, maxHeight: 100 })
            .fontSize(15)
            .fontColor(this.cx.text)
            .placeholderColor(this.cx.placeholder)
            .caretColor(this.cx.gold)
            .selectedBackgroundColor(this.cx.selection)
            .backgroundColor(Color.Transparent)
            .borderWidth(0)
            .padding({ left: 12, right: 4, top: 8, bottom: 8 })
            .onChange((value: string) => {
              this.question = value;
            })
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            Image($r('app.media.ic_send')).width(17).height(17).fillColor(this.cx.onGold)
          }
          .width(36)
          .height(36)
          .backgroundColor(this.cx.gold)
          .accessibilityText('带着审查结果去维权里提问')
          .onClick(() => {
            this.sendQuestion();
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Bottom)
        .padding(4)
        .backgroundColor(this.cx.surface)
        .borderRadius(24)
        .border({ width: 1, color: this.cx.line })
        .shadow({ radius: 14, color: this.cx.softShadow, offsetY: 4 })
        Text('发送后在「维权」中继续 · AI 内容仅供参考')
          .fontSize(9)
          .fontColor(this.cx.muted)
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: 5 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 24 + this.bottomInset })
      .backgroundColor(this.cx.bgBottom)
    }
    .width('100%')
  }

  @Builder
  private Section(p: SectionParams) {
    if (p.body.length > 0) {
      Column({ space: 3 }) {
        Text(p.title).fontSize(12.5).fontWeight(FontWeight.Medium).fontColor(this.cx.muted).width('100%')
        Text(p.body).fontSize(15).lineHeight(25).fontColor(this.cx.text).width('100%')
          .copyOption(CopyOptions.LocalDevice)
      }
      .width('100%')
    }
  }

  @Builder
  private ActionChip(label: string, color: string, action: () => void) {
    Text(label)
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontColor(color)
      .height(30)
      .padding({ left: 11, right: 12 })
      .borderRadius(15)
      .backgroundColor(this.cx.tint)
      .onClick(() => {
        action();
      })
  }

  @Builder
  private SheetBody() {
    if (this.sheet === SHEET_PREVIEW) {
      this.PreviewSheet()
    } else if (this.sheet === SHEET_FINDING) {
      this.FindingSheet()
    } else {
      this.LawSheetBody()
    }
  }

  // One finding: the words, why, how it was judged, the law, what to do, and
  // for AI findings the model's own reasoning.
  @Builder
  private FindingSheet() {
    if (this.currentFinding() !== undefined && this.report() !== undefined) {
      Column() {
        Scroll() {
          Column({ space: 10 }) {
            Row({ space: 5 }) {
              Text(ContractReviewService.anchorLabel(this.report()!, this.currentFinding()!.anchorId) + ' · ' +
                this.currentFinding()!.topic)
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.cx.text)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .flexShrink(1)
              this.Pill({ label: this.currentFinding()!.severity, color: this.severityColor(this.currentFinding()!.severity), bg: this.severityBg(this.currentFinding()!.severity) })
              this.Pill({ label: this.stake(this.currentFinding()!, this.report()!.facts.signed), color: this.cx.muted, bg: this.cx.surface2 })
              Blank()
              Text((this.navPos + 1).toString() + ' / ' + this.visibleOrder().length.toString())
                .fontSize(11)
                .fontColor(this.cx.faint)
            }
            .width('100%')
            if (this.currentFinding()!.start >= 0) {
              Text(this.report()!.text.substring(this.currentFinding()!.start, this.currentFinding()!.end))
                .fontSize(13.5)
                .lineHeight(21)
                .fontColor(this.cx.muted)
                .width('100%')
                .padding({ left: 10, top: 2, bottom: 2 })
                .border({ width: { left: 3 }, color: { left: this.severityColor(this.currentFinding()!.severity) } })
            }
            this.Section({ title: '为什么有问题', body: this.currentFinding()!.reason })
            if (this.currentFinding()!.trace.length > 0) {
              Column({ space: 5 }) {
                Text('审查过程 · 规则 ' + this.currentFinding()!.ruleId)
                  .fontSize(12.5)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.cx.muted)
                  .width('100%')
                ForEach(this.currentFinding()!.trace, (line: string, i: number) => {
                  Row({ space: 7 }) {
                    Text((i + 1).toString())
                      .fontSize(10)
                      .fontColor(this.cx.brand)
                      .textAlign(TextAlign.Center)
                      .width(17)
                      .height(17)
                      .borderRadius(9)
                      .backgroundColor(this.cx.tint)
                    Text(line).fontSize(13.5).lineHeight(21).fontColor(this.cx.text).layoutWeight(1)
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Top)
                }, (line: string, i: number) => i.toString() + line)
              }
              .width('100%')
            } else if (this.currentFinding()!.ruleId !== 'AI') {
              Text('审查过程：重新审查这份合同后可查看').fontSize(11.5).fontColor(this.cx.faint).width('100%')
            }
            if (this.currentFinding()!.lawRefs.length > 0) {
              Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
                ForEach(this.currentFinding()!.lawRefs, (ref: string) => {
                  this.ActionChip(this.refLabel(ref) + ' ›', this.cx.brand, () => {
                    this.openLaw(ref);
                  })
                })
              }
              .width('100%')
            }
            this.Section({ title: '建议', body: this.currentFinding()!.suggestion })
            if (!this.report()!.scanned) {
              this.Section({ title: '可以改为', body: this.currentFinding()!.altClause })
            }
            this.Section({ title: '证据缺口', body: this.currentFinding()!.evidenceGap })
            if (this.currentFinding()!.pendingFacts.length > 0) {
              this.Section({ title: '待确认', body: this.currentFinding()!.pendingFacts.join('、') })
            }
            if (this.currentFinding()!.ruleId === 'AI') {
              Column({ space: 5 }) {
                Row() {
                  Text('AI 思考过程' + (this.batchOf(this.currentFinding()!) !== undefined ?
                    ' · ' + this.batchOf(this.currentFinding()!)!.label + ' · 用时 ' +
                      this.batchOf(this.currentFinding()!)!.seconds.toString() + ' 秒' : ''))
                    .fontSize(12.5)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.cx.gold)
                    .layoutWeight(1)
                  if (this.batchOf(this.currentFinding()!) !== undefined &&
                    this.batchOf(this.currentFinding()!)!.reasoning.length > 0) {
                    Text(this.showThinking ? '收起' : '展开')
                      .fontSize(11.5)
                      .fontColor(this.cx.faint)
                      .onClick(() => {
                        this.showThinking = !this.showThinking;
                      })
                  }
                }
                .width('100%')
                if (this.batchOf(this.currentFinding()!) === undefined ||
                  this.batchOf(this.currentFinding()!)!.reasoning.length === 0) {
                  Text('这个模型没有返回思考过程。').fontSize(11.5).fontColor(this.cx.faint).width('100%')
                } else if (this.showThinking) {
                  Text(this.batchOf(this.currentFinding()!)!.reasoning)
                    .fontSize(12.5)
                    .lineHeight(20)
                    .fontColor(this.cx.muted)
                    .width('100%')
                    .padding({ left: 10 })
                    .border({ width: { left: 2 }, color: { left: this.cx.gold } })
                  Text('思考过程由模型生成，覆盖这一批的全部条款，未经引用校验，以审查结论为准。')
                    .fontSize(10.5)
                    .fontColor(this.cx.faint)
                    .width('100%')
                }
              }
              .width('100%')
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 4, bottom: 12 })
        }
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .layoutWeight(1)
        Row({ space: 8 }) {
          if (this.currentFinding()!.suggestion.length > 0) {
            this.ActionChip('复制建议', this.cx.gold, () => {
              const f: Finding = this.currentFinding()!;
              this.copy(f.suggestion + (f.altClause.length > 0 && !this.report()!.scanned ? '\n' + f.altClause : ''),
                '已复制建议');
            })
          }
          Blank()
          this.ActionChip('‹ 上一处', this.cx.text, () => {
            this.step(-1);
          })
          this.ActionChip('下一处 ›', this.cx.text, () => {
            this.step(1);
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 24 })
        .border({ width: { top: 1 }, color: { top: this.cx.line } })
      }
      .width('100%')
      .height('100%')
    }
  }

  @Builder
  private PreviewSheet() {
    Scroll() {
      Column({ space: 10 }) {
        Text('将发送给模型的内容（第 1 批示例）').fontSize(16).fontWeight(FontWeight.Bold).fontColor(this.cx.text)
        Text('每批最多 6 个条款，另附检索到的法条和上面填的事实。合同文件本身不会发送。')
          .fontSize(11.5).lineHeight(17).fontColor(this.cx.muted)
        Text(this.preview())
          .fontSize(12)
          .lineHeight(19)
          .fontColor(this.cx.text)
          .padding(11)
          .backgroundColor(this.cx.surface2)
          .borderRadius(12)
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .padding(16)
    }
    .align(Alignment.Top)
  }

  @Builder
  private LawSheetBody() {
    Scroll() {
      Column({ space: 10 }) {
        if (this.lawFromFinding) {
          Text('‹ 返回这一处问题')
            .fontSize(12.5)
            .fontColor(this.cx.brand)
            .onClick(() => {
              this.sheet = SHEET_FINDING;
            })
        }
        Text(this.law !== undefined ? `${this.law.title} ${this.law.article}` : this.lawRef)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.cx.text)
        if (this.law !== undefined) {
          Text(this.law.excerpt).fontSize(13).lineHeight(21).fontColor(this.cx.text).copyOption(CopyOptions.LocalDevice)
          Text(`${this.law.status}${this.law.effectiveDate.length > 0 ? ' · 生效 ' + this.law.effectiveDate : ''}`)
            .fontSize(11)
            .fontColor(this.cx.muted)
        } else {
          Text('本地法规库中没有找到这一条的原文，请到国家法律法规数据库核对。')
            .fontSize(12.5)
            .lineHeight(19)
            .fontColor(this.cx.muted)
        }
        Text(CORPUS_NOTE).fontSize(10.5).lineHeight(16).fontColor(this.cx.faint)
      }
      .alignItems(HorizontalAlign.Start)
      .padding(16)
    }
    .align(Alignment.Top)
  }

  build() {
    Column() {
      if (this.mode === CONTRACT_MODE_REPORT) {
        this.ReportHeader()
      } else if (!this.embedded || this.mode !== CONTRACT_MODE_HOME) {
        this.Header()
      }
      if (this.notice.length > 0) {
        Text(this.notice)
          .fontSize(12)
          .fontColor(this.cx.warn)
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 8 })
          .onClick(() => {
            this.notice = '';
          })
      }
      if (this.mode === CONTRACT_MODE_FACTS) {
        Stack({ alignContent: Alignment.Bottom }) {
          this.Facts()
          Column({ space: 8 }) {
            if (this.busy) {
              Text(this.progress).fontSize(12).fontColor(this.cx.muted)
            }
            Row({ space: 10 }) {
              if (this.busy && this.handle !== undefined) {
                Button('停止')
                  .fontSize(14)
                  .fontColor(this.cx.danger)
                  .backgroundColor(this.cx.dangerBg)
                  .height(44)
                  .layoutWeight(1)
                  .onClick(() => {
                    this.handle?.cancel();
                  })
              }
              Button(this.busy ? '审查中…' : '开始审查')
                .fontSize(15)
                .fontColor(this.cx.onGold)
                .backgroundColor(this.cx.gold)
                .height(44)
                .layoutWeight(2)
                .enabled(!this.busy)
                .onClick(() => {
                  this.start();
                })
            }
            .width('100%')
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 10, bottom: 28 + this.bottomInset })
          .backgroundColor(this.cx.bgBottom)
        }
        .layoutWeight(1)
      } else if (this.mode === CONTRACT_MODE_REPORT || this.mode === CONTRACT_MODE_CLAUSE) {
        Stack({ alignContent: Alignment.BottomEnd }) {
          Column() {
            if (this.report() !== undefined && this.reportView === VIEW_TEXT) {
              this.DocView()
            } else {
              this.Report()
            }
            if (!this.askCollapsed) {
              this.PinnedAsk()
            }
          }
          .width('100%')
          .height('100%')
          if (this.askCollapsed) {
            Row() {
              if (this.report() !== undefined && this.reportView === VIEW_TEXT && this.visibleOrder().length > 0) {
                this.FindingNavigator()
              }
              Blank()
              AskFab({
                label: '问 AI',
                cx: this.cx,
                onOpen: () => {
                  this.setFolded(false);
                }
              })
            }
            .width('100%')
            .alignItems(VerticalAlign.Bottom)
          }
        }
        .layoutWeight(1)
      } else {
        if (this.busy) {
          Text(this.progress).fontSize(12).fontColor(this.cx.muted).padding({ left: 16, bottom: 8 }).width('100%')
        }
        this.Home()
      }
    }
    .width('100%')
    .height('100%')
    .linearGradient({
      angle: 180,
      colors: [[this.cx.bgTop, 0.0], [this.cx.bgBottom, 1.0]]
    })
    .bindSheet(this.sheet !== SHEET_NONE, this.SheetBody(), {
      height: this.sheet === SHEET_PREVIEW ? '70%' : this.sheet === SHEET_FINDING ? '62%' : '60%',
      dragBar: true,
      showClose: false,
      maskColor: this.isDark ? '#88040B18' : '#66404A5A',
      onWillDismiss: () => {
        this.sheet = SHEET_NONE;
      }
    })
  }
}
