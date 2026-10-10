import { C, Motion, Radius } from '../theme/Theme';
import { IconButton } from '../components/Basics';
import { RoomSheetLayout } from './RoomSheetLayout';

/** Room-specific presentation shell; the page continues owning every action and lifetime. */
@ComponentV2
export struct RoomSheet {
  @Param title: string = '';
  @Param layout: RoomSheetLayout = new RoomSheetLayout();
  @Param reduceMotion: boolean = false;
  @Event onClose: () => void = () => {};
  @Event onRefresh: () => void = () => {};
  @BuilderParam content: () => void;

  @Builder
  header() {
    Row() {
      Text(this.title)
        .fontSize(15).fontWeight(FontWeight.Bold).fontColor(C.onMedia)
        .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.layout.side) {
        IconButton({ dim: 40, icon: $r('sys.symbol.arrow_clockwise'), tint: C.onMedia, iconSize: 17,
          label: '刷新', onTap: () => this.onRefresh() })
      }
      IconButton({ dim: 40, icon: $r('sys.symbol.xmark'), tint: C.onMedia, iconSize: 17,
        label: '关闭', onTap: () => this.onClose() })
        .id('room_sheet_close')
    }
    .width('100%')
    .height(this.layout.headerH)
    .padding({ left: 18, right: 8 })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%').height('100%')
        .backgroundColor('#33000000')
        .transition(TransitionEffect.OPACITY.animation({ duration: this.reduceMotion ? 0 : 180 }))
        .onClick(() => this.onClose())
      if (this.layout.side) {
        Column() {
          this.header()
          Column() { this.content() }
            .width('100%').layoutWeight(1)
        }
        .width(this.layout.width)
        .height(this.layout.maxH)
        .position({ x: this.layout.x, y: this.layout.y })
        .borderRadius(Radius.xl)
        .backgroundColor('#A6121216')
        .backgroundBlurStyle(BlurStyle.Thick)
        .borderWidth(1).borderColor('#1FFFFFFF')
        .shadow({ radius: 28, color: '#4D000000', offsetY: 8 })
        .clip(true)
        .onClick(() => {})
        .transition(TransitionEffect.translate({ x: this.reduceMotion ? 0 : 60 }).combine(TransitionEffect.OPACITY)
          .animation({ duration: this.reduceMotion ? 0 : 220, curve: Motion.snappy }))
        .gesture(PanGesture({ direction: PanDirection.Right, distance: 30 }).onActionEnd(() => this.onClose()))
      } else {
        Column() {
          Column() {
            this.header()
            this.content()
          }
          .width(this.layout.width)
          .constraintSize({ maxHeight: this.layout.maxH })
          .padding({ bottom: 10 })
          .borderRadius(Radius.xl)
          .backgroundColor('#99121216')
          .backgroundBlurStyle(BlurStyle.Thick)
          .borderWidth(1).borderColor('#24FFFFFF')
          .shadow({ radius: 32, color: '#59000000', offsetY: 10 })
          .clip(true)
          .onClick(() => {})
          .transition(TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: this.reduceMotion ? 1 : 0.9,
            y: this.reduceMotion ? 1 : 0.9, centerY: '100%' }))
            .animation({ duration: this.reduceMotion ? 0 : 220, curve: Motion.snappy }))
        }
        .width(this.layout.width)
        .height(this.layout.bottom)
        .justifyContent(FlexAlign.End)
        .position({ x: this.layout.x, y: 0 })
        .hitTestBehavior(HitTestMode.Transparent)
      }
    }
    .width('100%')
    .height('100%')
  }
}
