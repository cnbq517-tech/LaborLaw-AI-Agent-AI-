import { AppEnv } from '../models/AppEnv';
import { MAX_QUICK_SESSIONS, QuickSession } from '../models/ChatState';
import { DRAWER_WIDTH, DrawerState } from '../models/DrawerState';
import { ConversationText, HistoryGroup } from '../services/ConversationText';
import { LIGHT_BUTTON, LIGHT_PANEL, pointLight } from '../theme/Light';
import { Material } from '../theme/Material';
import { ChatIcon } from './chat/ChatViews';

// 历史咨询: the saved 普法 conversations, grouped by day and searchable,
// sliding in over the 普法 page.

export class DrawerActions {
  close: () => void = () => {
  };
  startNew: () => void = () => {
  };
  open: (session: QuickSession) => void = (session: QuickSession) => {
  };
  remove: (id: string) => void = (id: string) => {
  };
}

@Component
export struct HistoryDrawer {
  @Consume('env') env: AppEnv;
  @ObjectLink @Watch('onDrawerChange') drawer: DrawerState;
  @Link sessions: QuickSession[];
  // The session the 普法 page shows, or '' on its home.
  @Prop activeId: string = '';
  // A reply is streaming in, so 新建咨询 waits.
  @Prop busy: boolean = false;
  actions: DrawerActions = new DrawerActions();
  @State pressedId: string = '';
  @State glowX: number = 0;
  @State glowY: number = 0;
  @State glowOn: boolean = false;
  private searchController: TextInputController = new TextInputController();

  private onDrawerChange(): void {
    if (!this.drawer.open) {
      this.searchController.stopEditing();
    }
  }

  // Lists only show the pressed state once they are sure the touch is not a
  // scroll, which can miss quick taps. Highlight on touch-down instead.
  private trackRowPress(id: string, event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      this.pressedId = id;
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.pressedId = '';
    }
  }

  // A soft light follows the finger across the drawer, like the floating tab
  // bar's light effect.
  private trackGlow(event: TouchEvent): void {
    if (event.touches.length === 0) {
      return;
    }
    const touch: TouchObject = event.touches[0];
    if (event.type === TouchType.Down) {
      this.glowX = touch.windowX;
      this.glowY = touch.windowY;
      this.getUIContext().animateTo({ duration: this.env.reduceMotion ? 0 : 140, curve: Curve.EaseOut }, () => {
        this.glowOn = true;
      });
    } else if (event.type === TouchType.Move) {
      this.glowX = touch.windowX;
      this.glowY = touch.windowY;
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.getUIContext().animateTo({ duration: this.env.reduceMotion ? 0 : 420, curve: Curve.EaseOut }, () => {
        this.glowOn = false;
      });
    }
  }

  private isActive(session: QuickSession): boolean {
    return session.id === this.activeId;
  }

  @Builder
  private DrawerGlow() {
    Column()
      .width(260)
      .height(260)
      .radialGradient({
        center: [130, 130],
        radius: 130,
        colors: [
          [this.env.isDark ? '#40E7BE6A' : '#33E8B85C', 0.0],
          [this.env.isDark ? '#14E7BE6A' : '#10E8B85C', 0.45],
          ['#00E7BE6A', 1.0]
        ]
      })
      .position({ x: this.glowX - 130, y: this.glowY - 130 })
      .opacity(this.glowOn ? 1 : 0)
      .scale({ x: this.glowOn ? 1 : 0.7, y: this.glowOn ? 1 : 0.7 })
      .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  private HistoryGroupHeader(label: string) {
    Text(label)
      .fontSize(11.5)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.env.cx.faint)
      .width('100%')
      .padding({ left: 10, top: 12, bottom: 6 })
  }

  @Builder
  private DrawerSessionRow(session: QuickSession) {
    if (this.isActive(session)) {
      Column({ space: 4 }) {
        this.DrawerSessionText(session)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .borderRadius(14)
      .backgroundColor(this.pressedId === session.id ? this.env.cx.surface2 : this.env.cx.tint)
      .border({ width: 1, color: this.env.isDark ? '#4DE0B45C' : '#40C0842A' })
      .onTouch((event: TouchEvent) => {
        this.trackRowPress(session.id, event);
      })
      .onClick(() => {
        this.actions.close();
      })
    } else {
      Column({ space: 4 }) {
        this.DrawerSessionText(session)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .borderRadius(14)
      .backgroundColor(this.pressedId === session.id ? this.env.cx.tint : Color.Transparent)
      .onTouch((event: TouchEvent) => {
        this.trackRowPress(session.id, event);
      })
      .onClick(() => {
        this.actions.open(session);
      })
    }
  }

  @Builder
  private DrawerSessionText(session: QuickSession) {
    Text(session.title)
      .fontSize(14)
      .fontWeight(this.isActive(session) ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.env.cx.text)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .width('100%')
    Text(ConversationText.sessionMeta(session))
      .fontSize(11)
      .fontColor(this.isActive(session) ? this.env.cx.goldDeep : this.env.cx.muted)
      .width('100%')
  }

  @Builder
  private DrawerDeleteAction(id: string) {
    Column() {
      Text('删除')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.env.cx.danger)
    }
    .width(72)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.env.cx.dangerBg)
    .borderRadius(14)
    .margin({ left: 6 })
    .onClick(() => {
      this.actions.remove(id);
    })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.env.isDark ? '#99040B18' : '#66404A5A')
        .opacity(this.drawer.open ? 1 + this.drawer.drag / DRAWER_WIDTH : 0)
        .accessibilityText('关闭历史咨询')
        .onClick(() => {
          this.actions.close();
        })

      Column() {
        Row() {
          Column({ space: 4 }) {
            Text('历史咨询')
              .fontSize(21)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.env.cx.text)
            Row()
              .width(28)
              .height(3)
              .backgroundColor(this.env.cx.glow)
              .borderRadius(2)
              .margin({ top: 4 })
          }
          .alignItems(HorizontalAlign.Start)
          Blank()
          Text(this.sessions.length.toString() + ' 段')
            .fontSize(11)
            .fontColor(this.env.cx.muted)
            .padding({ left: 9, right: 9, top: 4, bottom: 4 })
            .backgroundColor(this.env.cx.tint)
            .borderRadius(999)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
        .padding({ left: 20, right: 18 })

        Row({ space: 8 }) {
          ChatIcon({ res: $r('app.media.ic_search'), size: 16, color: this.env.cx.faint })
          TextInput({ text: this.drawer.query, placeholder: '搜索咨询记录', controller: this.searchController })
            .layoutWeight(1)
            .height(40)
            .fontSize(14)
            .fontColor(this.env.cx.text)
            .placeholderColor(this.env.cx.placeholder)
            .caretColor(this.env.cx.gold)
            .backgroundColor(Color.Transparent)
            .padding({ left: 0, right: 0 })
            .onChange((value: string) => {
              this.drawer.query = value;
            })
        }
        .height(42)
        .padding({ left: 13, right: 8 })
        .backgroundColor(this.env.cx.inputBg)
        .borderRadius(21)
        .border({ width: 1, color: this.env.cx.line })
        .margin({ left: 16, right: 16, top: 16 })

        Column() {
          Row({ space: 7 }) {
            ChatIcon({ res: $r('app.media.ic_compose'), size: 17, color: this.env.cx.onGold })
            Text('新建咨询')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.env.cx.onGold)
          }
        }
        .height(46)
        .alignSelf(ItemAlign.Stretch)
        .justifyContent(FlexAlign.Center)
        .borderRadius(15)
        .backgroundColor(this.env.cx.gold)
        .shadow({ radius: 16, color: this.env.cx.navShadow, offsetY: 4 })
        .visualEffect(pointLight(LIGHT_BUTTON, this.env.isDark, this.env.cx))
        .margin({ left: 16, right: 16, top: 12 })
        .opacity(this.busy ? 0.5 : 1)
        .accessibilityText('新建咨询')
        .onClick(() => {
          this.actions.startNew();
        })

        if (this.sessions.length === 0 || ConversationText.historyGroups(this.sessions, this.drawer.query).length === 0) {
          Column({ space: 8 }) {
            Column() {
              ChatIcon({ res: this.sessions.length === 0 ? $r('app.media.ic_clock') : $r('app.media.ic_search'), size: 22, color: this.env.cx.brand })
            }
            .width(48)
            .height(48)
            .justifyContent(FlexAlign.Center)
            .backgroundColor(this.env.cx.tint)
            .borderRadius(16)
            Text(this.sessions.length === 0 ? '还没有咨询记录' : '没有找到相关咨询')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.env.cx.text)
            Text(this.sessions.length === 0 ? '每次问答结束后会自动保存在这里' : '换个关键词试试')
              .fontSize(11.5)
              .fontColor(this.env.cx.muted)
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          List({ space: 4 }) {
            ForEach(ConversationText.historyGroups(this.sessions, this.drawer.query), (group: HistoryGroup) => {
              ListItemGroup({ header: this.HistoryGroupHeader(group.label) }) {
                ForEach(group.sessions, (session: QuickSession) => {
                  ListItem() {
                    this.DrawerSessionRow(session)
                  }
                  .swipeAction({
                    end: {
                      builder: () => {
                        this.DrawerDeleteAction(session.id)
                      }
                    }
                  })
                }, (session: QuickSession) => session.id + '_' + session.updatedAt.toString())
              }
            }, (group: HistoryGroup) => group.label + '_' + group.sessions.length.toString())
          }
          .layoutWeight(1)
          .width('100%')
          .padding({ left: 10, right: 10 })
          .margin({ top: 8 })
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
        }

        Row({ space: 6 }) {
          ChatIcon({ res: $r('app.media.ic_shield'), size: 12, color: this.env.cx.ok })
          Text('仅保存在本机 · ' + this.sessions.length.toString() + ' / '
            + MAX_QUICK_SESSIONS.toString() + ' 段')
            .fontSize(11)
            .fontColor(this.env.cx.muted)
          Blank()
          Text('左滑可删除')
            .fontSize(11)
            .fontColor(this.env.cx.faint)
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 12 })
        .border({ width: { top: 1 }, color: this.env.cx.line })
      }
      .width('84%')
      .constraintSize({ maxWidth: DRAWER_WIDTH })
      .height('100%')
      .padding({ top: 56, bottom: 30 })
      .borderRadius({ topRight: 26, bottomRight: 26 })
      .backgroundColor(this.env.isDark ? '#E60E1B30' : '#EBF7F9FC')
      .backgroundBlurStyle(BlurStyle.BACKGROUND_THICK, Material.blurOptions(this.env.isDark))
      .border({ width: { right: 1 }, color: this.env.cx.line })
      .shadow({ radius: 30, color: this.env.cx.softShadow, offsetX: 6 })
      .visualEffect(pointLight(LIGHT_PANEL, this.env.isDark, this.env.cx))
      .overlay(this.DrawerGlow())
      .onTouch((event: TouchEvent) => {
        this.trackGlow(event);
      })
      .translate({ x: this.drawer.open ? this.drawer.drag : -(DRAWER_WIDTH + 40) })
      .gesture(
        PanGesture({ direction: PanDirection.Horizontal, distance: 8 })
          .onActionUpdate((event: GestureEvent) => {
            this.drawer.drag = Math.min(0, event.offsetX);
          })
          .onActionEnd((event: GestureEvent) => {
            this.drawer.settle(this.getUIContext(), this.env.reduceMotion, event.velocityX);
          })
      )
    }
    .width('100%')
    .height('100%')
  }
}
