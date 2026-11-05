import { AppEnv } from '../models/AppEnv';
import { DEMO_STEP_COUNT, DEMO_STEPS, DemoStepText } from '../services/DemoScript';
import { LIGHT_BUTTON, pointLight } from '../theme/Light';

// The pieces of 引导式演示 on screen: the opening card, the step card that
// leads through the story, and the summary at the end.

export class DemoActions {
  start: () => void = () => {
  };
  browse: () => void = () => {
  };
  exit: () => void = () => {
  };
  fill: () => void = () => {
  };
  next: () => void = () => {
  };
  prev: () => void = () => {
  };
  useBackup: () => void = () => {
  };
  keepWaiting: () => void = () => {
  };
  restart: () => void = () => {
  };
  // After the summary: look back at the pages, or see the summary again.
  review: () => void = () => {
  };
  summary: () => void = () => {
  };
}

// What the summary reports.
export class DemoStats {
  liveCalls: number = 0;
  backups: number = 0;
  evidence: number = 0;
  progress: number = 0;
  seconds: number = 0;
}

// A button on the dark step card; a component so its label follows the step.
@Component
struct DemoButton {
  @Consume('env') env: AppEnv;
  @Prop label: string = '';
  @Prop primary: boolean = false;
  action: () => void = () => {
  };

  build() {
    Text(this.label)
      .fontSize(12.5)
      .fontWeight(this.primary ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.primary ? this.env.cx.onGold : '#DDE6F2')
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .backgroundColor(this.primary ? this.env.cx.gold : Color.Transparent)
      .border({ width: this.primary ? 0 : 1, color: '#59FFFFFF' })
      .borderRadius(999)
      .onClick(() => {
        this.action();
      })
  }
}

@Component
export struct DemoStepCard {
  @Consume('env') env: AppEnv;
  @Prop step: number = 1;
  @Prop done: boolean = false;
  // The model has been quiet too long: offer the backup.
  @Prop slow: boolean = false;
  @Prop hasBackup: boolean = false;
  // The step's call is under way.
  @Prop busy: boolean = false;
  // After the summary: the story is done and the pages are there to look back at.
  @Prop review: boolean = false;
  // Where the presenter dragged the card, and whether it is shrunk to a pill;
  // the page keeps these so they last from step to step.
  @Link offsetX: number;
  @Link offsetY: number;
  @Link collapsed: boolean;
  actions: DemoActions = new DemoActions();
  private dragStartX: number = 0;
  private dragStartY: number = 0;

  private text(): DemoStepText {
    return DEMO_STEPS[Math.max(0, Math.min(DEMO_STEP_COUNT, this.step) - 1)];
  }

  private title(): string {
    return this.review ? '演示已完成' : this.text().title;
  }

  private badge(): string {
    if (this.review) {
      return '✓';
    }
    return (this.done ? '✓ ' : '') + this.step.toString() + ' / ' + DEMO_STEP_COUNT.toString();
  }

  private body(): string {
    if (this.review) {
      return '切换页签回看刚才的对话、证据、卷宗、分析报告和合同审查。';
    }
    if (this.slow) {
      return '模型响应较慢，' + (this.hasBackup ? '可以继续等待，也可以使用事先真实调用生成的备用结果。' : '请稍候。');
    }
    if (this.done) {
      return '✓ ' + this.text().done;
    }
    return this.busy ? '正在实时调用模型，回答会逐字出现…' : this.text().body;
  }

  @Builder
  private Badge() {
    Text(this.badge())
      .fontSize(11)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.env.cx.onGold)
      .padding({ left: 7, right: 7, top: 2, bottom: 2 })
      .backgroundColor(this.done || this.review ? this.env.cx.ok : this.env.cx.gold)
      .borderRadius(6)
  }

  // Shrunk: a pill with the step; a tap opens it again.
  @Builder
  private Pill() {
    Row({ space: 8 }) {
      this.Badge()
      Text(this.title())
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
      if (this.slow && this.hasBackup) {
        Text('!')
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.env.cx.onGold)
          .textAlign(TextAlign.Center)
          .width(18)
          .height(18)
          .borderRadius(9)
          .backgroundColor(this.env.cx.gold)
      }
      Text('⌄')
        .fontSize(14)
        .fontColor('#9FB2CC')
    }
    .padding({ left: 10, right: 12, top: 8, bottom: 8 })
    .onClick(() => {
      this.collapsed = false;
    })
  }

  @Builder
  private Full() {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        this.Badge()
        Text(this.title())
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
        Text(this.review ? '' : this.text().page)
          .fontSize(11)
          .fontColor('#9FB2CC')
          .layoutWeight(1)
        Text('缩小')
          .fontSize(11.5)
          .fontColor('#9FB2CC')
          .padding({ left: 4, top: 4, bottom: 4 })
          .onClick(() => {
            this.collapsed = true;
          })
        Text('退出')
          .fontSize(11.5)
          .fontColor('#9FB2CC')
          .padding({ left: 4, top: 4, bottom: 4 })
          .onClick(() => {
            this.actions.exit();
          })
      }
      .width('100%')
      Row({ space: 3 }) {
        ForEach([1, 2, 3, 4, 5], (i: number) => {
          Row()
            .layoutWeight(1)
            .height(3)
            .borderRadius(2)
            .backgroundColor(this.review || i < this.step || (i === this.step && this.done) ? this.env.cx.glow :
              (i === this.step ? '#80E0B45C' : '#38FFFFFF'))
        }, (i: number) => i.toString())
      }
      .width('100%')
      Text(this.body())
        .fontSize(12.5)
        .lineHeight(19)
        .fontColor(this.done && !this.slow && !this.review ? '#B5E6CF' : '#DDE6F2')
        .width('100%')
      Row({ space: 8 }) {
        if (this.review) {
          Blank()
          DemoButton({
            label: '查看总结',
            primary: false,
            action: () => {
              this.actions.summary();
            }
          })
          DemoButton({
            label: '退出演示',
            primary: true,
            action: () => {
              this.actions.exit();
            }
          })
        } else if (this.slow && this.hasBackup) {
          DemoButton({
            label: '继续等待',
            primary: false,
            action: () => {
              this.actions.keepWaiting();
            }
          })
          DemoButton({
            label: '使用备用结果',
            primary: true,
            action: () => {
              this.actions.useBackup();
            }
          })
        } else if (this.busy) {
          Blank()
        } else if (this.done) {
          if (this.step > 1) {
            DemoButton({
              label: '上一步',
              primary: false,
              action: () => {
                this.actions.prev();
              }
            })
          }
          Blank()
          DemoButton({
            label: this.step < DEMO_STEP_COUNT ? '下一步' : '完成演示',
            primary: true,
            action: () => {
              this.actions.next();
            }
          })
        } else {
          DemoButton({
            label: this.text().fill,
            primary: true,
            action: () => {
              this.actions.fill();
            }
          })
          Blank()
          if (this.step > 1) {
            DemoButton({
              label: '上一步',
              primary: false,
              action: () => {
                this.actions.prev();
              }
            })
          }
          DemoButton({
            label: '跳过',
            primary: false,
            action: () => {
              this.actions.next();
            }
          })
        }
      }
      .width('100%')
      .margin({ top: 2 })
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
  }

  build() {
    Column() {
      if (this.collapsed) {
        this.Pill()
      } else {
        this.Full()
      }
    }
    .width(this.collapsed ? undefined : '100%')
    .backgroundColor('#F216233A')
    .borderRadius(this.collapsed ? 999 : 16)
    // Stands out on a dark page too.
    .border({ width: 1, color: '#33FFFFFF' })
    .shadow({ radius: 16, color: '#40000000', offsetY: 5 })
    .constraintSize({ maxWidth: 460 })
    .translate({ x: this.offsetX, y: this.offsetY })
    // Dragged anywhere on the card; taps still reach its buttons.
    .gesture(
      PanGesture({ distance: 6 })
        .onActionStart(() => {
          this.dragStartX = this.offsetX;
          this.dragStartY = this.offsetY;
        })
        .onActionUpdate((event: GestureEvent) => {
          this.offsetX = this.dragStartX + event.offsetX;
          this.offsetY = this.dragStartY + event.offsetY;
        })
    )
  }
}

// Full-screen cards on the brand gradient: the opening and the summary.
@Component
export struct DemoCover {
  @Consume('env') env: AppEnv;
  @Prop statusBarHeight: number = 40;
  // The summary, rather than the opening.
  @Prop summary: boolean = false;
  @Prop stats: DemoStats = new DemoStats();
  // Requests on the built-in service left today, or -1 for the user's own.
  @Prop callsLeft: number = -1;
  actions: DemoActions = new DemoActions();

  @Builder
  private Line(text: string) {
    Text(text)
      .fontSize(13.5)
      .lineHeight(22)
      .fontColor(this.env.cx.headerText)
      .width('100%')
  }

  @Builder
  private Action(label: string, primary: boolean, action: () => void) {
    Text(label)
      .fontSize(15.5)
      .fontWeight(FontWeight.Medium)
      .fontColor(primary ? this.env.cx.onGold : this.env.cx.headerText)
      .textAlign(TextAlign.Center)
      .width('100%')
      .height(48)
      .borderRadius(24)
      .backgroundColor(primary ? this.env.cx.gold : Color.Transparent)
      .border({ width: primary ? 0 : 1, color: '#66FFFFFF' })
      .visualEffect(primary ? pointLight(LIGHT_BUTTON, this.env.isDark, this.env.cx) : undefined)
      .onClick(action)
  }

  @Builder
  private Opening() {
    Text('引导式演示')
      .fontSize(12)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.env.cx.onGold)
      .padding({ left: 9, right: 9, top: 3, bottom: 3 })
      .backgroundColor(this.env.cx.gold)
      .borderRadius(8)
    Text('张三的维权故事')
      .fontSize(28)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.env.cx.headerText)
      .margin({ top: 14 })
    Text('销售员张三被公司口头辞退，没有加班费，也没交社保。跟着五步，看应用怎样帮他从咨询走到维权。')
      .fontSize(14)
      .lineHeight(22)
      .fontColor(this.env.cx.headerSub)
      .margin({ top: 10, bottom: 16 })
    Column({ space: 2 }) {
      ForEach(['1  普法咨询', '2  梳理案件', '3  整理证据', '4  生成分析报告', '5  合同体检'], (line: string) => {
        this.Line(line)
      }, (line: string) => line)
    }
    .width('100%')
    .padding(14)
    .backgroundColor('#24FFFFFF')
    .borderRadius(16)
    Text('约 5 分钟 · 调用模型 4 次 · 人物和公司均为虚构' +
      (this.callsLeft >= 0 && this.callsLeft < 4 ? '\n今日内置服务次数不足，部分步骤将使用备用结果' : ''))
      .fontSize(12)
      .lineHeight(18)
      .fontColor(this.env.cx.headerSub)
      .margin({ top: 12 })
  }

  @Builder
  private Summary() {
    Text('✓')
      .fontSize(36)
      .fontColor(this.env.cx.glow)
    Text('演示完成')
      .fontSize(28)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.env.cx.headerText)
      .margin({ top: 8, bottom: 16 })
    Column({ space: 2 }) {
      this.Line('实时调用模型 ' + this.stats.liveCalls.toString() + ' 次 · 备用结果 ' + this.stats.backups.toString() + ' 次')
      this.Line('本机识别证据 ' + this.stats.evidence.toString() + ' 份')
      this.Line('卷宗完整度 ' + this.stats.progress.toString() + '%')
      this.Line('用时 ' + Math.floor(this.stats.seconds / 60).toString() + ' 分 ' + (this.stats.seconds % 60).toString() + ' 秒')
    }
    .width('100%')
    .padding(14)
    .backgroundColor('#24FFFFFF')
    .borderRadius(16)
  }

  build() {
    Column() {
    Column() {
      Blank()
      Column() {
        if (this.summary) {
          this.Summary()
        } else {
          this.Opening()
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      Blank()
      Column({ space: 10 }) {
        if (this.summary) {
          this.Action('回看演示内容', false, () => {
            this.actions.review();
          })
          this.Action('再演示一遍', false, () => {
            this.actions.restart();
          })
          this.Action('退出演示', true, () => {
            this.actions.exit();
          })
        } else {
          this.Action('开始演示', true, () => {
            this.actions.start();
          })
          this.Action('直接查看示例结果', false, () => {
            this.actions.browse();
          })
          Text('退出演示模式')
            .fontSize(13)
            .fontColor(this.env.cx.headerSub)
            .padding(6)
            .onClick(() => {
              this.actions.exit();
            })
        }
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24, top: this.statusBarHeight + 24, bottom: 36 })
    // On a tablet the content keeps to a column in the middle.
    .constraintSize({ maxWidth: 560 })
    }
    .width('100%')
    .height('100%')
    .linearGradient({
      angle: 160,
      colors: [[this.env.cx.headerA, 0.0], [this.env.cx.headerB, 0.62], [this.env.cx.headerC, 1.0]]
    })
    .onClick(() => {
    })
  }
}
