import { pasteboard } from '@kit.BasicServicesKit';
import { LengthMetrics } from '@kit.ArkUI';
import { AppEnv } from '../../models/AppEnv';
import { ChatMessage, ChatRole, FileAttachment, LawCitation } from '../../models/AppModels';
import { ChatSession } from '../../models/ChatSession';
import { AnswerSegment, CitationText } from '../../services/CitationText';
import { ConversationText } from '../../services/ConversationText';
import { EvidenceExtractor } from '../../services/EvidenceExtractor';
import { ThemeColors } from '../../theme/Theme';

// The conversation pieces 普法 and 维权 share: answers with citation chips and
// copy actions, the model's reasoning, the answer streaming in, and the
// composer pinned at the bottom. Theme comes from the 'env' the page provides;
// what needs the page (sheets, sending) goes through ChatActions.

// The floating tab bar's height plus its bottom margin; the pinned composer
// sits just above it.
export const TAB_BAR_CLEARANCE: number = 102;
// While reading, the folded composer sits this far from the bottom; the tab
// bar is hidden then.
export const READING_FAB_BOTTOM: number = 32;
const FAB_HEIGHT: number = 38;
// While reasoning streams in, only its tail is rendered to keep layout light.
const LIVE_REASONING_CHARS: number = 1500;

// What the conversation views ask the page to do.
export class ChatActions {
  openCitation: (content: string, citations: LawCitation[], index: number) => void =
    (content: string, citations: LawCitation[], index: number) => {
    };
  openCitations: (citations: LawCitation[]) => void = (citations: LawCitation[]) => {
  };
  openChecklist: (content: string) => void = (content: string) => {
  };
  // Text selection in an answer pauses the history drawer's swipe.
  selecting: (active: boolean) => void = (active: boolean) => {
  };
  send: (forCase: boolean) => void = (forCase: boolean) => {
  };
  stop: (forCase: boolean) => void = (forCase: boolean) => {
  };
  attach: (forCase: boolean) => void = (forCase: boolean) => {
  };
}

// The citation the citation sheet shows, provided as 'activeCitation', so its
// chip in the answer stands out.
export class CitationKey {
  static of(content: string, index: number): string {
    return index.toString() + '\u0001' + content;
  }
}

export interface IconParams {
  res: Resource;
  size: number;
  color: ResourceColor;
}

// Takes a single object literal so it is passed by reference: theme colors
// then refresh live instead of staying at the values from first render.
@Builder
export function ChatIcon(icon: IconParams) {
  Image(icon.res)
    .width(icon.size)
    .height(icon.size)
    .fillColor(icon.color)
    .draggable(false)
}

export interface SendingParams {
  label: string;
  cx: ThemeColors;
}

@Builder
export function SendingRow(p: SendingParams) {
  Row({ space: 9 }) {
    LoadingProgress()
      .width(20)
      .height(20)
      .color(p.cx.brand)
    Text(p.label)
      .fontSize(12)
      .fontColor(p.cx.muted)
  }
  .width('100%')
  .padding({ left: 4, top: 3, bottom: 3 })
}

export interface AttachmentParams {
  attachment: FileAttachment;
  cx: ThemeColors;
  onRemove: () => void;
}

@Builder
export function AttachmentRow(p: AttachmentParams) {
  Row() {
    Column() {
      ChatIcon({ res: $r('app.media.ic_doc'), size: 18, color: p.cx.brand })
    }
    .width(34)
    .height(34)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(p.cx.tint)
    .borderRadius(10)
    Column() {
      Text(p.attachment.name)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(p.cx.text)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text(p.attachment.format + ' · 已提取 ' + p.attachment.text.length.toString() + ' 字'
        + (p.attachment.truncated ? ' · 已截取' : ''))
        .fontSize(10)
        .fontColor(p.cx.muted)
        .margin({ top: 3 })
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
    .margin({ left: 9 })
    Button('移除')
      .fontSize(10)
      .fontColor(p.cx.danger)
      .height(30)
      .backgroundColor(p.cx.dangerBg)
      .borderRadius(9)
      .onClick(() => {
        p.onRemove();
      })
  }
  .width('100%')
  .padding(10)
  .backgroundColor(p.cx.surface2)
  .borderRadius(12)
  .border({ width: 1, color: p.cx.line })
  .margin({ bottom: 10 })
}

export interface AttachmentErrorParams {
  message: string;
  cx: ThemeColors;
}

@Builder
export function AttachmentErrorRow(p: AttachmentErrorParams) {
  Text(p.message)
    .fontSize(11)
    .lineHeight(17)
    .fontColor(p.cx.danger)
    .width('100%')
    .padding({ top: 7, bottom: 3 })
}

export interface ErrorParams {
  message: string;
  cx: ThemeColors;
  // Opens 我的; offered only for errors fixed there.
  onSettings: () => void;
}

@Builder
export function ErrorNotice(p: ErrorParams) {
  Row() {
    Text(p.message)
      .fontSize(12)
      .lineHeight(18)
      .fontColor(p.cx.danger)
      .layoutWeight(1)
    if (ConversationText.needsModelSettings(p.message)) {
      Button('去「我的」')
        .fontSize(11)
        .fontColor(p.cx.onBrand)
        .backgroundColor(p.cx.brand)
        .height(32)
        .borderRadius(10)
        .onClick(() => {
          p.onSettings();
        })
    }
  }
  .width('100%')
  .padding(10)
  .backgroundColor(p.cx.dangerBg)
  .borderRadius(12)
}

function chipBg(env: AppEnv): string {
  return env.isDark ? '#2A2416' : '#F6EAD2';
}

function reasoningBorder(env: AppEnv): string {
  return env.isDark ? '#3A3320' : '#EADBB8';
}

// Copies an answer, or the selected part of it; with citations, the used
// citations are listed after it.
function copyAnswer(ui: UIContext, content: string, citations: LawCitation[], withCitations: boolean,
  start: number = 0, end: number = -1): void {
  const text: string = CitationText.copyText(content, citations, withCitations, start, end);
  if (text.length === 0) {
    return;
  }
  const used: number = CitationText.usedCitationCount(content, citations.length);
  const message: string = !withCitations ? '已复制' :
    (end < 0 ? '已复制回答和 ' + used.toString() + ' 条依据' : '已复制，含引用依据');
  try {
    const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      ui.getPromptAction().showToast({ message: message, duration: 1500 });
    }).catch(() => {
      ui.getPromptAction().showToast({ message: '复制失败，请重试', duration: 1500 });
    });
  } catch (error) {
    ui.getPromptAction().showToast({ message: '复制失败，请重试', duration: 1500 });
  }
}

// An answer's text with tappable citation chips. report sets it at the dossier
// report's size; otherwise it is laid flat like 普法.
@Component
export struct AnswerText {
  @Consume('env') env: AppEnv;
  @Consume('activeCitation') activeCitation: string;
  @Prop content: string = '';
  @Prop citations: LawCitation[] = [];
  @Prop report: boolean = false;
  // Off while the text is still streaming in.
  @Prop selectable: boolean = true;
  actions: ChatActions = new ChatActions();

  private active(index: number): boolean {
    return this.activeCitation === CitationKey.of(this.content, index);
  }

  // The system copy item copies plain text; 复制含依据 is added when the
  // answer cites anything.
  private menu(): EditMenuOptions {
    const withCitationsId: TextMenuItemId = TextMenuItemId.of('copy_with_citations');
    return {
      onCreateMenu: (items: Array<TextMenuItem>): Array<TextMenuItem> => {
        if (CitationText.usedCitationCount(this.content, this.citations.length) === 0) {
          return items;
        }
        const copyIndex: number = items.findIndex((item: TextMenuItem) => item.id.equals(TextMenuItemId.COPY));
        const extra: TextMenuItem = { content: '复制含依据', id: withCitationsId };
        items.splice(copyIndex >= 0 ? copyIndex + 1 : items.length, 0, extra);
        return items;
      },
      onMenuItemClick: (item: TextMenuItem, range: TextRange): boolean => {
        const isPlain: boolean = item.id.equals(TextMenuItemId.COPY);
        if (!isPlain && !item.id.equals(withCitationsId)) {
          return false;
        }
        copyAnswer(this.getUIContext(), this.content, this.citations, !isPlain, range.start ?? 0, range.end ?? -1);
        return true;
      }
    };
  }

  build() {
    Text() {
      ForEach(CitationText.split(this.content, this.citations.length), (segment: AnswerSegment) => {
        if (segment.citationIndex < 0) {
          Span(segment.text)
        } else {
          Span(CitationText.chipLabel(segment.citationIndex))
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.active(segment.citationIndex) ? this.env.cx.onGold : this.env.cx.gold)
            .textBackgroundStyle({
              color: this.active(segment.citationIndex) ? this.env.cx.gold : chipBg(this.env),
              radius: 8
            })
            .onClick(() => {
              this.actions.openCitation(this.content, this.citations, segment.citationIndex);
            })
        }
      }, (segment: AnswerSegment, index: number) => index.toString() + '_' + segment.citationIndex.toString()
        + '_' + segment.text.length.toString())
    }
    .fontSize(this.report ? 15 : 15.5)
    .lineHeight(this.report ? 24 : 26)
    .fontColor(this.env.cx.text)
    .width('100%')
    .padding(this.report ? 0 : 2)
    .copyOption(this.selectable ? CopyOptions.LocalDevice : CopyOptions.None)
    .caretColor(this.env.cx.gold)
    .selectedBackgroundColor(this.env.cx.selection)
    .editMenuOptions(this.menu())
    .onTextSelectionChange((start: number, end: number) => {
      this.actions.selecting(start !== end);
    })
  }
}

// 复制 · 复制含依据 · 对照证据库 · 依据 N 条 under an answer. The report shows
// its citations in a panel of its own, so it has no 依据 button.
@Component
export struct AnswerActionsView {
  @Consume('env') env: AppEnv;
  @Prop content: string = '';
  @Prop citations: LawCitation[] = [];
  @Prop report: boolean = false;
  actions: ChatActions = new ChatActions();

  @Builder
  private CopyButton(res: Resource, label: string, primary: boolean) {
    Row({ space: 5 }) {
      ChatIcon({ res: res, size: 13, color: primary ? this.env.cx.gold : this.env.cx.muted })
      Text(label)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(primary ? this.env.cx.gold : this.env.cx.muted)
    }
    .height(30)
    .padding({ left: 11, right: 12 })
    .borderRadius(15)
    .backgroundColor(primary ? chipBg(this.env) : this.env.cx.tint)
    .accessibilityText(label)
    .onClick(() => {
      copyAnswer(this.getUIContext(), this.content, this.citations, !primary);
    })
  }

  build() {
    Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
      this.CopyButton($r('app.media.ic_copy'), '复制', true)
      if (CitationText.usedCitationCount(this.content, this.citations.length) > 0) {
        this.CopyButton($r('app.media.ic_book'), '复制含依据', false)
      }
      if (EvidenceExtractor.checklist(this.content).length > 0) {
        Row({ space: 5 }) {
          ChatIcon({ res: $r('app.media.ic_folder'), size: 13, color: this.env.cx.onGold })
          Text('对照证据库')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.env.cx.onGold)
        }
        .height(30)
        .padding({ left: 11, right: 12 })
        .borderRadius(15)
        .backgroundColor(this.env.cx.gold)
        .accessibilityText('对照证据库')
        .onClick(() => {
          this.actions.openChecklist(this.content);
        })
      }
      if (!this.report && this.citations.length > 0) {
        Row({ space: 5 }) {
          ChatIcon({ res: $r('app.media.ic_book'), size: 13, color: this.env.cx.brand })
          Text('依据 ' + this.citations.length.toString() + ' 条')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.env.cx.brand)
        }
        .height(30)
        .padding({ left: 11, right: 12 })
        .borderRadius(15)
        .backgroundColor(this.env.cx.tint)
        .accessibilityText('查看本轮检索依据')
        .onClick(() => {
          this.actions.openCitations(this.citations);
        })
      }
    }
    .width('100%')
  }
}

export interface ChipParams {
  label: string;
  env: AppEnv;
  action: () => void;
}

@Builder
function ReasoningChip(p: ChipParams) {
  Row({ space: 4 }) {
    Text(p.label + ' ›')
      .fontSize(11.5)
      .fontWeight(FontWeight.Medium)
      .fontColor(p.env.cx.gold)
  }
  .padding({ left: 10, right: 10, top: 5, bottom: 5 })
  .backgroundColor(chipBg(p.env))
  .borderRadius(999)
  .accessibilityText('展开思考过程')
  .onClick(() => {
    p.action();
  })
}

export interface ReasoningTextParams {
  text: string;
  env: AppEnv;
}

// Plain text on purpose: citation IDs here are not validated, so they are
// not turned into tappable chips. The gold rule is a left border on the text
// itself; a separate full-height bar inside a Scroll stretches to the viewport.
@Builder
function ReasoningText(p: ReasoningTextParams) {
  Text(p.text)
    .fontSize(12.5)
    .lineHeight(20)
    .fontColor(p.env.cx.muted)
    .width('100%')
    .padding({ left: 9 })
    .border({ width: { left: 2 }, color: p.env.isDark ? '#6B5A2E' : '#D9C08A' })
    .copyOption(CopyOptions.LocalDevice)
    .selectedBackgroundColor(p.env.cx.selection)
    .caretColor(p.env.cx.gold)
}

// One message of a conversation: the user's bubble, or an answer laid flat
// with its saved reasoning and actions.
@Component
export struct MessageView {
  @Consume('env') env: AppEnv;
  message: ChatMessage = new ChatMessage(ChatRole.USER, '');
  actions: ChatActions = new ChatActions();
  @State showReasoning: boolean = false;

  @Builder
  private SavedReasoning() {
    Column() {
      if (this.showReasoning) {
        Column({ space: 8 }) {
          Row() {
            Text('已思考 ' + ConversationText.thinkLabel(this.message.thinkMs))
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.env.cx.gold)
            Blank()
            Text('收起')
              .fontSize(11.5)
              .fontColor(this.env.cx.faint)
              .padding({ left: 8, top: 2, bottom: 2 })
              .onClick(() => {
                this.showReasoning = false;
              })
          }
          .width('100%')
          ReasoningText({ text: this.message.reasoning, env: this.env })
          Text('思考过程由模型生成，未经引用校验，可能包含推测，请以正式回答为准。')
            .fontSize(10.5)
            .lineHeight(16)
            .fontColor(this.env.cx.faint)
            .width('100%')
        }
        .width('100%')
        .padding(11)
        .backgroundColor(this.env.cx.surface2)
        .borderRadius(14)
        .border({ width: 1, color: reasoningBorder(this.env) })
      } else {
        ReasoningChip({
          label: '已思考 ' + ConversationText.thinkLabel(this.message.thinkMs),
          env: this.env,
          action: () => {
            this.showReasoning = true;
          }
        })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column({ space: 10 }) {
      if (this.message.role === ChatRole.USER) {
        Row() {
          Blank()
          Text(this.message.content)
            .fontSize(15)
            .lineHeight(24)
            .fontColor(this.env.cx.onBrand)
            .constraintSize({ maxWidth: '84%' })
            .copyOption(CopyOptions.LocalDevice)
            .caretColor(this.env.cx.gold)
            .selectedBackgroundColor(this.env.isDark ? '#4D08111F' : '#59FFFFFF')
            .onTextSelectionChange((start: number, end: number) => {
              this.actions.selecting(start !== end);
            })
            .padding({ left: 14, right: 14, top: 11, bottom: 11 })
            .backgroundColor(this.env.cx.brand)
            .borderRadius({ topLeft: 18, topRight: 6, bottomLeft: 18, bottomRight: 18 })
        }
        .width('100%')
      } else {
        if (this.env.showReasoning && this.message.reasoning.length > 0) {
          this.SavedReasoning()
        }
        AnswerText({ content: this.message.content, citations: this.message.citations, actions: this.actions })
        AnswerActionsView({ content: this.message.content, citations: this.message.citations, actions: this.actions })
      }
    }
    .width('100%')
    .transition(TransitionEffect.OPACITY.animation({ duration: this.env.reduceMotion ? 0 : 160 }))
  }
}

// The reply streaming in: the live reasoning panel, which folds into a chip
// once the answer starts, and the answer so far.
@Component
export struct StreamingView {
  @Consume('env') env: AppEnv;
  @ObjectLink chat: ChatSession;
  actions: ChatActions = new ChatActions();
  @State open: boolean = true;

  aboutToAppear(): void {
    this.open = this.env.autoExpandReasoning;
  }

  private liveReasoning(): string {
    const text: string = this.chat.reasoning;
    return text.length > LIVE_REASONING_CHARS ? '…' + text.substring(text.length - LIVE_REASONING_CHARS) : text;
  }

  @Builder
  private LiveReasoning() {
    if (this.chat.streaming.length > 0 && !this.open) {
      ReasoningChip({
        label: '已思考 ' + (this.chat.thinkSeconds > 0 ? this.chat.thinkSeconds.toString() + ' 秒' : ''),
        env: this.env,
        action: () => {
          this.open = true;
        }
      })
    } else {
      Column({ space: 8 }) {
        Row({ space: 6 }) {
          if (this.chat.streaming.length === 0) {
            LoadingProgress()
              .width(14)
              .height(14)
              .color(this.env.cx.gold)
          }
          Text((this.chat.streaming.length === 0 ? '正在思考' : '已思考') + ' · ' +
            this.chat.thinkSeconds.toString() + ' 秒')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.env.cx.gold)
          Blank()
          Text(this.open ? '收起' : '展开')
            .fontSize(11.5)
            .fontColor(this.env.cx.faint)
            .padding({ left: 8, top: 2, bottom: 2 })
            .onClick(() => {
              this.open = !this.open;
            })
        }
        .width('100%')
        if (this.open) {
          ReasoningText({ text: this.liveReasoning(), env: this.env })
        }
      }
      .width('100%')
      .padding(11)
      .backgroundColor(this.env.cx.surface2)
      .borderRadius(14)
      .border({ width: 1, color: reasoningBorder(this.env) })
    }
  }

  build() {
    Column({ space: 10 }) {
      if (this.env.showReasoning && this.chat.reasoning.length > 0) {
        this.LiveReasoning()
      }
      if (this.chat.streaming.length > 0) {
        AnswerText({
          content: this.chat.streaming,
          citations: this.chat.streamCitations,
          selectable: false,
          actions: this.actions
        })
      }
    }
    .width('100%')
  }
}

// The composer pinned above the tab bar (or the keyboard): attachment, text,
// the 本地法规检索 mark, and send or stop.
@Component
export struct PinnedComposer {
  @Consume('env') env: AppEnv;
  @ObjectLink chat: ChatSession;
  @Prop forCase: boolean = false;
  @Prop placeholder: string = '';
  @Prop picking: boolean = false;
  controller: TextAreaController = new TextAreaController();
  actions: ChatActions = new ChatActions();

  build() {
    Column() {
      Column()
        .width('100%')
        .height(22)
        .linearGradient({
          angle: 180,
          colors: [['#00' + this.env.cx.bgBottom.substring(1), 0.0], [this.env.cx.bgBottom, 1.0]]
        })
        .hitTestBehavior(HitTestMode.Transparent)
      Column() {
        if (this.chat.attachment.name.length > 0) {
          AttachmentRow({
            attachment: this.chat.attachment,
            cx: this.env.cx,
            onRemove: () => {
              this.chat.attachment = new FileAttachment();
            }
          })
        }
        if (this.chat.attachmentError.length > 0) {
          AttachmentErrorRow({ message: this.chat.attachmentError, cx: this.env.cx })
        }
        Row({ space: 6 }) {
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            ChatIcon({ res: $r('app.media.ic_plus'), size: 17, color: this.env.cx.gold })
          }
          .width(36)
          .height(36)
          .backgroundColor(this.env.cx.surface2)
          .accessibilityText(this.forCase ? '添加案件材料' : '添加附件')
          .enabled(!this.picking && !this.chat.sending)
          .onClick(() => {
            this.actions.attach(this.forCase);
          })
          TextArea({ text: this.chat.input, placeholder: this.placeholder, controller: this.controller })
            .layoutWeight(1)
            .constraintSize({ minHeight: 38, maxHeight: 100 })
            .fontSize(15)
            .fontColor(this.env.cx.text)
            .placeholderColor(this.env.cx.placeholder)
            .caretColor(this.env.cx.gold)
            .selectedBackgroundColor(this.env.cx.selection)
            .backgroundColor(Color.Transparent)
            .borderWidth(0)
            .padding({ left: 4, right: 4, top: 8, bottom: 8 })
            .onChange((value: string) => {
              this.chat.input = value;
            })
          // 本地法规检索 is always on; a small mark keeps that visible.
          Column() {
            ChatIcon({ res: $r('app.media.ic_book'), size: 14, color: this.env.cx.ok })
          }
          .margin({ bottom: 11 })
          if (this.chat.sending) {
            Button({ type: ButtonType.Circle, stateEffect: true }) {
              ChatIcon({ res: $r('app.media.ic_stop'), size: 18, color: this.env.cx.onGold })
            }
            .width(36)
            .height(36)
            .backgroundColor(this.env.cx.gold)
            .accessibilityText('停止生成')
            .onClick(() => {
              this.actions.stop(this.forCase);
            })
          } else {
            Button({ type: ButtonType.Circle, stateEffect: true }) {
              ChatIcon({ res: $r('app.media.ic_send'), size: 17, color: this.env.cx.onGold })
            }
            .width(36)
            .height(36)
            .backgroundColor(this.chat.canSend() ? this.env.cx.gold : this.env.cx.surface2)
            .enabled(this.chat.canSend())
            .accessibilityText('发送')
            .onClick(() => {
              this.actions.send(this.forCase);
            })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Bottom)
        .padding(4)
        .backgroundColor(this.env.cx.surface)
        .borderRadius(24)
        .border({ width: 1, color: this.env.cx.line })
        .shadow({ radius: 14, color: this.env.cx.softShadow, offsetY: 4 })
        Text('AI 内容仅供参考，重要决定请核对最新法规或咨询专业人士')
          .fontSize(9)
          .fontColor(this.env.cx.muted)
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: 5 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: this.env.keyboardVisible ? 8 : TAB_BAR_CLEARANCE })
      .backgroundColor(this.env.cx.bgBottom)
    }
    .width('100%')
    .onAreaChange((oldValue: Area, newValue: Area) => {
      this.chat.pinnedHeight = newValue.height as number;
    })
  }
}

export interface AskFabParams {
  label: string;
  cx: ThemeColors;
  onOpen: () => void;
}

// The composer folded while reading, in 普法, 维权 and 合同 alike.
@Builder
export function AskFab(p: AskFabParams) {
  Text('✦ ' + p.label)
    .fontSize(13)
    .fontColor(p.cx.onGold)
    .height(FAB_HEIGHT)
    .padding({ left: 15, right: 15 })
    .backgroundColor(p.cx.gold)
    .borderRadius(FAB_HEIGHT / 2)
    .shadow({ radius: 10, color: p.cx.softShadow, offsetY: 3 })
    .margin({ right: 18, bottom: READING_FAB_BOTTOM })
    .accessibilityText('展开输入框')
    .onClick(() => {
      p.onOpen();
    })
}

// ↓ to the latest message, shown when it is far below.
@Component
export struct JumpButton {
  @Consume('env') env: AppEnv;
  @ObjectLink chat: ChatSession;
  scroller: Scroller = new Scroller();

  build() {
    Button({ type: ButtonType.Circle, stateEffect: true }) {
      ChatIcon({ res: $r('app.media.ic_arrow_down'), size: 18, color: this.env.cx.text })
    }
    .width(38)
    .height(38)
    .backgroundColor(this.env.cx.surface)
    .border({ width: 1, color: this.env.cx.line })
    .shadow({ radius: 10, color: this.env.cx.softShadow, offsetY: 3 })
    .accessibilityText('回到最新')
    .margin({ right: 18, bottom: this.chat.reading ? READING_FAB_BOTTOM + FAB_HEIGHT + 10 : this.chat.pinnedHeight + 10 })
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.8, y: 0.8 }))
      .animation({ duration: this.env.reduceMotion ? 0 : 160 }))
    .onClick(() => {
      // The latest message is where a reply starts, so the composer comes back.
      // Unfolding grows the bottom room, so scroll once that is laid out.
      if (this.chat.reading) {
        this.getUIContext().animateTo({ duration: this.env.reduceMotion ? 0 : 200, curve: Curve.EaseOut }, () => {
          this.chat.reading = false;
        });
      }
      setTimeout(() => {
        // No fling velocity: on a long conversation it can stop short of the end.
        this.scroller.scrollEdge(Edge.Bottom);
      }, 80);
    })
  }
}
