import { formBindingData, FormExtensionAbility, formInfo, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LawCardStateService, TIP_AUTO_HIDE_MS } from '../services/LawCardStateService';

export default class LawFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const formId: string = this.formIdFromWant(want);
    LawCardStateService.registerForm(this.context, formId);
    LawCardStateService.hideTipIfExpired(this.context, formId).catch(() => {});
    return LawCardStateService.bindingData(this.context);
  }

  onUpdateForm(formId: string): void {
    // With sceneAnimationParams.triggerTypes=['shake'], HarmonyOS 7 calls
    // onUpdateForm when the user shakes the phone on the desktop.
    if (deviceInfo.sdkApiVersion >= 26) {
      hilog.info(0x0000, 'LawLiveCard', 'onUpdateForm: card update requested');
      this.showTip(formId).catch(() => {});
    } else {
      LawCardStateService.updateForm(this.context, formId).catch(() => {});
    }
  }

  onChangeFormVisibility(newStatus: Record<string, number>): void {
    // Backstop for a tip whose hide timer was lost because the extension
    // process was reclaimed: hide it the next time the card becomes visible.
    Object.keys(newStatus).forEach((formId: string) => {
      LawCardStateService.hideTipIfExpired(this.context, formId).catch(() => {});
    });
  }

  onFormEvent(formId: string, message: string): void {
    if (message.includes('show_law_tip')) {
      this.showTip(formId).catch(() => {});
    } else if (message.includes('hide_law_tip')) {
      LawCardStateService.hideTip(this.context, formId).catch(() => {});
    }
  }

  private async showTip(formId: string): Promise<void> {
    await LawCardStateService.nextTip(this.context, formId);
    this.scheduleAutoHide(formId);
    try {
      const cardRect: formInfo.Rect = await formProvider.getFormRect(formId);
      await formProvider.requestOverflow(formId, {
        // getFormRect is screen-relative; overflow.area is card-relative.
        area: { left: 0, top: 0, width: cardRect.width, height: cardRect.height },
        duration: 2800,
        useDefaultAnimation: false
      });
      hilog.info(0x0000, 'LawLiveCard', 'requestOverflow succeeded');
    } catch (error) {
      hilog.error(0x0000, 'LawLiveCard', 'requestOverflow failed: %{public}s', JSON.stringify(error));
      // Unsupported devices keep the updated static tip card as fallback.
    }
  }

  private scheduleAutoHide(formId: string): void {
    const shownAt: number = LawCardStateService.tipShownAt(this.context);
    setTimeout(() => {
      hilog.info(0x0000, 'LawLiveCard', 'auto hide tip');
      LawCardStateService.hideTipIfExpired(this.context, formId, shownAt).catch(() => {});
    }, TIP_AUTO_HIDE_MS);
  }

  onRemoveForm(formId: string): void {
    LawCardStateService.removeForm(this.context, formId);
  }

  onAcquireFormState(want: Want): formInfo.FormState {
    return formInfo.FormState.READY;
  }

  private formIdFromWant(want: Want): string {
    if (want.parameters === undefined) {
      return '';
    }
    const value: Object | undefined = want.parameters[formInfo.FormParam.IDENTITY_KEY];
    return typeof value === 'string' ? value : '';
  }
}
