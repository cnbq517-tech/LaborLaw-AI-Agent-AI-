import { AppEnv } from '../models/AppEnv';
import { LIGHT_BUTTON, pointLight } from '../theme/Light';
import { ChatIcon } from './chat/ChatViews';

// The welcome pages a first-time user sees before the app: the brand, the
// three sections, then the model service and what stays on the device. Laid
// out on the 普法 header's gradient with its scale, so it reads as the app.

const PAGE_COUNT: number = 3;
// On a tablet the pages keep to a card this wide in the middle.
const CARD_MAX: number = 520;

export class OnboardingActions {
  finish: () => void = () => {
  };
  setBuiltin: (value: boolean) => void = (value: boolean) => {
  };
}

@Component
export struct Onboarding {
  @Consume('env') env: AppEnv;
  @Prop statusBarHeight: number = 40;
  actions: OnboardingActions = new OnboardingActions();
  @State page: number = 0;
  private swiper: SwiperController = new SwiperController();

  private next(): void {
    if (this.page < PAGE_COUNT - 1) {
      this.swiper.showNext();
    } else {
      this.actions.finish();
    }
  }

  @Builder
  private Feature(res: Resource, title: string, detail: string, bg: string, fg: string) {
    Row({ space: 12 }) {
      Column() {
        ChatIcon({ res: res, size: 20, color: fg })
      }
      .width(44)
      .height(44)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(bg)
      .borderRadius(14)
      Column({ space: 3 }) {
        Text(title)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.env.cx.headerText)
        Text(detail)
          .fontSize(12.5)
          .lineHeight(18)
          .fontColor(this.env.cx.headerSub)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding(14)
    .backgroundColor('#24FFFFFF')
    .borderRadius(18)
    .border({ width: 1, color: '#40FFFFFF' })
  }

  @Builder
  private Pledge(text: string) {
    Row({ space: 8 }) {
      ChatIcon({ res: $r('app.media.ic_shield'), size: 14, color: this.env.cx.glow })
      Text(text)
        .fontSize(12.5)
        .lineHeight(18)
        .fontColor(this.env.cx.headerText)
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  private ServiceSegment(builtin: boolean, label: string) {
    Text(label)
      .fontSize(13.5)
      .fontWeight(this.env.useBuiltin === builtin ? FontWeight.Bold : FontWeight.Regular)
      .fontColor(this.env.useBuiltin === builtin ? this.env.cx.headerA : this.env.cx.headerSub)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(34)
      .borderRadius(10)
      .backgroundColor(this.env.useBuiltin === builtin ? this.env.cx.headerText : Color.Transparent)
      .onClick(() => {
        this.actions.setBuiltin(builtin);
      })
  }

  @Builder
  private BrandPage() {
    Column() {
      Blank()
      Text('劳动法律 AI 智能体')
        .fontSize(30)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.env.cx.headerText)
      Text('懂法律，更懂你的难处')
        .fontSize(15)
        .fontColor(this.env.cx.headerSub)
        .margin({ top: 8 })
      Row()
        .width(40)
        .height(3)
        .backgroundColor(this.env.cx.glow)
        .borderRadius(2)
        .margin({ top: 16 })
      Text('遇到欠薪、辞退、合同问题，\n先问问它。')
        .fontSize(15)
        .lineHeight(24)
        .fontColor(this.env.cx.headerText)
        .margin({ top: 22 })
      Blank()
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .height('100%')
  }

  @Builder
  private FeaturesPage() {
    Column({ space: 12 }) {
      Blank()
      Text('三件事，帮你走完维权')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.env.cx.headerText)
        .margin({ bottom: 6 })
      this.Feature($r('app.media.ic_consult'), '普法', '问法律问题，答案附法条依据',
        this.env.cx.tint, this.env.cx.brand)
      this.Feature($r('app.media.ic_scale'), '维权', '像聊天一样说经过，自动整理卷宗；证据拍照即可识别',
        this.env.isDark ? '#2A2416' : '#F6EAD2', this.env.cx.gold)
      this.Feature($r('app.media.ic_shield'), '合同体检', '逐条标出风险条款和依据，审查在手机上完成',
        this.env.cx.okBg, this.env.cx.ok)
      Blank()
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .height('100%')
  }

  @Builder
  private PrivacyPage() {
    Column({ space: 12 }) {
      Blank()
      Text('隐私与模型服务')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.env.cx.headerText)
      Text('随时可以在「我的」里修改')
        .fontSize(13)
        .fontColor(this.env.cx.headerSub)
        .margin({ bottom: 4 })
      Column({ space: 10 }) {
        if (this.env.builtin !== undefined) {
          Row() {
            this.ServiceSegment(true, '内置服务')
            this.ServiceSegment(false, '自定义')
          }
          .width('100%')
          .padding(3)
          .backgroundColor('#2EFFFFFF')
          .borderRadius(12)
          Text(this.env.useBuiltin ? '无需配置，每天 100 次，开箱即用' : '使用你自己的模型服务，稍后在「我的」里填写')
            .fontSize(12.5)
            .lineHeight(18)
            .fontColor(this.env.cx.headerSub)
            .width('100%')
        } else {
          Text('在「我的」里填写你的模型服务后即可提问；法规检索和合同规则审查无需配置。')
            .fontSize(12.5)
            .lineHeight(18)
            .fontColor(this.env.cx.headerText)
            .width('100%')
        }
      }
      .width('100%')
      .padding(14)
      .backgroundColor('#24FFFFFF')
      .borderRadius(18)
      .border({ width: 1, color: '#40FFFFFF' })
      Column({ space: 10 }) {
        this.Pledge('法规检索、证据识别、合同规则审查都在本机完成')
        this.Pledge('对话、证据和审查报告只保存在本机')
        this.Pledge('只有你的提问会发给模型；合同中的姓名、身份证号等先替换成占位符')
      }
      .width('100%')
      .padding(14)
      .backgroundColor('#24FFFFFF')
      .borderRadius(18)
      .border({ width: 1, color: '#40FFFFFF' })
      Blank()
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .height('100%')
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Image($r('app.media.ic_scale'))
        .width(260)
        .height(260)
        .fillColor(this.env.cx.headerText)
        .opacity(0.08)
        .position({ top: this.statusBarHeight + 60, right: -60 })
      Column() {
        Row() {
          Blank()
          Text(this.page < PAGE_COUNT - 1 ? '跳过' : '')
            .fontSize(14)
            .fontColor(this.env.cx.headerSub)
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .onClick(() => {
              this.actions.finish();
            })
        }
        .width('100%')
        .height(52)
        Swiper(this.swiper) {
          this.BrandPage()
          this.FeaturesPage()
          this.PrivacyPage()
        }
        .index(this.page)
        .loop(false)
        .indicator(false)
        .layoutWeight(1)
        .width('100%')
        .onChange((index: number) => {
          this.page = index;
        })
        Row({ space: 6 }) {
          ForEach([0, 1, 2], (i: number) => {
            Row()
              .width(this.page === i ? 22 : 7)
              .height(7)
              .borderRadius(4)
              .backgroundColor(this.page === i ? this.env.cx.glow : '#59FFFFFF')
              .animation({ duration: this.env.reduceMotion ? 0 : 200, curve: Curve.EaseOut })
          }, (i: number) => i.toString())
        }
        .margin({ top: 12, bottom: 20 })
        Text(this.page < PAGE_COUNT - 1 ? '下一步' : '开始使用')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.env.cx.onGold)
          .textAlign(TextAlign.Center)
          .width('100%')
          .height(50)
          .borderRadius(25)
          .backgroundColor(this.env.cx.gold)
          .shadow({ radius: 16, color: this.env.cx.navShadow, offsetY: 4 })
          .visualEffect(pointLight(LIGHT_BUTTON, this.env.isDark, this.env.cx))
          .onClick(() => {
            this.next();
          })
      }
      .width('100%')
      .height('100%')
      .constraintSize({ maxWidth: CARD_MAX })
      .padding({ left: 24, right: 24, top: this.statusBarHeight, bottom: 36 })
    }
    .width('100%')
    .height('100%')
    .linearGradient({
      angle: 160,
      colors: [[this.env.cx.headerA, 0.0], [this.env.cx.headerB, 0.62], [this.env.cx.headerC, 1.0]]
    })
    // Swallows touches so the app under it waits.
    .onClick(() => {
    })
  }
}
