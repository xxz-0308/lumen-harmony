import { LiveRoomItem } from '../core/model/Models';
import { AppEnv } from '../app/AppEnv';
import { Settings } from '../app/Settings';
import { Nav } from '../app/Nav';
import { C, formatOnline, Motion, Radius } from '../theme/Theme';
import { Avatar, LiveDot, NetImage, Shimmer, SiteBadge, StateView } from '../components/Basics';
import { PillIndicator } from '../components/Decor';
import { HeroSlideState, HomeHeroState } from './HomeHeroState';

/** Visuals and navigation read the same reactive room, including when a slide is reused. */
@ComponentV2
struct HomeHeroSlide {
  @Param slide: HeroSlideState = new HeroSlideState(new LiveRoomItem());
  @Param compact: boolean = false;
  @Param fromFollows: boolean = false;

  private cover(): string {
    const item = this.slide.item;
    if (item.siteId === 'huya') {
      return item.cover.replace('?x-oss-process=style/w338_h190&', '');
    }
    if (item.siteId === 'bilibili') return item.cover.replace('@400w.jpg', '@1280w.jpg');
    return item.cover;
  }

  build() {
    Row({ space: 32 }) {
      Stack({ alignContent: Alignment.TopStart }) {
        NetImage({ src: this.cover() })
        if (this.compact) {
          Column()
            .width('100%')
            .height('100%')
            .linearGradient({ angle: 180, colors: [['#00000000', 0.35], ['#CC000000', 1]] })
          Column({ space: 6 }) {
            Text(this.slide.item.userName)
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(C.onMedia)
            Text(this.slide.item.title)
              .fontSize(14)
              .fontColor(C.onMedia2)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .position({ left: 18, bottom: 16 })
          .padding({ right: 18 })
        }
        Row({ space: 6 }) {
          LiveDot({ dim: 6, color: '#FFFFFF' })
          Text(this.fromFollows ? '关注 · 直播中' : 'LIVE')
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .letterSpacing(this.fromFollows ? 0 : 1)
        }
        .padding({ left: 10, right: 12, top: 5, bottom: 5 })
        .borderRadius(Radius.pill)
        .backgroundColor(C.live)
        .margin(14)
      }
      .height('100%')
      .aspectRatio(16 / 9)
      .constraintSize({ maxWidth: this.compact ? '100%' : '60%' })
      .borderRadius(Radius.xl)
      .clip(true)
      .shadow({ radius: 40, color: '#4D000000', offsetY: 16 })

      if (!this.compact) {
        Column({ space: 14 }) {
          Row({ space: 8 }) {
            SiteBadge({ siteId: this.slide.item.siteId, onMedia: false })
            if (this.slide.item.area.length > 0) {
              Text(this.slide.item.area)
                .fontSize(12)
                .fontColor(C.text2)
            }
          }
          Row({ space: 14 }) {
            Avatar({ src: this.slide.item.avatar, dim: 52, live: true })
            Column({ space: 4 }) {
              Text(this.slide.item.userName)
                .fontSize(26)
                .fontWeight(FontWeight.Bolder)
                .fontColor(C.text1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Row({ space: 4 }) {
                SymbolGlyph($r('sys.symbol.flame_fill'))
                  .fontSize(13)
                  .fontColor([C.accent])
                Text(`${formatOnline(this.slide.item.online)} 人气`)
                  .fontSize(13)
                  .fontColor(C.text2)
              }
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          Text(this.slide.item.title)
            .fontSize(17)
            .lineHeight(25)
            .fontColor(C.text2)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.play_fill'))
              .fontSize(16)
              .fontColor([Color.White])
            Text('进入直播间')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
          }
          .height(44)
          .padding({ left: 20, right: 24 })
          .borderRadius(Radius.pill)
          .linearGradient({ angle: 100, colors: [[C.accentHighlight, 0], [C.accent, 1]] })
          .shadow({ radius: 18, color: C.accentGlow, offsetY: 6 })
          .margin({ top: 6 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Center)
        .translate({ x: AppEnv.inst.reduceMotion ? 0 : this.slide.shift * 60 })
      }
    }
    .width('100%')
    .height('100%')
    .opacity(AppEnv.inst.reduceMotion ? 1 : this.slide.opacity)
    .onClick(() => Nav.openLive(this.slide.item))
  }
}

@ComponentV2
export struct HomeHero {
  @Param items: LiveRoomItem[] = [];
  @Param fromFollows: boolean = false;
  @Param active: boolean = false;
  @Param compact: boolean = false;
  @Param heroHeight: number = 300;
  @Param error: string = '';
  @Param loading: boolean = false;
  @Event onRetry: () => void = () => {};
  @Event onCover: (cover: string) => void = () => {};
  @Local state: HomeHeroState = new HomeHeroState();
  private releaseTimer: number = -1;
  private mounted: boolean = false;

  aboutToAppear(): void {
    this.mounted = true;
    this.state.update(this.items, this.fromFollows);
    this.state.setActive(this.active);
    this.publishCover();
  }

  aboutToDisappear(): void {
    this.mounted = false;
    this.clearRelease();
    this.state.setActive(false);
  }

  @Monitor('items', 'fromFollows')
  onSource(): void {
    if (!this.mounted) return;
    this.state.update(this.items, this.fromFollows);
    this.publishCover();
  }

  @Monitor('active')
  onActive(): void {
    if (!this.mounted) return;
    if (!this.active) this.clearRelease();
    this.state.setActive(this.active);
    this.publishCover();
  }

  private clearRelease(): void {
    if (this.releaseTimer >= 0) {
      clearTimeout(this.releaseTimer);
      this.releaseTimer = -1;
    }
  }

  private publishCover(): void {
    if (!this.mounted) return;
    this.onCover(this.state.slides[this.state.index]?.item.cover ?? '');
  }

  private changeHandler(generation: number): (index: number) => void {
    return (index: number) => {
      this.state.select(index, generation);
      this.publishCover();
    };
  }

  private endHandler(generation: number): (index: number) => void {
    return (index: number) => {
      this.state.finish(index, generation);
      this.publishCover();
    };
  }

  private transitionHandler(generation: number): (proxy: SwiperContentTransitionProxy) => void {
    return (proxy: SwiperContentTransitionProxy) => {
      this.state.transition(proxy.index, proxy.position, generation);
    };
  }

  private touch(event: TouchEvent): void {
    if (!this.mounted || !this.active) return;
    if (event.type === TouchType.Down) {
      this.clearRelease();
      this.state.beginTouch();
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.clearRelease();
      this.releaseTimer = setTimeout(() => {
        this.releaseTimer = -1;
        this.state.endTouch();
        this.publishCover();
      }, 200);
    }
  }

  @Builder
  placeholder() {
    Row({ space: 32 }) {
      Shimmer({ radius: Radius.xl })
        .height('100%')
        .aspectRatio(16 / 9)
      if (!this.compact) {
        Column({ space: 14 }) {
          Shimmer({ radius: 6 }).width('40%').height(22)
          Shimmer({ radius: 6 }).width('70%').height(30)
          Shimmer({ radius: 6 }).width('90%').height(16)
          Shimmer({ radius: 22 }).width(150).height(44)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
    .height(this.heroHeight)
  }

  build() {
    if (this.state.slides.length === 0 && this.error.length > 0) {
      StateView({
        icon: $r('sys.symbol.exclamationmark_message'),
        title: '推荐加载失败', subtitle: this.error,
        actionText: '重试', onAction: () => this.onRetry()
      })
        .width('100%')
        .height(this.heroHeight)
    } else if (this.state.slides.length === 0 && this.loading) {
      this.placeholder()
    } else if (this.state.slides.length === 0) {
      StateView({
        icon: $r('sys.symbol.dot_radiowaves_left_and_right'), title: '暂时没有推荐直播',
        actionText: '重试', onAction: () => this.onRetry()
      })
        .width('100%')
        .height(this.heroHeight)
    } else {
      Column({ space: 16 }) {
        Swiper() {
          ForEach(this.state.slides, (slide: HeroSlideState) => {
            HomeHeroSlide({ slide: slide, compact: this.compact, fromFollows: this.state.fromFollows })
          }, (slide: HeroSlideState) => HomeHeroState.key(slide.item))
        }
        .id('home_hero')
        .width('100%')
        .height(this.heroHeight)
        .indicator(false)
        .loop(this.state.slides.length > 1)
        .autoPlay(!AppEnv.inst.reduceMotion && this.active && Settings.inst.heroAutoPlay &&
          this.state.slides.length > 1 && !this.state.touched)
        .interval(6500)
        .curve(Motion.smooth)
        // Adjacent slides must not leak into the page gutter after a swipe settles.
        .clip(true)
        .index(this.state.index)
        .onChange(this.changeHandler(this.state.generation))
        .onAnimationEnd(this.endHandler(this.state.generation))
        .onTouch((event: TouchEvent) => this.touch(event))
        .customContentTransition({ timeout: 1000, transition: this.transitionHandler(this.state.generation) })
        if (this.state.slides.length > 1) {
          PillIndicator({ count: this.state.slides.length, index: this.state.index })
        }
      }
    }
  }
}
