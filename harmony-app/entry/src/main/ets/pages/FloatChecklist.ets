import { ChecklistFloatService } from '../services/ChecklistFloatService';

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

  build() {
    Column({ space: 10 }) {
      Row() {
        Column({ space: 3 }) {
          Text('维权材料清单')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.color('#0F1E33', '#FFFFFF'))
          Text('已填写 ' + this.completedCount().toString() + '/6 项')
            .fontSize(11)
            .fontColor(this.color('#54637C', '#BFCDE3'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Button('关闭')
          .fontSize(11)
          .fontColor(this.color('#12315E', '#E9C677'))
          .backgroundColor(this.color('#E8EFFA', '#2C4164'))
          .onClick(() => {
            ChecklistFloatService.stop().catch(() => {});
          })
      }
      .width('100%')
      Scroll() {
        Column({ space: 8 }) {
          ForEach(this.labels, (label: string, index: number) => {
            Row({ space: 8 }) {
              Text(this.completed(index) ? '✓' : '·')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.completed(index) ?
                  this.color('#1F8E68', '#70D2AC') : this.color('#9C6A18', '#E9C677'))
                .width(18)
              Text(label)
                .fontSize(13)
                .fontColor(this.color('#0F1E33', '#FFFFFF'))
                .layoutWeight(1)
              Text(this.completed(index) ? '已填' : '待补')
                .fontSize(11)
                .fontColor(this.completed(index) ?
                  this.color('#1F8E68', '#70D2AC') : this.color('#54637C', '#BFCDE3'))
            }
            .width('100%')
            .padding({ left: 11, right: 11, top: 8, bottom: 8 })
            .backgroundColor(this.color('#EEF2F8', '#243958'))
            .borderRadius(11)
          })
        }
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
      Button('返回案件继续填写')
        .width('100%')
        .height(42)
        .fontSize(13)
        .fontColor(this.color('#FFFFFF', '#10223D'))
        .backgroundColor(this.color('#1D4B8F', '#E9C677'))
        .borderRadius(12)
        .onClick(() => {
          ChecklistFloatService.returnToCase().catch(() => {});
        })
      Text('仅显示事项状态，不展示姓名、工资或案情正文')
        .fontSize(10)
        .fontColor(this.color('#54637C', '#BFCDE3'))
        .textAlign(TextAlign.Center)
        .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding(14)
    .backgroundColor(this.color('#F7F9FC', '#10223D'))
  }
}
