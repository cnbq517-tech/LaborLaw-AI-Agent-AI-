// The 历史咨询 drawer: whether it is shown, where it is while dragged, and
// the search typed into it. The 普法 page pulls it out with a swipe and the
// drawer pushes itself back, so both work on this one object.

export const DRAWER_WIDTH: number = 320;

@Observed
export class DrawerState {
  // In the tree; stays true while the closing animation runs.
  visible: boolean = false;
  open: boolean = false;
  // How far it is pushed back while dragged, from -DRAWER_WIDTH to 0.
  drag: number = 0;
  query: string = '';
  private swiping: boolean = false;

  show(ui: UIContext, reduceMotion: boolean): void {
    if (this.visible) {
      return;
    }
    this.query = '';
    this.drag = 0;
    this.visible = true;
    ui.animateTo({ duration: reduceMotion ? 0 : 320, curve: Curve.FastOutSlowIn }, () => {
      this.open = true;
    });
  }

  hide(ui: UIContext, reduceMotion: boolean): void {
    if (!this.visible) {
      return;
    }
    if (reduceMotion) {
      this.open = false;
      this.drag = 0;
      this.visible = false;
      return;
    }
    ui.animateTo({
      duration: 240,
      curve: Curve.FastOutSlowIn,
      onFinish: () => {
        if (!this.open) {
          this.visible = false;
        }
      }
    }, () => {
      this.open = false;
      this.drag = 0;
    });
  }

  // After the drawer itself is dragged: closes past a third, or on a fling.
  settle(ui: UIContext, reduceMotion: boolean, velocityX: number): void {
    if (this.drag < -DRAWER_WIDTH * 0.3 || velocityX < -800) {
      this.hide(ui, reduceMotion);
      return;
    }
    ui.animateTo({ duration: reduceMotion ? 0 : 200, curve: Curve.FastOutSlowIn }, () => {
      this.drag = 0;
    });
  }

  // Swiping right on the 普法 page pulls the drawer out under the finger.
  beginSwipe(): void {
    this.swiping = true;
    this.query = '';
    this.drag = -DRAWER_WIDTH;
    this.open = true;
    this.visible = true;
  }

  updateSwipe(offsetX: number): void {
    if (this.swiping) {
      this.drag = Math.max(-DRAWER_WIDTH, Math.min(0, offsetX - DRAWER_WIDTH));
    }
  }

  endSwipe(ui: UIContext, reduceMotion: boolean, offsetX: number, velocityX: number): void {
    if (!this.swiping) {
      return;
    }
    this.swiping = false;
    if (offsetX > DRAWER_WIDTH * 0.35 || velocityX > 600) {
      ui.animateTo({ duration: reduceMotion ? 0 : 240, curve: Curve.FastOutSlowIn }, () => {
        this.drag = 0;
      });
    } else {
      this.hide(ui, reduceMotion);
    }
  }
}
