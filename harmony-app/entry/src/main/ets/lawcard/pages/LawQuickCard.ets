let cardStorage: LocalStorage = new LocalStorage();

@Entry(cardStorage)
@Component
struct LawQuickCard {
  @LocalStorageProp('documentCount') documentCount: number = 2790;
  @LocalStorageProp('searchableDocumentCount') searchableDocumentCount: number = 2761;
  @LocalStorageProp('statusText') statusText: string = '本地资料已就绪';
  @LocalStorageProp('recentConsultation') recentConsultation: string = '尚无咨询';
  @LocalStorageProp('tipVisible') tipVisible: boolean = false;
  @LocalStorageProp('tipTitle') tipTitle: string = '工资拖欠';
  @LocalStorageProp('tipBody') tipBody: string = '先保存工资流水、考勤和催付记录，便于说明欠薪事实。';
  @LocalStorageProp('tipScenario') tipScenario: string = 'wage_arrears';

  readonly actionType: string = 'router';
  readonly abilityName: string = 'EntryAbility';

  @Builder
  private QuickEntry(label: string, scenario: string, tint: string, accent: string) {
    Row() {
      Text(label)
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(accent)
        .width('100%')
        .textAlign(TextAlign.Center)
        .maxLines(1)
    }
    .width('100%')
    .height(36)
    .padding({ left: 5, right: 5 })
    .backgroundColor(tint)
    .borderRadius(11)
    .onClick(() => {
      postCardAction(this, {
        action: this.actionType,
        abilityName: this.abilityName,
        params: {
          source: 'law_quick_card',
          scenario: scenario
        }
      });
    })
  }

  build() {
    Column() {
      Row() {
        Column() {
          Text('劳动权益助手')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor('#12315E')
            .maxLines(1)
          Text('AI 权益速查 · ' + this.documentCount.toString() + ' 份')
            .fontSize(8)
            .fontColor('#54637C')
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text('✦ 小贴士')
          .fontSize(9)
          .fontColor('#1D4B8F')
          .padding({ left: 7, right: 7, top: 5, bottom: 5 })
          .backgroundColor('#E8EFFA')
          .borderRadius(9)
          .onClick(() => {
            postCardAction(this, { action: 'message', params: { tipAction: 'show_law_tip' } });
          })
      }
      .width('100%')

      if (this.tipVisible) {
        Column({ space: 5 }) {
          Text(this.tipTitle + ' · 维权提示')
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor('#12315E')
          Text(this.tipBody)
            .fontSize(10)
            .fontColor('#334761')
            .maxLines(3)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .margin({ top: 9 })
        Blank()
        Text('稍后自动返回四入口')
          .fontSize(8)
          .fontColor('#8593A8')
          .width('100%')
          .margin({ bottom: 3 })
        Row({ space: 7 }) {
          Text('返回四入口')
            .fontSize(9)
            .fontColor('#54637C')
            .layoutWeight(1)
            .onClick(() => {
              postCardAction(this, { action: 'message', params: { tipAction: 'hide_law_tip' } });
            })
          Text('了解更多  →')
            .fontSize(10)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1D4B8F')
            .onClick(() => {
              postCardAction(this, {
                action: this.actionType,
                abilityName: this.abilityName,
                params: { source: 'law_tip_card', scenario: this.tipScenario }
              });
            })
        }
        .width('100%')
      } else {
        Row({ space: 7 }) {
          Column({ space: 7 }) {
            this.QuickEntry('欠薪', 'wage_arrears', '#F6EAD2', '#9C6A18')
            this.QuickEntry('违法解除', 'illegal_termination', '#F6EAD2', '#9C6A18')
          }
          .layoutWeight(1)
          Column({ space: 7 }) {
            this.QuickEntry('未签合同', 'unsigned_contract', '#E8EFFA', '#1D4B8F')
            this.QuickEntry('加班', 'overtime', '#E8EFFA', '#1D4B8F')
          }
          .layoutWeight(1)
        }
        .width('100%')
        .margin({ top: 10 })
        Blank()
        Row() {
          Text(this.searchableDocumentCount.toString() + ' 份可检索')
            .fontSize(8)
            .fontColor('#1D4B8F')
            .maxLines(1)
          Blank()
          Text('最近 ' + this.recentConsultation)
            .fontSize(8)
            .fontColor('#54637C')
            .maxLines(1)
        }
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .padding(13)
    .backgroundColor('#F5F7FB')
    .borderRadius(22)
  }
}
