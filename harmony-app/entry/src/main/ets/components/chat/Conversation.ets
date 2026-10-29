import { AppEnv } from '../../models/AppEnv';
import { ChatMessage, ChatRole } from '../../models/AppModels';
import { ChatSession } from '../../models/ChatSession';
import { Material } from '../../theme/Material';
import { SCROLLED_PAST } from '../BrandBar';
import {
  AskFab,
  ChatActions,
  ErrorNotice,
  JumpButton,
  MessageView,
  PinnedComposer,
  READING_FAB_BOTTOM,
  SendingRow,
  StreamingView
} from './ChatViews';

// A 普法 or 维权 conversation: its lead content, the messages with the latest
// turn laid out on its own, the composer pinned at the bottom and the jump
// to the latest message. The page keeps the scroller so it can bring a new
// question to the top.

// Bottom room on the 普法 home, which has no pinned composer.
const CONTENT_BOTTOM: number = 128;
// Show the jump-to-latest button once the latest content is this far below.
const JUMP_BUTTON_DISTANCE: number = 240;
// Bottom room while reading: enough to clear the folded composer.
const READING_BOTTOM: number = READING_FAB_BOTTOM + 54;
// A downward drag this long starts reading.
const READING_DRAG: number = 24;
// A tap this soon after the list moved stops a fling rather than reveals.
export const SCROLL_SETTLE_MS: number = 200;

// What the conversation tells the page beyond ChatActions.
export class ConversationEvents {
  // ErrorNotice's 去「我的」.
  openSettings: () => void = () => {
  };
  // ErrorNotice's 只看法条, or undefined where it is not offered.
  lawsOnly: (() => void) | undefined = undefined;
  // A right swipe on 普法 pulls out the history drawer.
  swipeStart: () => void = () => {
  };
  swipeUpdate: (offsetX: number) => void = (offsetX: number) => {
  };
  swipeEnd: (offsetX: number, velocityX: number) => void = (offsetX: number, velocityX: number) => {
  };
}

@Builder
function noLead() {
}

@Component
export struct Conversation {
  @Consume('env') env: AppEnv;
  @ObjectLink chat: ChatSession;
  // False on the 普法 home: only the lead shows, and no pinned composer.
  @Prop conversing: boolean = true;
  @Prop forCase: boolean = false;
  @Prop placeholder: string = '';
  @Prop sendingLabel: string = '';
  @Prop picking: boolean = false;
  // Only 普法 has the history drawer to swipe out.
  @Prop drawerSwipe: boolean = false;
  // The folded composer's label.
  @Prop askLabel: string = '';
  // How much taller the page gets while reading beyond the folded composer
  // (the 维权 case bar, the header still to collapse). A conversation needs
  // that much more to scroll, or it would fit and snap back to the top.
  @Prop readingRoom: number = 0;
  // A tap with every control shown hides them all (immersive reading); where
  // false, a tap only brings hidden controls back.
  @Prop tapToHide: boolean = false;
  // Scrolling down folds the composer and tab bar away (reading). Where false,
  // they stay while scrolling, and only a tap hides them.
  @Prop scrollToRead: boolean = true;
  // Room at the top for a title bar floating over the content.
  @Prop topInset: number = 0;
  @BuilderParam lead: () => void = noLead;
  // Ids for measuring where the latest turn sits in the scroll.
  scrollId: string = '';
  turnId: string = '';
  scroller: Scroller = new Scroller();
  controller: TextAreaController = new TextAreaController();
  actions: ChatActions = new ChatActions();
  events: ConversationEvents = new ConversationEvents();
  private downDrag: number = 0;
  // actions with taps on message text routed to this conversation; the page's
  // actions are shared by 普法 and 维权.
  private chatActions: ChatActions = new ChatActions();
  private lastMoved: number = 0;

  aboutToAppear(): void {
    const shared: ChatActions = this.actions;
    const own: ChatActions = new ChatActions();
    own.openCitation = shared.openCitation;
    own.openCitations = shared.openCitations;
    own.openChecklist = shared.openChecklist;
    own.selecting = shared.selecting;
    own.isSelecting = shared.isSelecting;
    own.send = shared.send;
    own.stop = shared.stop;
    own.attach = shared.attach;
    own.tapped = () => {
      this.revealOnTap();
    };
    this.chatActions = own;
  }

  // Index of the latest user message; that turn is laid out separately so it
  // can fill the viewport.
  private turnStart(): number {
    const messages: ChatMessage[] = this.chat.messages;
    for (let i: number = messages.length - 1; i >= 0; i--) {
      if (messages[i].role === ChatRole.USER) {
        return i;
      }
    }
    return 0;
  }

  // While anchored, the latest turn is at least a screen tall so its question
  // can scroll to the top.
  private turnMinHeight(): number {
    const chat: ChatSession = this.chat;
    return chat.anchorTurn ? Math.max(0, chat.viewportHeight - 14 - chat.pinnedHeight - 12) : 0;
  }

  private updateJump(): void {
    const chat: ChatSession = this.chat;
    const remaining: number = chat.contentHeight - chat.viewportHeight - this.scroller.currentOffset().yOffset;
    const show: boolean = chat.messages.length > 0 && remaining > JUMP_BUTTON_DISTANCE;
    if (show !== chat.showJump) {
      chat.showJump = show;
    }
  }

  private setReading(reading: boolean, immersive: boolean = false): void {
    if (reading === this.chat.reading && (reading && immersive) === this.chat.immersive) {
      return;
    }
    if (reading) {
      this.controller.stopEditing();
    }
    this.getUIContext().animateTo({ duration: this.env.reduceMotion ? 0 : 220, curve: Curve.EaseOut }, () => {
      this.chat.reading = reading;
      this.chat.immersive = reading && immersive;
    });
  }

  // Starts reading on a downward drag or fling. Scrolls the app makes (a new
  // question brought to the top, the jump to the latest) report Idle and do
  // not count. Reading ends only at the top or from the folded composer:
  // unfolding on any upward scroll would shrink the page, scroll it, and fold
  // it again. Near the top nothing counts: a fling past the top springs back
  // down, and that rebound would fold the page again just after it unfolded.
  private trackReading(delta: number, state: ScrollState): void {
    if (!this.scrollToRead || state === ScrollState.Idle || !this.conversing || this.chat.reading ||
      this.env.keyboardVisible || this.scroller.currentOffset().yOffset < READING_DRAG) {
      this.downDrag = 0;
      return;
    }
    this.downDrag = delta > 0 ? this.downDrag + delta : 0;
    const room: number = this.readingRoom + this.chat.pinnedHeight - READING_BOTTOM;
    if (this.downDrag > READING_DRAG && this.chat.contentHeight - this.chat.viewportHeight >= room) {
      this.setReading(true);
    }
  }

  // While reading, a tap on the conversation (not on a chip, button or
  // selected text, which handle their own taps) brings the controls back.
  private revealOnTap(): void {
    if (this.actions.isSelecting() || Date.now() - this.lastMoved < SCROLL_SETTLE_MS) {
      return;
    }
    if (this.chat.reading) {
      this.setReading(false);
    } else if (this.tapToHide && this.conversing) {
      this.setReading(true, true);
    }
  }

  @Builder
  private Turn() {
    if (this.chat.sending) {
      if (this.chat.streaming.length > 0 || (this.env.showReasoning && this.chat.reasoning.length > 0)) {
        StreamingView({ chat: this.chat, actions: this.chatActions })
      } else {
        SendingRow({ label: this.sendingLabel, cx: this.env.cx })
      }
    }
    if (this.chat.error.length > 0) {
      ErrorNotice({
        message: this.chat.error,
        cx: this.env.cx,
        onSettings: () => {
          this.events.openSettings();
        },
        onLawsOnly: this.events.lawsOnly
      })
    }
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Scroll(this.scroller) {
        Column({ space: 14 }) {
          this.lead()
          if (this.conversing) {
            Column({ space: 10 }) {
              ForEach(this.chat.messages.slice(0, this.turnStart()), (message: ChatMessage) => {
                MessageView({ message: message, actions: this.chatActions })
              })
              Column({ space: 10 }) {
                ForEach(this.chat.messages.slice(this.turnStart()), (message: ChatMessage) => {
                  MessageView({ message: message, actions: this.chatActions })
                })
                this.Turn()
              }
              .id(this.turnId)
              .width('100%')
              .constraintSize({ minHeight: this.turnMinHeight() })
            }
            .width('100%')
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 14 + this.topInset,
          bottom: !this.conversing ? CONTENT_BOTTOM : this.chat.reading ? READING_BOTTOM : this.chat.pinnedHeight + 12 })
        .onAreaChange((oldValue: Area, newValue: Area) => {
          this.chat.contentHeight = newValue.height as number;
          this.updateJump();
        })
        .onClick(() => {
          this.revealOnTap();
        })
      }
      .id(this.scrollId)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .width('100%')
      .height('100%')
      .edgeEffect(EdgeEffect.Spring)
      .onAreaChange((oldValue: Area, newValue: Area) => {
        this.chat.viewportHeight = newValue.height as number;
      })
      .onDidScroll((xOffset: number, yOffset: number, state: ScrollState) => {
        this.updateJump();
        this.trackReading(yOffset, state);
        const scrolled: boolean = this.scroller.currentOffset().yOffset > SCROLLED_PAST;
        if (this.chat.scrolled !== scrolled) {
          this.chat.scrolled = scrolled;
        }
        if (state !== ScrollState.Idle) {
          this.lastMoved = Date.now();
        }
      })
      .onReachStart(() => {
        this.setReading(false);
      })
      .onGestureJudgeBegin((info: GestureInfo) => {
        return info.isSystemGesture || this.drawerSwipe ? GestureJudgeResult.CONTINUE : GestureJudgeResult.REJECT;
      })
      .gesture(
        PanGesture({ direction: PanDirection.Right, distance: 12 })
          .onActionStart(() => {
            this.events.swipeStart();
          })
          .onActionUpdate((event: GestureEvent) => {
            this.events.swipeUpdate(event.offsetX);
          })
          .onActionEnd((event: GestureEvent) => {
            this.events.swipeEnd(event.offsetX, event.velocityX);
          })
          .onActionCancel(() => {
            this.events.swipeEnd(0, 0);
          })
      )
      if (this.conversing && this.chat.reading && !this.chat.immersive) {
        AskFab({
          label: this.askLabel,
          cx: this.env.cx,
          isDark: this.env.isDark,
          glass: Material.glass(this.env.lightLevel, this.env.reduceMotion),
          onOpen: () => {
            this.setReading(false);
          }
        })
      } else if (this.conversing && !this.chat.reading) {
        PinnedComposer({
          chat: this.chat,
          forCase: this.forCase,
          placeholder: this.placeholder,
          picking: this.picking,
          controller: this.controller,
          actions: this.chatActions
        })
      }
      if (this.conversing && this.chat.showJump) {
        JumpButton({ chat: this.chat, scroller: this.scroller })
      }
    }
    .width('100%')
    .height('100%')
  }
}
