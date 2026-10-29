import { uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { hdsMaterial } from '@kit.UIDesignKit';

// HarmonyOS 7 沉浸光感 (immersive material) in one place, so every surface
// uses the same settings.
//
// The system material only takes effect on the title bar, the bottom tab bar,
// sheets and other dialogs, toasts, Slider and Toggle; set on anything else
// it renders transparent. So floating controls inside the content (composer,
// buttons over the text) use a glass look of their own, whose strength follows
// the same 光感强度 setting.
//
// The app still supports API 23, where none of this exists: every getter
// returns undefined or the plain look there.

// 我的 → 外观 → 光感强度.
export const LIGHT_ADAPTIVE: number = 0;
export const LIGHT_STRONG: number = 1;
export const LIGHT_BALANCED: number = 2;
export const LIGHT_SOFT: number = 3;
export const LIGHT_LABELS: string[] = ['自适应', '强', '均衡', '弱'];

let support: boolean | undefined = undefined;

// How a floating control in the content area looks.
export class Glass {
  // A blurred, see-through background rather than a solid one.
  blur: boolean;
  // The pressed point light.
  light: boolean;
  // How opaque the background is over the blur, as a hex alpha; 强 shows
  // more of the content behind.
  alpha: string;

  constructor(blur: boolean, light: boolean, alpha: string) {
    this.blur = blur;
    this.light = light;
    this.alpha = alpha;
  }

  // A theme color (#RRGGBB) as this glass's background.
  tint(color: string): string {
    return this.blur ? '#' + this.alpha + color.substring(1) : color;
  }
}

export class Material {
  static supported(): boolean {
    if (support === undefined) {
      try {
        support = deviceInfo.sdkApiVersion >= 26 && uiMaterial.isImmersiveMaterialSupported() &&
          hdsMaterial.getSystemMaterialTypes().length > 0;
      } catch (error) {
        support = false;
      }
    }
    return support;
  }

  // The level HDS components (the tab bar) use. Reduced motion asks for the
  // lightest one, which is also the cheapest to draw.
  static hdsLevel(setting: number, reduceMotion: boolean): hdsMaterial.MaterialLevel {
    if (reduceMotion || setting === LIGHT_SOFT) {
      return hdsMaterial.MaterialLevel.SMOOTH;
    }
    if (setting === LIGHT_STRONG) {
      return hdsMaterial.MaterialLevel.EXQUISITE;
    }
    if (setting === LIGHT_BALANCED) {
      return hdsMaterial.MaterialLevel.GENTLE;
    }
    return hdsMaterial.MaterialLevel.ADAPTIVE;
  }

  static hdsType(): hdsMaterial.MaterialType {
    return Material.supported() ? hdsMaterial.MaterialType.IMMERSIVE : hdsMaterial.MaterialType.NONE;
  }

  // Sheets, dialogs and toasts. Their level is the system's; apps cannot set it.
  static dialog(isDark: boolean): uiMaterial.Material | undefined {
    if (!Material.supported()) {
      return undefined;
    }
    return new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.THICK,
      materialColor: isDark ? '#66172940' : '#88EAF0F8',
      applyShadow: true
    });
  }

  // Toasts and alert dialogs: the system's own look, which follows light and
  // dark mode by itself.
  static popup(): uiMaterial.Material | undefined {
    return Material.supported() ? new uiMaterial.ImmersiveMaterial() : undefined;
  }

  // Toggles: the material with its press deformation and light.
  static control(): uiMaterial.Material | undefined {
    if (!Material.supported()) {
      return undefined;
    }
    return new uiMaterial.ImmersiveMaterial({ interactive: true, lightEffect: {} });
  }

  // The glass look for floating controls in the content area. 自适应 follows
  // the level the system picked for this device.
  static glass(setting: number, reduceMotion: boolean): Glass {
    let level: number = setting;
    if (setting === LIGHT_ADAPTIVE) {
      level = LIGHT_BALANCED;
      try {
        if (Material.supported() && uiMaterial.getGlobalMaterialLevel() === uiMaterial.MaterialLevel.SMOOTH) {
          level = LIGHT_SOFT;
        }
      } catch (error) {
        level = LIGHT_BALANCED;
      }
    }
    if (level === LIGHT_SOFT) {
      return new Glass(false, false, 'FF');
    }
    return new Glass(true, !reduceMotion, level === LIGHT_STRONG ? 'B3' : 'D9');
  }
}
