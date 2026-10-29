import { ThemeColors } from '../theme/Theme';
import { Glass, Material } from '../theme/Material';

// How far down a page counts as scrolled: its content has started to pass
// under the band.
export const SCROLLED_PAST: number = 16;

// The blue band behind a section's title bar at the top of the page: the 普法
// header's gradient and scale. It sits over the page's content, under the
// system title bar, which is clear over it; once the page scrolls, the band
// fades and the title bar turns to the system's glass.
@Component
export struct BrandBar {
  @Prop cx: ThemeColors;
  @Prop isDark: boolean = false;
  @Prop lightLevel: number = 0;
  @Prop reduceMotion: boolean = false;
  // Status bar, title row and whatever the title bar holds under it.
  @Prop barHeight: number = 0;
  // Fades out when the page scrolls under the title bar (which then turns to
  // the system's glass) or the title bar hides for immersive reading.
  @Prop shown: boolean = true;

  private glass(): Glass {
    return Material.glass(this.lightLevel, this.reduceMotion);
  }

  // Nearly solid: the band carries the white title, so only a hint of the
  // page shows through.
  private tint(color: string): string {
    return (this.glass().blur ? '#EB' : '#FF') + color.substring(1);
  }

  build() {
    // The blur under the gradient: set on one node, the blur's own tint
    // would cover the gradient.
    Stack({ alignContent: Alignment.TopEnd }) {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 118,
          colors: [[this.tint(this.cx.headerA), 0.0], [this.tint(this.cx.headerB), 0.58],
            [this.tint(this.cx.headerC), 1.0]]
        })
      Image($r('app.media.ic_scale'))
        .width(96)
        .height(96)
        .fillColor(this.cx.headerText)
        .opacity(0.12)
        .margin({ top: this.barHeight - 92, right: -10 })
    }
    .width('100%')
    .height(this.barHeight)
    .clip(true)
    .backgroundBlurStyle(this.glass().blur ? BlurStyle.COMPONENT_THICK : BlurStyle.NONE,
      Material.blurOptions(this.isDark))
    .shadow({ radius: 12, color: this.cx.softShadow, offsetY: 2 })
    .opacity(this.shown ? 1 : 0)
    .animation({ duration: this.reduceMotion ? 0 : 220, curve: Curve.EaseOut })
    .hitTestBehavior(HitTestMode.Transparent)
    .accessibilityLevel('no')
  }
}

