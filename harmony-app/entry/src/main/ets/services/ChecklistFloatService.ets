import { abilityAccessCtrl, common } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { display, floatView } from '@kit.ArkUI';

// The checklist's size in vp: six items in two columns, the button and a note.
const FLOAT_WIDTH_VP: number = 350;
const FLOAT_HEIGHT_VP: number = 272;

/** Only six completion flags cross into the floating window; case text never does. */
export class ChecklistFloatService {
  static readonly storage: LocalStorage = new LocalStorage();
  private static controller: floatView.FloatViewController | undefined = undefined;
  private static opening: boolean = false;

  static isSupported(): boolean {
    if (deviceInfo.sdkApiVersion < 26) {
      return false;
    }
    try {
      return floatView.isFloatViewEnabled();
    } catch (error) {
      return false;
    }
  }

  static isOpen(): boolean {
    return ChecklistFloatService.controller !== undefined;
  }

  static update(mask: number): void {
    ChecklistFloatService.storage.setOrCreate('checklistMask', mask);
  }

  static setDarkTheme(isDark: boolean): void {
    ChecklistFloatService.storage.setOrCreate('checklistIsDark', isDark);
  }

  static async open(context: common.UIAbilityContext, mask: number, isDark: boolean): Promise<void> {
    ChecklistFloatService.update(mask);
    ChecklistFloatService.setDarkTheme(isDark);
    if (!ChecklistFloatService.isSupported()) {
      throw new Error('当前设备不支持鸿蒙 7 闪控窗');
    }
    if (ChecklistFloatService.controller !== undefined || ChecklistFloatService.opening) {
      return;
    }
    ChecklistFloatService.opening = true;
    let createdController: floatView.FloatViewController | undefined = undefined;
    try {
      const result = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(
        context, ['ohos.permission.FLOAT_VIEW']
      );
      if (result.authResults.length === 0 || result.authResults[0] !== 0) {
        throw new Error('闪控窗权限未获授权，请在系统权限设置中允许后重试');
      }
      const controller: floatView.FloatViewController = await floatView.create({
        context: context,
        templateType: floatView.FloatViewTemplateType.ROUNDED_RECTANGLE
      });
      createdController = controller;
      ChecklistFloatService.controller = controller;
      const limits: floatView.FloatViewLimits = floatView.getFloatViewLimits(
        floatView.FloatViewTemplateType.ROUNDED_RECTANGLE
      );
      // The checklist needs about 350 × 272vp, the system bar included. The phone's largest window is
      // about that; a tablet's is much larger and left the content floating in
      // white space, so the window is capped at the content's size.
      const dp: number = display.getDefaultDisplaySync().densityPixels;
      const width: number = Math.max(limits.minSize.width, Math.min(limits.maxSize.width, FLOAT_WIDTH_VP * dp));
      let height: number = Math.max(limits.minSize.height, Math.min(limits.maxSize.height, FLOAT_HEIGHT_VP * dp));
      // Keep width / height inside one of the allowed ratio ranges, changing the
      // height only.
      if (limits.ratioLimits.length > 0) {
        const ratio: number = width / height;
        let best: number = ratio;
        let bestGap: number = Number.MAX_VALUE;
        limits.ratioLimits.forEach((range: floatView.RatioLimit): void => {
          const clamped: number = Math.min(Math.max(ratio, range.minRatio), range.maxRatio);
          const gap: number = Math.abs(clamped - ratio);
          if (clamped > 0 && gap < bestGap) {
            bestGap = gap;
            best = clamped;
          }
        });
        height = Math.max(limits.minSize.height, Math.min(limits.maxSize.height, width / best));
      }
      await controller.setWindowSize({ width: Math.round(width), height: Math.round(height) });
      controller.onStateChange((info: floatView.FloatViewStateChangeInfo): void => {
        if (info.state === floatView.FloatViewState.STOPPED || info.state === floatView.FloatViewState.ERROR) {
          ChecklistFloatService.controller = undefined;
          AppStorage.setOrCreate('checklistFloatActive', false);
        } else if (info.state === floatView.FloatViewState.STARTED) {
          AppStorage.setOrCreate('checklistFloatActive', true);
        }
      });
      await controller.setUIContext('pages/FloatChecklist', ChecklistFloatService.storage);
      await controller.setFloatViewVisibilityInApp(false);
      await controller.start();
    } catch (error) {
      if (createdController !== undefined) {
        try {
          await createdController.stop();
        } catch (stopError) {
          // The controller may not have reached STARTED yet.
        }
        createdController.offStateChange();
      }
      ChecklistFloatService.controller = undefined;
      AppStorage.setOrCreate('checklistFloatActive', false);
      throw new Error(String(error));
    } finally {
      ChecklistFloatService.opening = false;
    }
  }

  static async stop(): Promise<void> {
    const controller: floatView.FloatViewController | undefined = ChecklistFloatService.controller;
    if (controller === undefined) {
      return;
    }
    try {
      await controller.stop();
    } finally {
      ChecklistFloatService.controller = undefined;
      AppStorage.setOrCreate('checklistFloatActive', false);
    }
  }

  static async returnToCase(): Promise<void> {
    if (ChecklistFloatService.controller !== undefined) {
      await ChecklistFloatService.controller.restoreMainWindow();
    }
  }
}
