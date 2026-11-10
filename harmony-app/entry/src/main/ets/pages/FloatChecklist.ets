import { ChecklistFloatService } from '../services/ChecklistFloatService';

// Height of the system's bar over a ROUNDED_RECTANGLE float view, in vp
// (measured on ALN-AL00).
const FLOAT_SYSTEM_BAR: number = 36;

@Entry(ChecklistFloatService.storage)
@Component
struct FloatChecklist {
  @LocalStorageLink('checklistMask') checklistMask: number = 0;
  @LocalStorageLink('checklistIsDark') checklistIsDark: boolean = false;

  private labels: string[] = [
    '案件发生地', '单位名称', '平均月薪', '时间节点', '核心诉求', '详细经过'
  ];

  private completed(index: number): boolean {
    return (this.checklistMask & (1 << index)) !== 0;
  }

  private completedCount(): number {
    let count: number = 0;
    for (let index: number = 0; index < 6; index++) {
      if (this.completed(index)) {
        count++;
      }
    }
    return count;
  }

  private color(light: string, dark: string): string {
    return this.checklistIsDark ? dark : light;
  }

  // One item: a small tile, green with ✓ once filled. Two columns of three so
  // all six show at once in the window's height, with no scrolling.
  @Builder
  private Item(index: number) {
    Row() {
      Text(this.completed(index) ? '✓' : '○')
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.completed(index) ?
          this.color('#1F8E68', '#70D2AC') : this.color('#9C6A18', '#E9C677'))
        .width(16)
      Text(this.labels[index])
        .fontSize(13)
        .fontColor(this.completed(index) ? this.color('#14573F', '#BFEBD9') : this.color('#0F1E33', '#FFFFFF'))
        .maxLines(1)
        .layoutWeight(1)
    }
    .layoutWeight(1)
    .height(28)
    .padding({ left: 10, right: 6 })
    .backgroundColor(this.completed(index) ? this.color('#E3F3EC', '#1D4A3E') : this.color('#EEF2F8', '#243958'))
    .borderRadius(9)
  }

  build() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text('维权材料清单')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.color('#0F1E33', '#FFFFFF'))
        Text('已填 ' + this.completedCount().toString() + '/6')
          .fontSize(11)
          .fontColor(this.color('#54637C', '#BFCDE3'))
        Blank()
        Text(this.completedCount() === 6 ? '已全部填好' : '待补 ' + (6 - this.completedCount()).toString() + ' 项')
          .fontSize(11)
          .fontColor(this.completedCount() === 6 ? this.color('#1F8E68', '#70D2AC') : this.color('#9C6A18', '#E9C677'))
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
      Column({ space: 6 }) {
        Row({ space: 6 }) {
          this.Item(0)
          this.Item(1)
        }
        Row({ space: 6 }) {
          this.Item(2)
          this.Item(3)
        }
        Row({ space: 6 }) {
          this.Item(4)
          this.Item(5)
        }
      }
      .width('100%')
      Blank()
      Button('返回案件继续填写')
        .width('100%')
        .height(38)
        .fontSize(13)
        .fontColor(this.color('#FFFFFF', '#10223D'))
        .backgroundColor(this.color('#1D4B8F', '#E9C677'))
        .borderRadius(12)
        .onClick(() => {
          ChecklistFloatService.returnToCase().catch(() => {});
        })
      Text('仅显示事项状态，不展示个人信息')
        .fontSize(11)
        .fontColor(this.color('#54637C', '#BFCDE3'))
        .textAlign(TextAlign.Center)
        .width('100%')
    }
    .width('100%')
    .height('100%')
    // The system draws its own bar over the window's top (collapse, app icon
    // and name, close), so the content starts below it; that bar's close
    // replaces a button of our own.
    .padding({ left: 14, right: 14, top: FLOAT_SYSTEM_BAR + 6, bottom: 12 })
    .backgroundColor(this.color('#F7F9FC', '#10223D'))
  }
}
