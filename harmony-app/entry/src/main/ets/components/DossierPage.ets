import { AppEnv } from '../models/AppEnv';
import { CaseFieldInfo, LawCitation } from '../models/AppModels';
import { CaseState } from '../models/CaseState';
import { ChatSession } from '../models/ChatSession';
import { ThemeColors } from '../theme/Theme';
import { SCROLLED_PAST } from './BrandBar';
import { AnswerActionsView, AnswerText, ChatActions, ChatIcon, ErrorNotice, SendingRow } from './chat/ChatViews';

// 维权 · 卷宗: the six case fields, the floating checklist, and the analysis
// report generated from them.

const CONTENT_BOTTOM: number = 128;

export class DossierActions {
  // A field was edited: progress and saving follow.
  changed: () => void = () => {
  };
  toggleFloat: () => void = () => {
  };
  generate: () => void = () => {
  };
  stop: () => void = () => {
  };
  openSettings: () => void = () => {
  };
}

export interface RingParams {
  value: number;
  size: number;
  cx: ThemeColors;
}

// How complete the dossier is, as a ring with the percentage inside.
@Builder
export function ProgressRing(p: RingParams) {
  Stack() {
    Progress({ value: p.value, total: 100, type: ProgressType.Ring })
      .width(p.size)
      .height(p.size)
      .color(p.cx.gold)
      .backgroundColor(p.cx.surface2)
      .style({ strokeWidth: 5 })
    Text(p.value.toString() + '%')
      .fontSize(p.size > 48 ? 14 : 12)
      .fontWeight(FontWeight.Bold)
      .fontColor(p.cx.text)
  }
  .width(p.size)
  .height(p.size)
}

@Component
export struct DossierPage {
  @Consume('env') env: AppEnv;
  @ObjectLink caseState: CaseState;
  // The report's request while it streams.
  @ObjectLink reportRun: ChatSession;
  @Prop floatActive: boolean = false;
  @Prop floatBusy: boolean = false;
  @Prop floatError: string = '';
  // Room at the top for the title bar floating over the page.
  @Prop topInset: number = 0;
  // Whether the page has scrolled under that title bar.
  onScrolled: (scrolled: boolean) => void = () => {
  };
  caseFields: CaseFieldInfo[] = [];
  // The page's, so it can end editing before sending the report.
  fieldControllers: TextInputController[] = [];
  detailsController: TextAreaController = new TextAreaController();
  scroller: Scroller = new Scroller();
  actions: DossierActions = new DossierActions();
  chatActions: ChatActions = new ChatActions();

  // The report as it streams in, then as saved.
  private reportText(): string {
    return this.reportRun.streaming.length > 0 ? this.reportRun.streaming : this.caseState.report;
  }

  private reportTextCitations(): LawCitation[] {
    return this.reportRun.streaming.length > 0 ? this.reportRun.streamCitations : this.caseState.reportCitations;
  }

  @Builder
  private ErrorHint(message: string) {
    ErrorNotice({
      message: message,
      cx: this.env.cx,
      onSettings: () => {
        this.actions.openSettings();
      }
    })
  }

  @Builder
  private StopButton() {
    Row() {
      Button('停止生成')
        .fontSize(12)
        .fontColor(this.env.cx.danger)
        .height(32)
        .padding({ left: 14, right: 14 })
        .backgroundColor(this.env.cx.dangerBg)
        .borderRadius(10)
        .onClick(() => {
          this.actions.stop();
        })
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private FieldInput(label: string, hint: string, value: string, fieldIndex: number) {
    Column() {
      Row({ space: 6 }) {
        Text(label)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.env.cx.muted)
        if (this.caseState.fieldFilled(fieldIndex)) {
          ChatIcon({ res: $r('app.media.ic_check'), size: 12, color: this.env.cx.ok })
        }
      }
      .width('100%')
      .margin({ bottom: 7 })
      if (fieldIndex === 5) {
        TextArea({ text: value, placeholder: hint, controller: this.detailsController })
          .height(96)
          .fontColor(this.env.cx.text)
          .placeholderColor(this.env.cx.placeholder)
          .caretColor(this.env.cx.gold)
          .selectedBackgroundColor(this.env.cx.selection)
          .backgroundColor(this.env.cx.surface2)
          .borderRadius(12)
          .border({ width: 1, color: this.env.cx.line })
          .onChange((newValue: string) => {
            this.caseState.details = newValue;
            this.actions.changed();
          })
      } else {
        TextInput({ text: value, placeholder: hint, controller: this.fieldControllers[fieldIndex] })
          .height(46)
          .fontColor(this.env.cx.text)
          .placeholderColor(this.env.cx.placeholder)
          .caretColor(this.env.cx.gold)
          .selectedBackgroundColor(this.env.cx.selection)
          .backgroundColor(this.env.cx.surface2)
          .borderRadius(12)
          .border({ width: 1, color: this.env.cx.line })
          .onChange((newValue: string) => {
            if (fieldIndex === 0) {
              this.caseState.location = newValue;
            } else if (fieldIndex === 1) {
              this.caseState.company = newValue;
            } else if (fieldIndex === 2) {
              this.caseState.salary = newValue;
            } else if (fieldIndex === 3) {
              this.caseState.timeline = newValue;
            } else if (fieldIndex === 4) {
              this.caseState.request = newValue;
            }
            this.actions.changed();
          })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private CitationPanel(citations: LawCitation[]) {
    if (citations.length > 0) {
      Column({ space: 8 }) {
        Row({ space: 6 }) {
          ChatIcon({ res: $r('app.media.ic_book'), size: 14, color: this.env.cx.brand })
          Text('本轮检索依据')
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.env.cx.brandStrong)
          Blank()
          Text('查看 ' + citations.length.toString() + ' 条  ›')
            .fontSize(11)
            .fontColor(this.env.cx.gold)
        }
        .width('100%')
        Text(citations[0].title + ' · ' + citations[0].article)
          .fontSize(11)
          .fontColor(this.env.cx.muted)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text('资料为机械收录，尚未完成全面法律效力审查，请以官方最新文本为准。')
          .fontSize(10)
          .lineHeight(15)
          .fontColor(this.env.cx.faint)
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding(12)
      .backgroundColor(this.env.cx.surface2)
      .borderRadius(16)
      .border({ width: 1, color: this.env.cx.line })
      .onClick(() => {
        this.chatActions.openCitations(citations);
      })
    }
  }

  build() {
    Scroll(this.scroller) {
      Column({ space: 14 }) {
        Row({ space: 13 }) {
          ProgressRing({ value: this.caseState.progress, size: 56, cx: this.env.cx })
          Column() {
            Text('信息完整度 ' + this.caseState.progress.toString() + '%')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.env.cx.text)
              .width('100%')
            Text('达到 60% 后可生成结构化分析报告')
              .fontSize(11.5)
              .fontColor(this.env.cx.muted)
              .width('100%')
              .margin({ top: 4 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding(15)
        .backgroundColor(this.env.cx.surface)
        .borderRadius(18)
        .border({ width: 1, color: this.env.cx.line })

        Button() {
          Row({ space: 9 }) {
            ChatIcon({ res: $r('app.media.ic_doc'), size: 18, color: this.env.cx.goldDeep })
            Column({ space: 3 }) {
              Text(this.floatBusy ?
                (this.floatActive ? '正在关闭闪控窗…' : '正在开启闪控窗…') :
                (this.floatActive ? '闪控窗已开启' : '悬浮查看待补事项'))
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.env.cx.text)
              Text(this.floatActive ? '切到桌面或其他应用即可查看 · 点击此处关闭' :
                '切换到聊天或工资记录时，也能查看六项材料状态')
                .fontSize(11)
                .fontColor(this.env.cx.muted)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Text(this.floatBusy ? '…' : (this.floatActive ? '✓' : '›'))
              .fontSize(22)
              .fontColor(this.floatActive ? this.env.cx.ok : this.env.cx.goldDeep)
          }
          .width('100%')
        }
        .width('100%')
        .padding(13)
        .backgroundColor(this.floatActive ? this.env.cx.okBg : this.env.cx.surface)
        .borderRadius(16)
        .border({ width: 1, color: this.floatActive ? this.env.cx.ok : this.env.cx.line })
        .enabled(!this.floatBusy)
        .onClick(() => {
          this.actions.toggleFloat();
        })
        if (this.floatError.length > 0) {
          this.ErrorHint(this.floatError)
        }

        Column({ space: 12 }) {
          Text('基本信息')
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.env.cx.faint)
            .width('100%')
          this.FieldInput(this.caseFields[0].label, this.caseFields[0].hint, this.caseState.location, 0)
          this.FieldInput(this.caseFields[1].label, this.caseFields[1].hint, this.caseState.company, 1)
          this.FieldInput(this.caseFields[2].label, this.caseFields[2].hint, this.caseState.salary, 2)
          this.FieldInput(this.caseFields[3].label, this.caseFields[3].hint, this.caseState.timeline, 3)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(15)
        .backgroundColor(this.env.cx.surface)
        .borderRadius(18)
        .border({ width: 1, color: this.env.cx.line })

        Column({ space: 12 }) {
          Text('案情')
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.env.cx.faint)
            .width('100%')
          this.FieldInput(this.caseFields[4].label, this.caseFields[4].hint, this.caseState.request, 4)
          this.FieldInput(this.caseFields[5].label, this.caseFields[5].hint, this.caseState.details, 5)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(15)
        .backgroundColor(this.env.cx.surface)
        .borderRadius(18)
        .border({ width: 1, color: this.env.cx.line })

        Button() {
          Row({ space: 8 }) {
            ChatIcon({ res: $r('app.media.ic_doc'), size: 16, color: this.caseState.progress >= 60 ? this.env.cx.onBrand : this.env.cx.faint })
            Text('生成案件分析报告')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.caseState.progress >= 60 ? this.env.cx.onBrand : this.env.cx.faint)
          }
        }
        .width('100%')
        .height(48)
        .backgroundColor(this.caseState.progress >= 60 ? this.env.cx.brand : this.env.cx.surface2)
        .borderRadius(14)
        .enabled(this.caseState.progress >= 60 && !this.reportRun.sending)
        .onClick(() => {
          this.actions.generate();
        })
        if (this.reportRun.sending) {
          SendingRow({ label: this.reportRun.streaming.length > 0 ? '正在生成案件分析报告…' : '正在准备案件分析报告…', cx: this.env.cx })
          this.StopButton()
        }
        if (this.reportRun.error.length > 0) {
          this.ErrorHint(this.reportRun.error)
        }
        if (this.reportRun.streaming.length > 0 || this.caseState.report.length > 0) {
          Column() {
            Row({ space: 7 }) {
              ChatIcon({ res: $r('app.media.ic_doc'), size: 16, color: this.env.cx.brand })
              Text('案件分析报告')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.env.cx.brandStrong)
            }
            .width('100%')
            AnswerText({
              content: this.reportText(),
              citations: this.reportTextCitations(),
              report: true,
              selectable: this.reportRun.streaming.length === 0,
              actions: this.chatActions
            })
              .margin({ top: 12 })
            if (this.reportRun.streaming.length === 0) {
              AnswerActionsView({
                content: this.caseState.report,
                citations: this.caseState.reportCitations,
                report: true,
                actions: this.chatActions
              })
              this.CitationPanel(this.caseState.reportCitations)
            }
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding(15)
          .backgroundColor(this.env.cx.surface)
          .borderRadius(18)
          .border({ width: 1, color: this.env.cx.line })
        }
        Text('资料只会保存在本机；提交分析时，相关内容将发送至你配置的模型 API。')
          .fontSize(11)
          .lineHeight(17)
          .fontColor(this.env.cx.muted)
          .textAlign(TextAlign.Center)
          .width('100%')
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14 + this.topInset, bottom: CONTENT_BOTTOM })
    }
    .scrollBar(BarState.Off)
    .width('100%')
    .height('100%')
    .edgeEffect(EdgeEffect.Spring)
    .onDidScroll(() => {
      this.onScrolled(this.scroller.currentOffset().yOffset > SCROLLED_PAST);
    })
  }
}
