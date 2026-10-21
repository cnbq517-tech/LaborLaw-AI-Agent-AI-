import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { liveCardStorage } from '../lawcard/LiveCardState';

@Entry(liveCardStorage)
@Component
struct LawLiveCard {
  @LocalStorageProp('liveTipTitle') tipTitle: string = '工资拖欠';
  @LocalStorageProp('liveTipBody') tipBody: string = '先保存工资流水、考勤和催付记录。';
  @LocalStorageProp('liveTipScenario') tipScenario: string = 'wage_arrears';
  @State unfolded: boolean = false;

  aboutToAppear(): void {
    hilog.info(0x0000, 'LawLiveCard', 'animation page appeared');
    setTimeout(() => {
      this.getUIContext().animateTo({ duration: 800, curve: Curve.EaseOut }, () => {
        this.unfolded = true;
      });
    }, 80);
  }

  private openConsultation(): void {
    const host: Context | undefined = this.getUIContext().getHostContext();
    if (host === undefined) {
      return;
    }
    (host as common.LiveFormExtensionContext).startAbilityByLiveForm({
      bundleName: 'com.laborlaw.aiassistant',
      moduleName: 'entry',
      abilityName: 'EntryAbility',
      parameters: {
        source: 'law_live_card',
        scenario: this.tipScenario
      }
    }).catch(() => {
      // The non-animated tip card retains the same "了解更多" route.
    });
  }

  build() {
    Stack() {
      Column()
        .width(this.unfolded ? 132 : 52)
        .height(this.unfolded ? 132 : 52)
        .backgroundColor('#35C79A3E')
        .borderRadius(66)
        .opacity(this.unfolded ? 1 : 0.2)

      Column({ space: 4 }) {
        Text('维权小贴士')
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor('#F2CA79')
          .width('100%')
        Image($r('app.media.ic_scale'))
          .width(this.unfolded ? 62 : 24)
          .height(this.unfolded ? 62 : 24)
          .fillColor('#F2CA79')
          .rotate({ angle: this.unfolded ? 0 : -24 })
          .opacity(this.unfolded ? 1 : 0.25)
        Text(this.tipTitle)
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .opacity(this.unfolded ? 1 : 0)
        Text(this.tipBody)
          .fontSize(10)
          .fontColor('#DCE7F6')
          .maxLines(2)
          .opacity(this.unfolded ? 1 : 0)
        Text('了解更多  →')
          .fontSize(10)
          .fontWeight(FontWeight.Bold)
          .fontColor('#F2CA79')
          .width('100%')
          .textAlign(TextAlign.End)
          .opacity(this.unfolded ? 1 : 0)
          .onClick(() => {
            this.openConsultation();
          })
      }
      .width('100%')
      .height('100%')
      .padding(12)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#12315E')
    .borderRadius(22)
  }
}
