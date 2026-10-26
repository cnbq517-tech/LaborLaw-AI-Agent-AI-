import { vibrator } from '@kit.SensorServiceKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

// Haptics for the shake card, timed to LawLiveCard's 800ms EaseOut unfold:
// a light tick as the scale starts to turn, a soft swell while it rights
// itself, and a firmer tap as it settles.
export class LawCardHaptics {
  static playUnfold(): void {
    const attribute: vibrator.VibrateAttribute = { usage: 'physicalFeedback' };
    try {
      const pattern: vibrator.VibratorPattern = new vibrator.VibratorPatternBuilder()
        .addTransientEvent(0, { intensity: 45, frequency: 60 })
        .addContinuousEvent(40, 580, {
          intensity: 40,
          frequency: 30,
          // The vibrator service requires 4 to 16 curve points.
          points: [
            { time: 0, intensity: 0.2 },
            { time: 200, intensity: 0.4 },
            { time: 400, intensity: 0.6 },
            { time: 580, intensity: 0.9 }
          ]
        })
        .addTransientEvent(800, { intensity: 95, frequency: 50 })
        .build();
      vibrator.startVibration({ type: 'pattern', pattern: pattern }, attribute).catch(() => {
        LawCardHaptics.playPresets(attribute);
      });
    } catch (error) {
      hilog.warn(0x0000, 'LawLiveCard', 'pattern vibration failed: %{public}s', JSON.stringify(error));
      LawCardHaptics.playPresets(attribute);
    }
  }

  // Fallback for vibrators without custom patterns: two preset clicks at the
  // start and the settle.
  private static playPresets(attribute: vibrator.VibrateAttribute): void {
    LawCardHaptics.playPreset('haptic.effect.soft', attribute);
    setTimeout(() => {
      LawCardHaptics.playPreset('haptic.effect.hard', attribute);
    }, 800);
  }

  private static playPreset(effectId: string, attribute: vibrator.VibrateAttribute): void {
    try {
      if (!vibrator.isSupportEffectSync(effectId)) {
        return;
      }
      vibrator.startVibration({ type: 'preset', effectId: effectId, count: 1 }, attribute).catch(() => {});
    } catch (error) {
      // Vibration is decorative; the animation plays without it.
    }
  }
}
