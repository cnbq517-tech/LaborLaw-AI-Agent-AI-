import { AppEnv } from '../models/AppEnv';
import { ChatIcon } from './chat/ChatViews';

// 我的, opened from the round button beside the tab bar: the model service,
// the local law index, what this phone keeps, reasoning display and
// appearance. Saving and clearing go back to the page through MineActions.

const CONTENT_BOTTOM: number = 128;

export class MineActions {
  close: () => void = () => {
  };
  test: () => void = () => {
  };
  clear: () => void = () => {
  };
  setTheme: (mode: number) => void = (mode: number) => {
  };
  saveShowReasoning: (value: boolean) => void = (value: boolean) => {
  };
  saveAutoExpand: (value: boolean) => void = (value: boolean) => {
  };
}

@Component
export struct MinePage {
  @Consume('env') env: AppEnv;
  @Prop connectionState: string = '';
  @Prop configBusy: boolean = false;
  @Prop documentCount: number = 0;
  @Prop searchableCount: number = 0;
  @Prop quickCount: number = 0;
  @Prop caseCount: number = 0;
  @Prop progress: number = 0;
  @Prop evidenceCount: number = 0;
  @Prop contractCount: number = 0;
  // A reply or report is being generated, so records cannot be cleared.
  @Prop busy: boolean = false;
  actions: MineActions = new MineActions();
  private baseUrlController: TextInputController = new TextInputController();
  private modelNameController: TextInputController = new TextInputController();
  private apiKeyController: TextInputController = new TextInputController();

  @Builder
  private SettingCardHeader(res: Resource, title: string) {
    Row({ space: 8 }) {
      Column() {
        ChatIcon({ res: res, size: 15, color: this.env.cx.brand })
      }
      .width(26)
      .height(26)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(this.env.cx.tint)
      .borderRadius(8)
      Text(title)
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.env.cx.text)
    }
    .width('100%')
  }

  @Builder
  private SettingsInput(label: string, value: string, placeholder: string, field: number) {
    Column() {
      Text(label)
        .fontSize(12)
        .fontColor(this.env.cx.muted)
        .width('100%')
        .margin({ bottom: 7 })
      if (field === 0) {
        TextInput({ text: value, placeholder: placeholder, controller: this.baseUrlController })
          .type(InputType.Normal)
          .height(46)
          .fontColor(this.env.cx.text)
          .placeholderColor(this.env.cx.placeholder)
          .caretColor(this.env.cx.gold)
          .selectedBackgroundColor(this.env.cx.selection)
          .backgroundColor(this.env.cx.surface2)
          .borderRadius(12)
          .border({ width: 1, color: this.env.cx.line })
          .onChange((v: string) => {
            this.env.baseUrl = v;
          })
      } else if (field === 1) {
        TextInput({ text: value, placeholder: placeholder, controller: this.modelNameController })
          .type(InputType.Normal)
          .height(46)
          .fontColor(this.env.cx.text)
          .placeholderColor(this.env.cx.placeholder)
          .caretColor(this.env.cx.gold)
          .selectedBackgroundColor(this.env.cx.selection)
          .backgroundColor(this.env.cx.surface2)
          .borderRadius(12)
          .border({ width: 1, color: this.env.cx.line })
          .onChange((v: string) => {
            this.env.modelName = v;
          })
      } else {
        TextInput({ text: value, placeholder: placeholder, controller: this.apiKeyController })
          .type(InputType.Password)
          .height(46)
          .fontColor(this.env.cx.text)
          .placeholderColor(this.env.cx.placeholder)
          .caretColor(this.env.cx.gold)
          .selectedBackgroundColor(this.env.cx.selection)
          .backgroundColor(this.env.cx.surface2)
          .borderRadius(12)
          .border({ width: 1, color: this.env.cx.line })
          .onChange((v: string) => {
            this.env.apiKey = v;
          })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private SettingRow(key: string, value: string) {
    Row() {
      Text(key)
        .fontSize(12.5)
        .fontColor(this.env.cx.muted)
      Blank()
      Text(value)
        .fontSize(12.5)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.env.cx.text)
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .border({ width: { top: 1 }, color: this.env.cx.line })
  }

  @Builder
  private ThemeSeg(label: string, mode: number) {
    Text(label)
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.env.themeMode === mode ? this.env.cx.onBrand : this.env.cx.muted)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(34)
      .borderRadius(9)
      .backgroundColor(this.env.themeMode === mode ? this.env.cx.brand : Color.Transparent)
      .onClick(() => {
        this.actions.setTheme(mode);
      })
  }

  @Builder
  private Settings() {
    Scroll() {
      Column({ space: 14 }) {
        Column({ space: 14 }) {
          this.SettingCardHeader($r('app.media.ic_gear'), '模型连接')
          this.SettingsInput('Base URL', this.env.baseUrl, 'https://…/v1', 0)
          this.SettingsInput('模型名称', this.env.modelName, '填写服务商提供的模型 ID', 1)
          this.SettingsInput('API Key', this.env.apiKey, '输入后将安全保存在本机', 2)
          Row({ space: 6 }) {
            ChatIcon({ res: $r('app.media.ic_shield'), size: 12, color: this.env.cx.ok })
            Text('API Key 使用 Asset Store 加密保存于本机，不写入代码或同步')
              .fontSize(10.5)
              .lineHeight(15)
              .fontColor(this.env.cx.muted)
              .layoutWeight(1)
          }
          .width('100%')
          Row() {
            Column() {
              Text('连接状态')
                .fontSize(11)
                .fontColor(this.env.cx.muted)
              Text(this.connectionState)
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.connectionState.includes('成功') ? this.env.cx.ok : this.env.cx.text)
                .margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Button('测试连接')
              .height(42)
              .fontSize(14)
              .fontColor(this.env.cx.onBrand)
              .backgroundColor(this.env.cx.brand)
              .borderRadius(13)
              .enabled(!this.configBusy)
              .onClick(() => {
                this.actions.test();
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .padding({ top: 4 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(16)
        .backgroundColor(this.env.cx.surface)
        .borderRadius(18)
        .border({ width: 1, color: this.env.cx.line })

        Column({ space: 10 }) {
          this.SettingCardHeader($r('app.media.ic_book'), '本地法规库')
          this.SettingRow('收录资料', this.documentCount > 0 ?
            this.documentCount.toString() + ' 份' : '加载中…')
          this.SettingRow('可检索文档', this.searchableCount > 0 ?
            this.searchableCount.toString() + ' 份' : '—')
          this.SettingRow('检索方式', '仅本地 · 不联网')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(16)
        .backgroundColor(this.env.cx.surface)
        .borderRadius(18)
        .border({ width: 1, color: this.env.cx.line })

        Column({ space: 10 }) {
          this.SettingCardHeader($r('app.media.ic_folder'), '本机记录')
          this.SettingRow('普法咨询', this.quickCount.toString() + ' 段历史')
          this.SettingRow('维权案件', this.caseCount.toString() + ' 个')
          this.SettingRow('卷宗完整度', this.progress.toString() + '%')
          this.SettingRow('证据库', this.evidenceCount.toString() + ' 份材料')
          this.SettingRow('合同审查', this.contractCount.toString() + ' 份报告')
          Text('以上记录仅保存在本机应用沙箱中，重新打开应用后会自动恢复。')
            .fontSize(10.5)
            .lineHeight(15)
            .fontColor(this.env.cx.muted)
            .width('100%')
          Button('清空本机记录')
            .width('100%')
            .height(42)
            .fontSize(14)
            .fontColor(this.env.cx.danger)
            .backgroundColor(this.env.cx.dangerBg)
            .borderRadius(13)
            .enabled(!this.busy)
            .onClick(() => {
              this.actions.clear();
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(16)
        .backgroundColor(this.env.cx.surface)
        .borderRadius(18)
        .border({ width: 1, color: this.env.cx.line })

        Column({ space: 12 }) {
          this.SettingCardHeader($r('app.media.ic_consult'), '思考过程')
          Row() {
            Column({ space: 3 }) {
              Text('显示思考过程')
                .fontSize(14)
                .fontColor(this.env.cx.text)
              Text('模型返回思考内容时，在回答上方显示')
                .fontSize(11)
                .fontColor(this.env.cx.muted)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.env.showReasoning })
              .selectedColor(this.env.cx.brand)
              .onChange((value: boolean) => {
                this.env.showReasoning = value;
                this.actions.saveShowReasoning(value);
              })
          }
          .width('100%')
          Row() {
            Column({ space: 3 }) {
              Text('思考中自动展开')
                .fontSize(14)
                .fontColor(this.env.showReasoning ? this.env.cx.text : this.env.cx.faint)
              Text('关闭后只显示「正在思考」，不展开内容')
                .fontSize(11)
                .fontColor(this.env.cx.muted)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.env.autoExpandReasoning })
              .selectedColor(this.env.cx.brand)
              .enabled(this.env.showReasoning)
              .onChange((value: boolean) => {
                this.env.autoExpandReasoning = value;
                this.actions.saveAutoExpand(value);
              })
          }
          .width('100%')
          Text('需要模型服务返回思考内容，例如 DeepSeek 等推理模型的 reasoning_content。不支持的服务不会显示，也不影响回答。')
            .fontSize(10.5)
            .lineHeight(16)
            .fontColor(this.env.cx.faint)
            .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(16)
        .backgroundColor(this.env.cx.surface)
        .borderRadius(18)
        .border({ width: 1, color: this.env.cx.line })

        Column({ space: 12 }) {
          this.SettingCardHeader($r('app.media.ic_theme'), '外观')
          Row() {
            this.ThemeSeg('跟随系统', 0)
            this.ThemeSeg('浅色', 1)
            this.ThemeSeg('深色', 2)
          }
          .width('100%')
          .padding(3)
          .backgroundColor(this.env.cx.surface2)
          .borderRadius(12)
          Row() {
            Column({ space: 3 }) {
              Text('减少动态效果')
                .fontSize(14)
                .fontColor(this.env.cx.text)
              Text('关闭触点动效和进度过渡，标题栏改为简化切换')
                .fontSize(11)
                .fontColor(this.env.cx.muted)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.env.reduceMotion })
              .selectedColor(this.env.cx.brand)
              .onChange((value: boolean) => {
                this.env.reduceMotion = value;
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(16)
        .backgroundColor(this.env.cx.surface)
        .borderRadius(18)
        .border({ width: 1, color: this.env.cx.line })

        Column() {
          this.SettingCardHeader($r('app.media.ic_shield'), '隐私说明')
          Text('用户主动发送咨询时，问题、选中的附件内容和相关法条片段才会发给你配置的模型服务商；本地检索全程不联网。' +
            '证据图片的识别和合同的规则审查都在手机上完成；开启合同 AI 审查时，只发送替换掉个人信息后的条款文字。')
            .fontSize(12)
            .lineHeight(19)
            .fontColor(this.env.cx.muted)
            .width('100%')
            .margin({ top: 10 })
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding(16)
        .backgroundColor(this.env.cx.surface2)
        .borderRadius(16)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: CONTENT_BOTTOM })
    }
    .scrollBar(BarState.Off)
    .width('100%')
    .height('100%')
    .edgeEffect(EdgeEffect.Spring)
  }

  // 我的: settings, opened from the round button beside the tab bar.
  build() {
    Column() {
      Row({ space: 12 }) {
        Text('‹')
          .fontSize(24)
          .fontColor(this.env.cx.gold)
          .textAlign(TextAlign.Center)
          .width(40)
          .height(40)
          .backgroundColor(this.env.cx.tint)
          .borderRadius(20)
          .accessibilityText('返回')
          .onClick(() => {
            this.actions.close();
          })
        Column({ space: 3 }) {
          Text('我的').fontSize(20).fontWeight(FontWeight.Bold).fontColor(this.env.cx.text)
          Text('模型服务、外观与本机数据').fontSize(11.5).fontColor(this.env.cx.muted)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 52, bottom: 4 })
      this.Settings()
    }
    .width('100%')
    .height('100%')
    .linearGradient({
      angle: 180,
      colors: [[this.env.cx.bgTop, 0.0], [this.env.cx.bgBottom, 1.0]]
    })
  }
}
