import { hdsEffect } from '@kit.UIDesignKit';
import { ThemeColors } from './Theme';

// HarmonyOS point light (光感): buttons emit a light that follows the finger
// while pressed; rows and the drawer edge pick up light from nearby sources.

export const LIGHT_BUTTON: number = 0;
export const LIGHT_PANEL: number = 2;

const effects: Map<string, VisualEffect> = new Map<string, VisualEffect>();

export function pointLight(kind: number, isDark: boolean, cx: ThemeColors): VisualEffect | undefined {
  const key: string = kind.toString() + (isDark ? 'd' : 'l');
  const cached: VisualEffect | undefined = effects.get(key);
  if (cached !== undefined) {
    return cached;
  }
  let effect: VisualEffect | undefined = undefined;
  try {
    const builder: hdsEffect.HdsEffectBuilder = new hdsEffect.HdsEffectBuilder();
    if (kind === LIGHT_PANEL) {
      builder.pointLight({ illuminatedType: hdsEffect.PointLightIlluminatedType.DEFAULT_FEATHERING_BORDER });
    } else {
      builder.pointLight({
        sourceType: hdsEffect.PointLightSourceType.BRIGHT,
        illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER_CONTENT,
        options: {
          color: cx.glow,
          intensity: 2,
          height: 48,
          bloom: isDark ? 0.6 : 0.3
        }
      });
      builder.pressShadow(hdsEffect.PressShadowType.BLEND_GRADIENT);
    }
    effect = builder.buildEffect();
    effects.set(key, effect);
  } catch (error) {
    effect = undefined;
  }
  return effect;
}
