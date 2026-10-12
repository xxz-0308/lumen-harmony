import { LiveRoomItem } from '../core/model/Models';
import { AppEnv } from '../app/AppEnv';
import { Nav } from '../app/Nav';
import { Settings } from '../app/Settings';
import { FollowStore } from '../app/Stores';
import { C, formatOnline, Radius } from '../theme/Theme';
import { Avatar, LiveDot, NetImage, Shimmer, SiteBadge, StateView } from '../components/Basics';
import { HeroSlideState, HomeHeroState } from './HomeHeroState';

function highResCover(item: LiveRoomItem): string {
  if (item.siteId === 'huya') {
    return item.cover.replace('?x-oss-process=style/w338_h190&', '');
  }
  if (item.siteId === 'bilibili') {
    return item.cover.replace('@400w.jpg', '@1280w.jpg');
  }
  return item.cover;
}

/**
 * Concept B Split-Stage Hero Slide:
 * Preserves the native 16:9 aspect ratio of the live stream cover on the left (zero cropping or
 * horizontal stretching), paired with an editorial streamer detail panel on the right.
 */
@ComponentV2
struct HomeHeroSlide {
  @Param slide: HeroSlideState = new HeroSlideState(new LiveRoomItem());
  @Param compact: boolean = false;
  @Param fromFollows: boolean = false;
  private coverRect: number[] = [];

  get isFollowed(): boolean {
    return this.fromFollows || FollowStore.inst.isFollowed(this.slide.item.siteId, this.slide.item.roomId);
  }

  build() {
    if (this.compact) {
      Stack({ alignContent: Alignment.BottomStart }) {
        NetImage({ src: highResCover(this.slide.item) })
          .width('100%')
          .height('100%')
        Column()
          .width('100%')
          .height('65%')
          .linearGradient({ angle: 180, colors: [['#00000000', 0], ['#CC000000', 1]] })
        Column({ space: 6 }) {
          Text(this.slide.item.title.length > 0 ? this.slide.item.title : this.slide.item.userName)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(C.onMedia)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`${this.slide.item.userName} · ${formatOnline(this.slide.item.online)} 人气`)
            .fontSize(13)
            .fontColor(C.onMedia2)
        }
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 18, right: 18, bottom: 18 })
      }
      .width('100%')
      .height('100%')
      .onAreaChange((_old: Area, area: Area) => {
        this.coverRect = [
          (area.globalPosition.x ?? 0) as number,
          (area.globalPosition.y ?? 0) as number,
          area.width as number,
          area.height as number,
        ];
      })
      .onClick(() => Nav.openLive(this.slide.item, this.coverRect))
    } else {
      Row({ space: 26 }) {
        // Native 16:9 Live Cover — 100% uncropped, sharp original resolution
        Stack({ alignContent: Alignment.TopStart }) {
          NetImage({ src: highResCover(this.slide.item), radius: Radius.lg })
            .width('100%')
            .height('100%')

          Row({ space: 6 }) {
            LiveDot({ dim: 6, color: '#FFFFFF' })
            Text(this.isFollowed ? '关注 · 直播中' : '正在直播')
              .fontSize(11)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
          }
          .padding({ left: 10, right: 12, top: 5, bottom: 5 })
          .borderRadius(Radius.pill)
          .backgroundColor(C.live)
          .margin(12)
        }
        .height('100%')
        .aspectRatio(16 / 9)
        .borderRadius(Radius.lg)
        .clip(true)
        .shadow({ radius: 18, color: '#26000000', offsetY: 6 })
        .onAreaChange((_old: Area, area: Area) => {
          this.coverRect = [
            (area.globalPosition.x ?? 0) as number,
            (area.globalPosition.y ?? 0) as number,
            area.width as number,
            area.height as number,
          ];
        })

        // Right Editorial Detail Column
        Column({ space: 12 }) {
          Row({ space: 8 }) {
            SiteBadge({ siteId: this.slide.item.siteId, onMedia: false })
            if (this.slide.item.area.length > 0) {
              Text(this.slide.item.area)
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor(C.text2)
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                .borderRadius(Radius.pill)
                .backgroundColor(C.surface2)
            }
          }

          Text(this.slide.item.title.length > 0 ? this.slide.item.title : this.slide.item.userName)
            .fontSize(22)
            .fontWeight(FontWeight.Bolder)
            .fontColor(C.text1)
            .lineHeight(29)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Row({ space: 10 }) {
            Avatar({ src: this.slide.item.avatar, dim: 36, live: true })
            Column({ space: 2 }) {
              Text(this.slide.item.userName)
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor(C.text1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Row({ space: 4 }) {
                SymbolGlyph($r('sys.symbol.flame_fill'))
                  .fontSize(12)
                  .fontColor([C.live])
                Text(`${formatOnline(this.slide.item.online)} 人气`)
                  .fontSize(12)
                  .fontColor(C.text2)
              }
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }

          Blank()

          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.play_fill'))
              .fontSize(14)
              .fontColor([C.onAccent])
            Text('进入直播间')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(C.onAccent)
          }
          .height(40)
          .padding({ left: 20, right: 22 })
          .borderRadius(Radius.pill)
          .backgroundColor(C.accent)
          .margin({ bottom: 4 })
        }
        .layoutWeight(1)
        .height('100%')
        .padding({ top: 6, bottom: 36, right: 8 })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height('100%')
      .padding(16)
      .onClick(() => Nav.openLive(this.slide.item, this.coverRect))
    }
  }
}

@ComponentV2
export struct HomeHero {
  @Param items: LiveRoomItem[] = [];
  @Param fromFollows: boolean = false;
  @Param active: boolean = false;
  @Param compact: boolean = false;
  @Param heroHeight: number = 256;
  @Param error: string = '';
  @Param loading: boolean = false;
  @Event onRetry: () => void = () => {};
  @Event onCover: (cover: string) => void = () => {};
  @Local state: HomeHeroState = new HomeHeroState();
  private swiperController: SwiperController = new SwiperController();
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

  private changeHandler(generation: number = this.state.generation): (index: number) => void {
    return (index: number) => {
      this.state.select(index, generation);
      this.publishCover();
    };
  }

  private endHandler(generation: number = this.state.generation): (index: number) => void {
    return (index: number) => {
      this.state.finish(index, generation);
      this.publishCover();
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
    Shimmer({ radius: Radius.xl })
      .width('100%')
      .height(this.heroHeight)
  }

  @Builder
  dotScrubber() {
    Row({ space: 6 }) {
      ForEach(this.state.slides, (_s: HeroSlideState, i: number) => {
        Row()
          .width(this.state.index === i ? 20 : 6)
          .height(6)
          .borderRadius(3)
          .backgroundColor(this.state.index === i ? C.accent : C.text3)
          .opacity(this.state.index === i ? 1 : 0.45)
          .animation({ duration: 200, curve: Curve.EaseOut })
          .onClick(() => {
            this.swiperController.changeIndex(i, true);
            this.state.select(i);
            this.publishCover();
          })
      }, (_s: HeroSlideState, i: number) => `dot_${i}`)
    }
    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
  }

  build() {
    if (this.state.slides.length === 0 && this.error.length > 0) {
      StateView({
        icon: $r('sys.symbol.exclamationmark_message'),
        title: '焦点加载失败',
        subtitle: this.error,
        actionText: '重试',
        onAction: () => this.onRetry()
      })
        .width('100%')
        .height(this.heroHeight)
    } else if (this.state.slides.length === 0 && this.loading) {
      this.placeholder()
    } else if (this.state.slides.length === 0) {
      StateView({
        icon: $r('sys.symbol.dot_radiowaves_left_and_right'),
        title: '暂时没有推荐直播',
        actionText: '重试',
        onAction: () => this.onRetry()
      })
        .width('100%')
        .height(this.heroHeight)
    } else {
      Stack({ alignContent: Alignment.BottomEnd }) {
        Swiper(this.swiperController) {
          ForEach(this.state.slides, (slide: HeroSlideState) => {
            HomeHeroSlide({ slide: slide, compact: this.compact, fromFollows: this.state.fromFollows })
          }, (slide: HeroSlideState) => HomeHeroState.key(slide.item))
        }
        .index(this.state.index)
        .cachedCount(1)
        .autoPlay(!AppEnv.inst.reduceMotion && this.active && Settings.inst.heroAutoPlay &&
          this.state.slides.length > 1 && !this.state.touched, undefined)
        .interval(5000)
        .duration(AppEnv.inst.reduceMotion ? 0 : 480)
        .loop(this.state.slides.length > 1)
        .indicator(false)
        .curve(Curve.Friction)
        .width('100%')
        .height(this.heroHeight)
        .onChange(this.changeHandler(this.state.generation))
        .onAnimationEnd(this.endHandler(this.state.generation))
        .onTouch((e: TouchEvent) => this.touch(e))

        if (this.state.slides.length > 1) {
          Row() {
            this.dotScrubber()
          }
          .padding({ right: 20, bottom: 14 })
        }
      }
      .width('100%')
      .height(this.heroHeight)
      .borderRadius(Radius.xl)
      .backgroundColor(this.compact ? Color.Transparent : C.bgElevated)
      .shadow({ radius: 28, color: C.shadow, offsetY: 10 })
      .clip(true)
    }
  }
}
