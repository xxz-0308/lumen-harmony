import { RoomModel } from './RoomModel';
import { PlayState } from '../player/LivePlayer';
import { PlayerEngine } from '../player/PlayerApi';
import { DanmakuCanvas, DanmakuEngine } from '../danmaku/DanmakuCanvas';
import { BULLET_LEAD_MS, BulletDelay } from '../danmaku/BulletDelay';
import { C, Motion, Radius } from '../theme/Theme';
import { NetImage } from '../components/Basics';

/**
 * The picture itself: cover placeholder → XComponent surface (fit or fill) → danmaku canvas → status.
 * Sized entirely by its parent so the page can morph it between theater and fullscreen.
 */
@ComponentV2
export struct VideoLayer {
  @Param model: RoomModel = new RoomModel();
  @Param fill: boolean = false;
  @Param danmakuOn: boolean = true;
  @Param styleVersion: number = 0;
  @Param cornerRadius: number = 0;
  /** Receives the surface controller whenever the XComponent loads (used for picture-in-picture). */
  @Event onSurface: (xc: XComponentController) => void = () => {};
  @Local boxW: number = 0;
  @Local boxH: number = 0;
  @Local noticeText: string = '';
  private xc: XComponentController = new XComponentController();
  /** Unique per mounted layer: ijkplayer keys its native player by XComponent ID. */
  private nativeId: string = `lumen_video_${VideoLayer.nextId++}`;
  private static nextId: number = 0;
  private noticeTimer: number = -1;
  private bullets: BulletDelay | null = null;

  /** Room switched from the follow drawer: bring the cover back for a cross-fade. */
  @Monitor('model.switchSeq')
  onSwitch(): void {
    this.bullets?.clear();
    this.model.player.firstFrame = false;
  }

  @Monitor('model.player.noticeSeq')
  onNotice(): void {
    this.noticeText = this.model.player.notice;
    if (this.noticeTimer >= 0) {
      clearTimeout(this.noticeTimer);
    }
    this.noticeTimer = setTimeout(() => {
      this.noticeText = '';
      this.noticeTimer = -1;
    }, 2600);
  }

  aboutToDisappear(): void {
    this.bullets?.clear();
    if (this.noticeTimer >= 0) {
      clearTimeout(this.noticeTimer);
    }
  }

  /** Video frame size inside the box for the current fit mode. */
  get frameW(): number {
    const va = this.model.player.videoWidth / Math.max(1, this.model.player.videoHeight);
    const ba = this.boxW / Math.max(1, this.boxH);
    if (this.fill) {
      return va > ba ? this.boxH * va : this.boxW;
    }
    return va > ba ? this.boxW : this.boxH * va;
  }

  get frameH(): number {
    const va = this.model.player.videoWidth / Math.max(1, this.model.player.videoHeight);
    const ba = this.boxW / Math.max(1, this.boxH);
    if (this.fill) {
      return va > ba ? this.boxH : this.boxW / va;
    }
    return va > ba ? this.boxW / va : this.boxH;
  }

  get busy(): boolean {
    const st = this.model.player.state;
    return this.model.loading || this.model.player.reconnecting || st === PlayState.Loading ||
      st === PlayState.Buffering || (st === PlayState.Playing && !this.model.player.firstFrame);
  }

  get errorText(): string {
    if (this.model.error.length > 0) {
      return this.model.error;
    }
    if (this.model.player.state === PlayState.Error) {
      return this.model.player.errorText.length > 0 ? this.model.player.errorText : '播放失败';
    }
    return '';
  }

  build() {
    Stack() {
      // Keep the uninitialized native surface behind the cover. On this device its black
      // backing layer paints through opacity(0) until the first decoded frame arrives.
      if (this.model.player.engine === PlayerEngine.Ijk) {
        // ijkplayer renders from its own native library bound to this component's ID.
        XComponent({ id: this.nativeId, type: XComponentType.SURFACE, libraryname: 'ijkplayer_napi',
          controller: this.xc })
          .width(this.frameW)
          .height(this.frameH)
          .onLoad((context?: object) => {
            if (context !== undefined) {
              this.model.player.bindNative(context, this.nativeId);
            }
            this.onSurface(this.xc);
          })
          .onDestroy(() => this.model.player.unbindNative(this.nativeId))
      } else {
        XComponent({ type: XComponentType.SURFACE, controller: this.xc })
          .width(this.frameW)
          .height(this.frameH)
          .onLoad(() => {
            this.model.player.setSurface(this.xc.getXComponentSurfaceId());
            this.onSurface(this.xc);
          })
      }

      Stack() {
        NetImage({ src: this.model.cover, placeholder: '#101014' })
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#73000000')
      }
      .width('100%')
      .height('100%')
      .opacity(this.model.player.firstFrame ? 0 : 1)
      .animation({ duration: 380, curve: Curve.EaseOut })

      DanmakuCanvas({
        visible: this.danmakuOn,
        styleVersion: this.styleVersion,
        bind: (engine: DanmakuEngine | null) => {
          this.bullets?.clear();
          this.bullets = null;
          if (engine === null) {
            this.model.onBullet = null;
            return;
          }
          // Flying danmaku follows the picture (about a second early); the side chat stays live.
          const delay = new BulletDelay((text: string, color: number) => engine.push(text, color),
            () => this.model.player.latencyMs - BULLET_LEAD_MS);
          this.bullets = delay;
          this.model.onBullet = (text: string, color: number) => delay.push(text, color);
        }
      })
        .width('100%')
        .height('100%')

      if (this.busy && this.errorText.length === 0) {
        Column({ space: 10 }) {
          LoadingProgress()
            .width(36)
            .height(36)
            .color('#E6FFFFFF')
          Text(this.model.loading ? '正在进入直播间' :
            (this.model.player.reconnecting ? '续流中，正在切换播放源' :
              (this.model.player.state === PlayState.Loading && this.model.player.lineCount > 1 ?
                `连接线路 ${this.model.player.lineIndex + 1} / ${this.model.player.lineCount}` : '正在缓冲')))
            .fontSize(12)
            .fontColor(C.onMedia2)
        }
        .hitTestBehavior(HitTestMode.None)
        .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
      }

      if (this.errorText.length > 0 && !this.model.loading) {
        Column({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.exclamationmark_message'))
            .fontSize(34)
            .fontColor([C.onMedia2])
          Text(this.errorText)
            .fontSize(15)
            .fontColor(C.onMedia)
            .textAlign(TextAlign.Center)
            .maxLines(2)
          if (this.errorText !== '主播暂未开播') {
            Text('重试')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.White)
              .height(44)
              .padding({ left: 22, right: 22 })
              .borderRadius(Radius.pill)
              .backgroundColor(C.accent)
              .stateStyles({
                normal: { .opacity(1) },
                pressed: { .opacity(0.72) }
              })
              .accessibilityText('重试播放')
              .onClick(() => {
                this.model.refresh();
              })
          }
        }
        .padding(24)
        .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
      }

      if (this.noticeText.length > 0) {
        Text(this.noticeText)
          .fontSize(12)
          .fontColor(C.onMedia)
          .padding({ left: 14, right: 14, top: 7, bottom: 7 })
          .borderRadius(Radius.pill)
          .backgroundColor('#8C000000')
          .backgroundBlurStyle(BlurStyle.Thin)
          .position({ x: '50%', y: 16 })
          .markAnchor({ x: '50%', y: 0 })
          .hitTestBehavior(HitTestMode.None)
          .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -8 }))
            .animation({ curve: Motion.smooth }))
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
    .borderRadius(this.cornerRadius)
    .clip(true)
    .onAreaChange((o: Area, n: Area) => {
      this.boxW = n.width as number;
      this.boxH = n.height as number;
    })
  }
}
