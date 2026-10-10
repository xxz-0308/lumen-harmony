import { image } from '@kit.ImageKit';
import { C, Motion, Radius, SiteStyle } from '../theme/Theme';
import { AppEnv } from '../app/AppEnv';
import { GlowLoader } from '../util/GlowLoader';

/**
 * Ambient light behind the home header and the live room: the active cover, blurred beyond
 * recognition, cross-fading when it changes. The blur is baked once into a tiny bitmap
 * (GlowLoader) and stretched, so fades and transitions over it never re-blur per frame.
 * `strength` lets the host dim it as the page scrolls.
 */
@ComponentV2
export struct AmbientGlow {
  @Param src: string = '';
  @Param strength: number = 1;
  @Param glowHeight: number = 520;
  @Param active: boolean = true;
  @Local env: AppEnv = AppEnv.inst;
  @Local visible: boolean = true;
  private mounted: boolean = false;
  private generation: number = 0;
  @Local front: image.PixelMap | null = null;
  @Local back: image.PixelMap | null = null;
  @Local frontOn: boolean = true;
  private want: string = '';

  aboutToAppear(): void {
    this.mounted = true;
    this.onSrc();
  }

  aboutToDisappear(): void {
    this.mounted = false;
    this.want = '';
    this.generation++;
  }

  get canLoad(): boolean {
    return this.mounted && this.active && this.visible && this.strength > 0 && this.env.foreground;
  }

  @Monitor('src', 'active', 'strength', 'visible', 'env.foreground')
  onSrc(): void {
    if (!this.canLoad) {
      this.want = '';
      this.generation++;
      return;
    }
    const want = this.src;
    if (want === this.want) {
      return;
    }
    this.want = want;
    const generation = ++this.generation;
    if (want.length === 0) {
      this.front = null;
      this.back = null;
      return;
    }
    const hit = GlowLoader.cached(want);
    if (hit !== null) {
      this.show(hit);
      return;
    }
    GlowLoader.load(want).then((pm: image.PixelMap | null) => {
      if (pm !== null && this.canLoad && generation === this.generation && want === this.want) {
        this.show(pm);
      }
    });
  }

  /** Write the new glow into the hidden layer, then flip which layer is visible. */
  private show(pm: image.PixelMap): void {
    if (pm === (this.frontOn ? this.front : this.back)) {
      return;
    }
    if (this.front === null) {
      this.front = pm;
      this.frontOn = true;
      return;
    }
    if (this.frontOn) {
      this.back = pm;
    } else {
      this.front = pm;
    }
    this.frontOn = !this.frontOn;
  }

  @Builder
  layer(pm: image.PixelMap | null, visible: boolean) {
    if (pm !== null) {
      Image(pm)
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .interpolation(ImageInterpolation.High)
        .scale({ x: 1.25, y: 1.25 })
        .opacity(visible ? 1 : 0)
        .animation({ duration: this.env.reduceMotion || !this.canLoad ? 0 : 700, curve: Curve.EaseInOut })
        .draggable(false)
    }
  }

  build() {
    Stack() {
      this.layer(this.front, this.frontOn)
      this.layer(this.back, !this.frontOn)
      // melt into the page background
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 180,
          colors: [['#00000000', 0], [C.heroFade, 0.92]]
        })
    }
    .width('100%')
    .height(this.glowHeight)
    .opacity(0.62 * this.strength)
    .clip(true)
    .onVisibleAreaChange([0], (visible: boolean) => { this.visible = visible; })
    .hitTestBehavior(HitTestMode.None)
  }
}

/** Capsule page indicator with a stretching active dot. */
@ComponentV2
export struct PillIndicator {
  @Param count: number = 0;
  @Param index: number = 0;

  indices(): number[] {
    const out: number[] = [];
    for (let i = 0; i < this.count; i++) {
      out.push(i);
    }
    return out;
  }

  build() {
    Row({ space: 6 }) {
      ForEach(this.indices(), (i: number) => {
        Row()
          .width(i === this.index ? 22 : 6)
          .height(6)
          .borderRadius(3)
          .backgroundColor(i === this.index ? C.accent : C.text3)
          .opacity(i === this.index ? 1 : 0.5)
          .animation({ curve: Motion.snappy })
      }, (i: number) => `${i}`)
    }
  }
}

@ComponentV2
export struct SectionTitle {
  @Param title: string = '';
  @Param subtitle: string = '';

  build() {
    Row({ space: 10 }) {
      Text(this.title)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(C.text1)
      if (this.subtitle.length > 0) {
        Text(this.subtitle)
          .fontSize(13)
          .fontColor(C.text3)
          .margin({ top: 4 })
      }
    }
    .alignItems(VerticalAlign.Center)
  }
}

/** Large page title used by the secondary sections. */
@ComponentV2
export struct PageTitle {
  @Param title: string = '';
  @Param subtitle: string = '';
  @BuilderParam trailing: () => void = this.none;

  @Builder
  none() {
  }

  build() {
    Row() {
      Column({ space: 4 }) {
        // Secondary pages already name themselves in the top bar; they pass no title.
        if (this.title.length > 0) {
          Text(this.title)
            .fontSize(30)
            .fontWeight(FontWeight.Bolder)
            .fontColor(C.text1)
            .letterSpacing(0.5)
        }
        if (this.subtitle.length > 0) {
          Text(this.subtitle)
            .fontSize(13)
            .fontColor(C.text2)
        }
      }
      .alignItems(HorizontalAlign.Start)
      Blank()
      this.trailing()
    }
    .width('100%')
    .alignItems(VerticalAlign.Bottom)
  }
}

/** Chip-style toggle used for filters. */
@ComponentV2
export struct FilterChip {
  @Param label: string = '';
  @Param selected: boolean = false;
  @Param dotColor: string = '';
  @Event onTap: () => void = () => {
  };
  @Local pressed: boolean = false;

  build() {
    Button({ type: ButtonType.Capsule }) {
      Row({ space: 6 }) {
        if (this.dotColor.length > 0) {
          Row()
            .width(7)
            .height(7)
            .borderRadius(Radius.pill)
            .backgroundColor(this.dotColor)
        }
        Text(this.label)
          .fontSize(13)
          .fontWeight(this.selected ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.selected ? C.accent : C.text2)
      }
    }
    .height(44)
    .padding({ left: 16, right: 16 })
    .borderRadius(Radius.pill)
    // Frosted chips; the selected one is lit and outlined in the accent colour.
    .backgroundColor(this.selected ? C.glassPill : C.glassTint)
    .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
    .borderWidth(this.selected ? 1 : 0.5)
    .borderColor(this.selected ? C.accent : C.glassStroke)
    .shadow(this.selected ? { radius: 10, color: '#1F000000', offsetY: 2 } : { radius: 0, color: Color.Transparent })
    .animation({ duration: AppEnv.inst.reduceMotion ? 0 : 200, curve: Curve.EaseOut })
    .accessibilitySelected(this.selected)
    .accessibilityText(this.label)
    .scale({ x: this.pressed && !AppEnv.inst.reduceMotion ? 0.97 : 1,
      y: this.pressed && !AppEnv.inst.reduceMotion ? 0.97 : 1 })
    .animation({ curve: Motion.snappy })
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Down) {
        this.pressed = true;
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.pressed = false;
      }
    })
    .onClick(() => this.onTap())
  }
}

export function siteDot(id: string): string {
  return SiteStyle.color(id);
}
