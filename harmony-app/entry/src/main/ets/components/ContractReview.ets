import { common } from '@kit.AbilityKit';
import { LengthMetrics } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { ContractAi } from '../contract/ContractAi';
import { ContractLaws } from '../contract/ContractLaws';
import { ContractPrivacy } from '../contract/ContractPrivacy';
import { ContractRules } from '../contract/ContractRules';
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
  ContractReport,
  ContractReviewService,
  ContractSource,
  ReviewProgress
} from '../services/ContractReviewService';
import { CAT_CONTRACT } from '../services/EvidenceExtractor';
import { EvidenceStore } from '../services/EvidenceStore';
import { ThemeColors } from '../theme/Theme';

export const CONTRACT_MODE_HOME: number = 0;
export const CONTRACT_MODE_FACTS: number = 1;
export const CONTRACT_MODE_REPORT: number = 2;
export const CONTRACT_MODE_CLAUSE: number = 3;

const DISCLAIMER: string = '本结果为规则审查与 AI 辅助审查，用于提示合同风险，不构成法律意见。各地裁审口径不一，' +
  '涉及重大权益时请咨询律师或当地劳动仲裁部门。';
const SHEET_NONE: number = 0;
const SHEET_PREVIEW: number = 1;
const SHEET_LAW: number = 2;
const CORPUS_NOTE: string = '资料为机械收录，尚未完成全面法律效力审查，请以官方最新文本为准。';

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
  @Link mode: number;
  // Shown as the 合同 section rather than as a cover: the home page has no
  // header of its own, and content leaves room for the floating tab bar.
  @Prop embedded: boolean = false;
  @Prop bottomInset: number = 0;
  // Changes when local records are cleared elsewhere; the reports reload.
  @Prop @Watch('reload') dataVersion: number = 0;
  onCountChange: (count: number) => void = (count: number) => {
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

  private startFacts(source: ContractSource): void {
    this.source = source;
    this.notice = source.note;
    const terms = ContractRules.extractTerms(ContractReviewService.local(source, new FactSheet()).text);
    this.termText = terms.termMonths === TERM_UNKNOWN ? '' : terms.termMonths === TERM_OPEN ? '无固定期限' :
      terms.termMonths === TERM_TASK ? '以完成工作任务为期限' : terms.termMonths.toString();
    this.probationText = terms.probationDays > 0 ?
      (terms.probationDays % 30 === 0 ? (terms.probationDays / 30).toString() : (terms.probationDays / 30).toFixed(1)) : '';
    this.useAi = this.aiReady();
    this.mode = CONTRACT_MODE_FACTS;
  }

  private facts(): FactSheet {
    const facts: FactSheet = new FactSheet();
    facts.city = this.city.trim();
    facts.position = this.jobTitle.trim();
    facts.confidential = this.confidential;
    facts.signed = this.signed;
    const term: number = Number(this.termText.trim());
    facts.termMonths = this.termText.includes('无固定') ? TERM_OPEN : this.termText.includes('任务') ? TERM_TASK :
      this.termText.trim().length > 0 && Number.isFinite(term) && term > 0 ? term : TERM_UNKNOWN;
    const probation: number = Number(this.probationText.trim());
    facts.probationMonths = this.probationText.trim().length > 0 && Number.isFinite(probation) && probation >= 0 ?
      probation : -1;
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
    this.mode = CONTRACT_MODE_REPORT;
    this.articles = [];
    const report: ContractReport | undefined = this.report();
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
    this.sheet = SHEET_LAW;
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
  private Pill(label: string, color: string, bg: string) {
    Text(label)
      .fontSize(10)
      .fontWeight(FontWeight.Medium)
      .fontColor(color)
      .padding({ left: 7, right: 7, top: 2, bottom: 2 })
      .backgroundColor(bg)
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
        this.Pill(f.severity, this.severityColor(f.severity), this.severityBg(f.severity))
        this.Pill(this.stake(f, report.facts.signed), this.cx.muted, this.cx.surface2)
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
      this.anchorId = f.anchorId;
      this.mode = CONTRACT_MODE_CLAUSE;
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
              this.Pill(this.aiLabel(this.report()!), this.cx.ok, this.cx.okBg)
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

          ForEach(this.report()!.findings, (f: Finding) => {
            this.FindingRow(this.report()!, f)
          }, (f: Finding) => f.findingId + f.anchorId + f.topic)

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
    }
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
  private Section(title: string, body: string) {
    if (body.length > 0) {
      Column({ space: 3 }) {
        Text(title).fontSize(12.5).fontWeight(FontWeight.Medium).fontColor(this.cx.muted).width('100%')
        Text(body).fontSize(15).lineHeight(25).fontColor(this.cx.text).width('100%')
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

  // One finding on a clause, flat like a 普法 answer: badges, sections, then a
  // row of action chips.
  @Builder
  private ClauseFinding(report: ContractReport, f: Finding) {
    Column({ space: 10 }) {
      Row({ space: 5 }) {
        Text(f.topic).fontSize(15.5).fontWeight(FontWeight.Bold).fontColor(this.cx.text)
        this.Pill(f.severity, this.severityColor(f.severity), this.severityBg(f.severity))
        this.Pill(f.nature, this.cx.muted, this.cx.surface2)
        this.Pill(this.stake(f, report.facts.signed), this.cx.muted, this.cx.surface2)
        Blank()
        Text(f.ruleId === 'AI' ? 'AI 意见' : `规则 ${f.ruleId}`).fontSize(10).fontColor(this.cx.faint)
      }
      .width('100%')
      this.Section('为什么有问题', f.reason)
      this.Section('建议', f.suggestion)
      if (!report.scanned) {
        this.Section('可以改为', f.altClause)
      }
      this.Section('证据缺口', f.evidenceGap)
      if (f.pendingFacts.length > 0) {
        this.Section('待确认', f.pendingFacts.join('、'))
      }
      Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
        if (f.suggestion.length > 0) {
          this.ActionChip('复制建议', this.cx.gold, () => {
            this.copy(f.suggestion + (f.altClause.length > 0 && !report.scanned ? '\n' + f.altClause : ''), '已复制建议');
          })
        }
        ForEach(f.lawRefs, (ref: string) => {
          this.ActionChip(this.refLabel(ref) + (ContractLaws.isKnownMissing(ref) ? ' · 本地库未收录' : ' ›'),
            ContractLaws.isKnownMissing(ref) ? this.cx.faint : this.cx.brand, () => {
              if (!ContractLaws.isKnownMissing(ref)) {
                this.openLaw(ref);
              }
            })
        })
      }
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ left: 2, right: 2, top: 14, bottom: 14 })
    .border({ width: { bottom: 1 }, color: { bottom: this.cx.line } })
  }

  @Builder
  private Clause() {
    if (this.report() !== undefined) {
      Scroll() {
        Column({ space: 4 }) {
          if (this.anchorId !== WHOLE_CONTRACT) {
            Text(this.report()!.anchors.find((a: ClauseAnchor) => a.anchorId === this.anchorId)?.text ?? '')
              .fontSize(14)
              .lineHeight(23)
              .fontColor(this.cx.muted)
              .copyOption(CopyOptions.LocalDevice)
              .width('100%')
              .padding({ left: 12, right: 4, top: 2, bottom: 2 })
              .border({ width: { left: 3 }, color: { left: this.cx.gold } })
              .margin({ bottom: 6 })
          } else {
            Text('全文级问题：合同整体缺少或存在的约定').fontSize(12.5).fontColor(this.cx.muted).width('100%')
          }
          ForEach(this.report()!.findings.filter((f: Finding) => f.anchorId === this.anchorId), (f: Finding) => {
            this.ClauseFinding(this.report()!, f)
          }, (f: Finding) => f.findingId + f.topic)
          Text(DISCLAIMER).fontSize(10.5).lineHeight(16).fontColor(this.cx.faint).width('100%').margin({ top: 10 })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 24 })
      }
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .layoutWeight(1)
    }
  }

  @Builder
  private SheetBody() {
    if (this.sheet === SHEET_PREVIEW) {
      this.PreviewSheet()
    } else {
      this.LawSheetBody()
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
      if (!this.embedded || this.mode !== CONTRACT_MODE_HOME) {
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
        Column() {
          if (this.mode === CONTRACT_MODE_CLAUSE) {
            this.Clause()
          } else {
            this.Report()
          }
          this.PinnedAsk()
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
      height: this.sheet === SHEET_PREVIEW ? '70%' : '60%',
      dragBar: true,
      showClose: false,
      maskColor: this.isDark ? '#88040B18' : '#66404A5A',
      onWillDismiss: () => {
        this.sheet = SHEET_NONE;
      }
    })
  }
}
