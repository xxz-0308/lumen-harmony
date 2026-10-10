import { image } from '@kit.ImageKit';
import { C, Motion, Radius, SiteStyle } from '../theme/Theme';
import { ImageLoader } from '../util/ImageLoader';
import { AppEnv } from '../app/AppEnv';

/** Network image that fades in over a skeleton tone once decoded. */
@ComponentV2
export struct NetImage {
  @Param src: string = '';
  @Param radius: number = 0;
  @Param fit: ImageFit = ImageFit.Cover;
  @Param placeholder: ResourceColor = C.skeleton;
  @Local loaded: boolean = false;
  @Local pixel: image.PixelMap | null = null;
  @Local env: AppEnv = AppEnv.inst;
  @Local visible: boolean = true;
  private mounted: boolean = false;
  private resolveGeneration: number = 0;

  aboutToAppear(): void {
    this.mounted = true;
    this.resolveManual();
  }

  aboutToDisappear(): void {
    this.mounted = false;
    this.resolveGeneration++;
  }

  @Monitor('src')
  onSrc(): void {
    this.loaded = false;
    this.pixel = null;
    this.resolveManual();
  }

  @Monitor('visible', 'env.foreground')
  onActivity(): void {
    this.resolveManual();
  }

  private resolveManual(): void {
    const generation = ++this.resolveGeneration;
    if (!this.mounted || !this.visible || !this.env.foreground || !ImageLoader.needsManual(this.src)) {
      return;
    }
    const want = this.src;
    const hit = ImageLoader.cached(want);
    if (hit !== null) {
      this.pixel = hit;
      this.loaded = true;
      return;
    }
    ImageLoader.load(want).then((pm: image.PixelMap | null) => {
      // The download is shared by other views; discard only this view's stale completion.
      if (pm !== null && this.mounted && this.visible && this.env.foreground &&
        generation === this.resolveGeneration && want === this.src) {
        this.pixel = pm;
        this.loaded = true;
      }
    });
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.placeholder)
      if (this.pixel !== null) {
        Image(this.pixel)
          .width('100%')
          .height('100%')
          .objectFit(this.fit)
          .draggable(false)
          .opacity(this.loaded ? 1 : 0)
          .animation({ duration: AppEnv.inst.reduceMotion ? 0 : 320, curve: Curve.EaseOut })
          .onComplete(() => {
            this.loaded = true;
          })
      } else if (this.src.length > 0 && !ImageLoader.needsManual(this.src)) {
        Image(this.src)
          .width('100%')
          .height('100%')
          .objectFit(this.fit)
          .draggable(false)
          .syncLoad(false)
          .opacity(this.loaded ? 1 : 0)
          .animation({ duration: AppEnv.inst.reduceMotion ? 0 : 320, curve: Curve.EaseOut })
          .onComplete(() => {
            this.loaded = true;
          })
      }
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .borderRadius(this.radius)
    .onVisibleAreaChange([0], (visible: boolean) => { this.visible = visible; })
  }
}

/** Circular avatar with an optional breathing live ring. */
@ComponentV2
export struct Avatar {
  @Param src: string = '';
  @Param dim: number = 32;
  @Param live: boolean = false;
  @Param ring: number = 2;
  @Local pulse: boolean = false;
  @Local visible: boolean = true;

  get animated(): boolean {
    return this.visible && AppEnv.inst.foreground && !AppEnv.inst.reduceMotion;
  }

  build() {
    Stack() {
      if (this.live) {
        Row()
          .width(this.dim + this.ring * 4)
          .height(this.dim + this.ring * 4)
          .borderRadius(999)
          .borderWidth(this.ring)
          .borderColor(C.live)
          .opacity(this.pulse && this.animated ? 0.25 : 0.95)
          .scale({ x: this.pulse && this.animated ? 1.08 : 1, y: this.pulse && this.animated ? 1.08 : 1 })
          .animation({ duration: this.animated ? 1100 : 0, curve: Curve.EaseInOut,
            iterations: this.animated ? -1 : 1, playMode: PlayMode.Alternate })
          .onAppear(() => {
            this.pulse = true;
          })
      }
      NetImage({ src: this.src, radius: this.dim / 2, placeholder: C.surface3 })
        .width(this.dim)
        .height(this.dim)
    }
    .width(this.dim + (this.live ? this.ring * 4 : 0))
    .height(this.dim + (this.live ? this.ring * 4 : 0))
    .onVisibleAreaChange([0], (visible: boolean) => { this.visible = visible; })
  }
}

/** The Lumen "live" mark: a solid dot with an expanding halo. */
@ComponentV2
export struct LiveDot {
  @Param dim: number = 7;
  @Param color: ResourceColor = C.live;
  @Local pulse: boolean = false;
  @Local visible: boolean = true;

  get animated(): boolean {
    return this.visible && AppEnv.inst.foreground && !AppEnv.inst.reduceMotion;
  }

  build() {
    Stack() {
      Row()
        .width(this.dim)
        .height(this.dim)
        .borderRadius(999)
        .backgroundColor(this.color)
        .opacity(this.pulse && this.animated ? 0 : 0.6)
        .scale({ x: this.pulse && this.animated ? 2.6 : 1, y: this.pulse && this.animated ? 2.6 : 1 })
        .animation({ duration: this.animated ? 1800 : 0, curve: Curve.EaseOut,
          iterations: this.animated ? -1 : 1 })
      Row()
        .width(this.dim)
        .height(this.dim)
        .borderRadius(999)
        .backgroundColor(this.color)
    }
    .width(this.dim)
    .height(this.dim)
    .onVisibleAreaChange([0], (visible: boolean) => { this.visible = visible; })
    .onAppear(() => {
      this.pulse = true;
    })
  }
}

/**
 * Small platform pill. `onMedia` renders it as a dark tint for use on top of covers; a live blur
 * this small is invisible, yet every card would re-blur it whenever anything moved over the grid.
 */
@ComponentV2
export struct SiteBadge {
  @Param siteId: string = 'huya';
  @Param onMedia: boolean = true;

  build() {
    Row({ space: 5 }) {
      Row()
        .width(6)
        .height(6)
        .borderRadius(999)
        .backgroundColor(SiteStyle.color(this.siteId))
      Text(SiteStyle.label(this.siteId))
        .fontSize(10)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.onMedia ? C.onMedia : C.text2)
    }
    .padding({ left: 7, right: 8, top: 3, bottom: 3 })
    .borderRadius(Radius.pill)
    .backgroundColor(this.onMedia ? '#73000000' : C.surface2)
  }
}

/** A moving highlight sweep used by skeleton placeholders. */
@ComponentV2
export struct Shimmer {
  @Param radius: number = Radius.md;
  @Local run: boolean = false;
  @Local visible: boolean = true;

  get animated(): boolean {
    return this.visible && AppEnv.inst.foreground && !AppEnv.inst.reduceMotion;
  }

  build() {
    Stack() {
      Row()
        .width('55%')
        .height('100%')
        .linearGradient({
          angle: 90,
          colors: [[C.skeleton, 0], [C.skeletonHi, 0.5], [C.skeleton, 1]]
        })
        .translate({ x: this.run && this.animated ? '190%' : '-100%' })
        .animation({ duration: this.animated ? 1500 : 0, curve: Curve.EaseInOut,
          iterations: this.animated ? -1 : 1, delay: this.animated ? 150 : 0 })
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Start)
    .backgroundColor(C.skeleton)
    .borderRadius(this.radius)
    .clip(true)
    .onVisibleAreaChange([0], (visible: boolean) => { this.visible = visible; })
    .onAppear(() => {
      this.run = true;
    })
  }
}

@ComponentV2
export struct RoomCardSkeleton {
  build() {
    Column({ space: 10 }) {
      Shimmer({ radius: Radius.lg })
        .width('100%')
        .aspectRatio(16 / 9)
      Row({ space: 10 }) {
        Shimmer({ radius: 14 })
          .width(28)
          .height(28)
        Column({ space: 6 }) {
          Shimmer({ radius: 4 })
            .width('85%')
            .height(12)
          Shimmer({ radius: 4 })
            .width('45%')
            .height(10)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
    }
    .width('100%')
  }
}

/** Horizontal segmented control with a spring-animated selection pill. */
@ComponentV2
export struct Segmented {
  @Param items: string[] = [];
  @Param selected: number = 0;
  @Param segmentWidth: number = 64;
  @Param barHeight: number = 48;
  /** Frosted track with a lit pill, for switchers that float over imagery (platform tabs). */
  @Param glass: boolean = false;
  @Event onSelect: (index: number) => void = () => {
  };
  @Local pressed: number = -1;

  build() {
    Stack({ alignContent: Alignment.Start }) {
      Row()
        .width(this.segmentWidth - 6)
        .height(this.barHeight - 6)
        .borderRadius(Radius.pill)
        .backgroundColor(this.glass ? C.glassPill : C.bgElevated)
        .borderWidth(this.glass ? 0.5 : 0)
        .borderColor(C.glassStroke)
        .shadow({ radius: this.glass ? 12 : 8, color: this.glass ? '#26000000' : '#1F000000', offsetY: 2 })
        .translate({ x: 3 + this.selected * this.segmentWidth })
        .animation({ curve: AppEnv.inst.reduceMotion ? Curve.Linear : Motion.snappy,
          duration: AppEnv.inst.reduceMotion ? 0 : 220 })
      Row() {
        ForEach(this.items, (label: string, i: number) => {
          Button(label, { type: ButtonType.Normal })
            .backgroundColor(Color.Transparent)
            .borderRadius(Radius.pill)
            .accessibilitySelected(i === this.selected)
            .width(this.segmentWidth)
            .height(this.barHeight)
            .padding(0)
            .fontSize(13)
            .fontWeight(i === this.selected ? FontWeight.Bold : FontWeight.Medium)
            .fontColor(i === this.selected ? C.text1 : C.text2)
            .animation({ duration: 180, curve: Curve.EaseOut })
            .scale({ x: this.pressed === i && !AppEnv.inst.reduceMotion ? 0.96 : 1,
              y: this.pressed === i && !AppEnv.inst.reduceMotion ? 0.96 : 1 })
            .animation({ curve: Motion.snappy })
            .onTouch((e: TouchEvent) => {
              if (e.type === TouchType.Down) {
                this.pressed = i;
              } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
                this.pressed = -1;
              }
            })
            .onClick(() => this.onSelect(i))
        }, (label: string) => label)
      }
    }
    .width(this.segmentWidth * this.items.length)
    .height(this.barHeight)
    .padding(0)
    .borderRadius(Radius.pill)
    .backgroundColor(this.glass ? C.glassTint : C.surface2)
    .backgroundBlurStyle(this.glass ? BlurStyle.COMPONENT_THIN : BlurStyle.NONE)
    .borderWidth(this.glass ? 0.5 : 0)
    .borderColor(C.glassStroke)
  }
}

/** Round icon button; `glass` variant is meant for use over video. */
@ComponentV2
export struct IconButton {
  @Param icon: Resource = $r('sys.symbol.xmark');
  @Param dim: number = 44;
  @Param iconSize: number = 20;
  @Param glass: boolean = false;
  @Param tint: ResourceColor = C.text1;
  @Param active: boolean = false;
  @Param toggleState: boolean = false;
  @Param label: string = '';
  @Event onTap: () => void = () => {
  };
  @Local pressed: boolean = false;

  build() {
    Button({ type: ButtonType.Circle }) {
      // SymbolGlyph keeps drawing its first glyph when only the resource changes (heart → filled
      // heart stayed an outline). Keying by resource id rebuilds it, with a short pop-in.
      Stack() {
        ForEach([this.icon], (icon: Resource) => {
          SymbolGlyph(icon)
            .fontSize(this.iconSize)
            .fontColor([this.active ? C.accent : (this.glass ? C.onMedia : this.tint)])
            .transition(TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.6, y: 0.6 }))
              .animation({ duration: AppEnv.inst.reduceMotion ? 0 : 180, curve: Curve.EaseOut }))
        }, (icon: Resource) => `${icon.id}`)
      }
    }
    .width(Math.max(44, this.dim))
    .height(Math.max(44, this.dim))
    .borderRadius(Radius.pill)
    .backgroundColor(this.glass ? (this.pressed ? '#66000000' : '#40000000') :
      (this.pressed ? C.surface3 : Color.Transparent))
    .backgroundBlurStyle(this.glass ? BlurStyle.Thin : BlurStyle.NONE)
    .scale({ x: this.pressed && !AppEnv.inst.reduceMotion ? 0.96 : 1,
      y: this.pressed && !AppEnv.inst.reduceMotion ? 0.96 : 1 })
    .animation({ curve: Motion.snappy })
    .accessibilityText(this.label)
    .accessibilitySelected(this.toggleState ? this.active : undefined)
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

/** Centered message used for empty and error states. */
@ComponentV2
export struct StateView {
  @Param icon: Resource = $r('sys.symbol.dot_radiowaves_left_and_right');
  @Param title: string = '';
  @Param subtitle: string = '';
  @Param actionText: string = '';
  @Event onAction: () => void = () => {
  };

  build() {
    Column({ space: 14 }) {
      Stack() {
        Row()
          .width(96)
          .height(96)
          .borderRadius(999)
          .backgroundColor(C.accentSoft)
          .blur(18)
        SymbolGlyph(this.icon)
          .fontSize(40)
          .fontColor([C.accent])
      }
      .width(110)
      .height(110)
      Text(this.title)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(C.text1)
      if (this.subtitle.length > 0) {
        Text(this.subtitle)
          .fontSize(13)
          .fontColor(C.text2)
          .textAlign(TextAlign.Center)
          .maxLines(3)
      }
      if (this.actionText.length > 0) {
        Button(this.actionText)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .backgroundColor(C.accent)
          .height(48)
          .padding({ left: 22, right: 22 })
          .margin({ top: 6 })
          .onClick(() => this.onAction())
      }
    }
    .padding(32)
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }
}

/** Pull-to-refresh indicator: the Lumen dot breathing while refreshing. */
@ComponentV2
export struct RefreshGlow {
  @Param refreshing: boolean = false;
  @Local on: boolean = false;

  @Monitor('refreshing')
  onRefreshingChanged(): void {
    this.on = this.refreshing;
  }

  build() {
    Row() {
      Stack() {
        Row()
          .width(26)
          .height(26)
          .borderRadius(999)
          .backgroundColor(C.accentSoft)
          .scale({ x: this.on && !AppEnv.inst.reduceMotion ? 1.35 : 1,
            y: this.on && !AppEnv.inst.reduceMotion ? 1.35 : 1 })
          .animation({ duration: this.refreshing && AppEnv.inst.foreground && !AppEnv.inst.reduceMotion ? 700 : 0,
            curve: Curve.EaseInOut,
            iterations: this.refreshing && AppEnv.inst.foreground && !AppEnv.inst.reduceMotion ? -1 : 1,
            playMode: PlayMode.Alternate })
        Row()
          .width(10)
          .height(10)
          .borderRadius(999)
          .backgroundColor(C.accent)
      }
      .width(40)
      .height(40)
      .onAppear(() => {
        this.on = this.refreshing;
      })
      .onClick(() => {
      })
    }
    .width('100%')
    .height(64)
    .justifyContent(FlexAlign.Center)
    .visibility(this.refreshing ? Visibility.Visible : Visibility.Hidden)
  }
}
