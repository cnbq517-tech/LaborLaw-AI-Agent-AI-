import { UIExtensionContentSession } from '@kit.AbilityKit';
import { LiveFormExtensionAbility, LiveFormInfo } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { liveCardStorage } from '../lawcard/LiveCardState';
import { LawCardTip } from '../models/LawCardTip';
import { LawCardStateService } from '../services/LawCardStateService';

export default class LawLiveFormAbility extends LiveFormExtensionAbility {
  onLiveFormCreate(info: LiveFormInfo, session: UIExtensionContentSession): void {
    const tip: LawCardTip = LawCardStateService.currentTip(this.context);
    liveCardStorage.setOrCreate('liveFormId', info.formId);
    liveCardStorage.setOrCreate('liveTipTitle', tip.title);
    liveCardStorage.setOrCreate('liveTipBody', tip.body);
    liveCardStorage.setOrCreate('liveTipScenario', tip.scenario);
    try {
      session.loadContent('pages/LawLiveCard', liveCardStorage);
      hilog.info(0x0000, 'LawLiveCard', 'live form content loaded');
    } catch (error) {
      hilog.error(0x0000, 'LawLiveCard', 'live form content failed: %{public}s', JSON.stringify(error));
    }
  }

  onLiveFormDestroy(info: LiveFormInfo): void {
    // The system releases the short-lived animation page.
  }
}
