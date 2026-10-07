import { ChatLine, RoomModel, ScCard } from './RoomModel';
import { FollowItem, FollowStore } from '../app/Stores';
import { Settings, DanmakuStroke } from '../app/Settings';
import { argb, C, formatDuration, formatOnline, Motion, Radius, SiteStyle } from '../theme/Theme';
import { Avatar, NetImage, Segmented, SiteBadge } from '../components/Basics';
import { stripTags } from '../core/common/Http';

/** Softens platform colors that are unreadable on the current surface. */
function chatColor(c: number, dark: boolean): string {
  if (c === 0xffffff || c === 0) {
    return '';
  }
  const r = (c >> 16) & 0xff;
  const g = (c >> 8) & 0xff;
  const b = c & 0xff;
  const lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
  if (dark && lum < 0.3) {
    return '';
  }
  if (!dark && lum > 0.8) {
    return '';
  }
  return argb(c, 1);
}

@ComponentV2
export struct ScCardView {
  @Param card: ScCard = new ScCard();
  @Param compact: boolean = false;

  build() {
    Column() {
      Row({ space: 8 }) {
        Avatar({ src: this.card.sc.face, dim: this.compact ? 22 : 28 })
        Text(this.card.sc.userName)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor('#E6000000')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(`¥${this.card.sc.price}`)
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor('#E6000000')
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 7, bottom: 7 })
      .backgroundColor(this.card.sc.backgroundColor)
      Text(this.card.sc.message)
        .fontSize(13)
        .fontColor(Color.White)
        .width('100%')
        .maxLines(this.compact ? 2 : 4)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .padding({ left: 10, right: 10, top: 7, bottom: 8 })
        .backgroundColor(this.card.sc.backgroundBottomColor)
    }
    .borderRadius(Radius.sm)
    .clip(true)
  }
}

/** Chat stream for the side panel: sticks to the bottom unless the user scrolls up. */
@ComponentV2
export struct ChatList {
  @Param model: RoomModel = new RoomModel();
  @Param dark: boolean = true;
  @Local following: boolean = true;
  @Local unseen: number = 0;
  private scroller: ListScroller = new ListScroller();
  private lastCount: number = 0;
  private scrollTimer: number = -1;

  @Monitor('model.chats')
  onChats(): void {
    const n = this.model.chats.length;
    const added = Math.max(0, n - this.lastCount);
    this.lastCount = n;
    if (this.following) {
      if (this.scrollTimer >= 0) {
        clearTimeout(this.scrollTimer);
      }
      this.scrollTimer = setTimeout(() => {
        this.scrollTimer = -1;
        this.scroller.scrollEdge(Edge.Bottom);
      }, 0);
    } else {
      this.unseen += added > 0 ? added : 1;
    }
  }

  aboutToDisappear(): void {
    if (this.scrollTimer >= 0) {
      clearTimeout(this.scrollTimer);
      this.scrollTimer = -1;
    }
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      List({ scroller: this.scroller, space: 2 }) {
        if (this.model.superChats.length > 0) {
          ListItem() {
            List({ space: 8 }) {
              ForEach(this.model.superChats, (c: ScCard) => {
                ListItem() {
                  ScCardView({ card: c, compact: true })
                    .width(220)
                }
              }, (c: ScCard) => `${c.id}`)
            }
            .listDirection(Axis.Horizontal)
            .scrollBar(BarState.Off)
            .height(96)
            .margin({ bottom: 8 })
          }
        }
        if (this.model.chats.length === 0) {
          ListItem() {
            Text(this.model.danmakuStatus.length > 0 ? this.model.danmakuStatus :
              (this.model.blockedChats > 0 ? `已屏蔽 ${this.model.blockedChats} 条弹幕，请检查屏蔽词` :
                (this.model.danmakuConnected ? '已连接，暂无弹幕' : '弹幕连接中…')))
              .fontSize(13)
              .fontColor(C.text3)
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: 40 })
          }
        }
        ForEach(this.model.chats, (line: ChatLine) => {
          ListItem() {
            Text() {
              Span(line.user)
                .fontColor(C.text3)
              Span('  ')
              Span(line.text)
                .fontColor(chatColor(line.color, this.dark).length > 0 ? chatColor(line.color, this.dark) : C.text1)
            }
            .fontSize(14)
            .lineHeight(21)
            .padding({ top: 4, bottom: 4 })
            .width('100%')
          }
        }, (line: ChatLine) => `${line.id}`)
      }
      .width('100%')
      .height('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .onScrollStart(() => {
        this.following = false;
      })
      .onReachEnd(() => {
        this.following = true;
        this.unseen = 0;
      })

      if (!this.following && this.unseen > 0) {
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(13)
            .fontColor([Color.White])
          Text(`${this.unseen > 99 ? '99+' : this.unseen} 条新弹幕`)
            .fontSize(12)
            .fontColor(Color.White)
        }
        .padding({ left: 12, right: 14, top: 7, bottom: 7 })
        .borderRadius(Radius.pill)
        .backgroundColor(C.accent)
        .shadow({ radius: 12, color: '#40000000', offsetY: 3 })
        .margin({ bottom: 14 })
        .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 10 }))
          .animation({ curve: Motion.lively }))
        .onClick(() => {
          this.following = true;
          this.unseen = 0;
          this.scroller.scrollEdge(Edge.Bottom);
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}

/** Live follows as tappable rows with cover thumbnails; used by the panel tab and the drawer. */
@ComponentV2
export struct LiveFollowList {
  @Param currentKey: string = '';
  @Param onMedia: boolean = false;
  @Event onPick: (f: FollowItem) => void = () => {
  };

  build() {
    Column() {
      if (FollowStore.inst.liveItems.length === 0) {
        Column({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.heart'))
            .fontSize(30)
            .fontColor([this.onMedia ? C.onMedia3 : C.text3])
          Text(FollowStore.inst.refreshing ? '正在刷新开播状态…' : '关注的主播都还没开播')
            .fontSize(13)
            .fontColor(this.onMedia ? C.onMedia2 : C.text2)
        }
        .width('100%')
        .padding({ top: 60 })
      } else {
        List({ space: 10 }) {
          ForEach(FollowStore.inst.liveItems, (f: FollowItem) => {
            ListItem() {
              Row({ space: 12 }) {
                Stack({ alignContent: Alignment.BottomEnd }) {
                  NetImage({ src: f.cover, radius: Radius.sm })
                  Text(formatOnline(f.online))
                    .fontSize(10)
                    .fontColor(Color.White)
                    .padding({ left: 5, right: 5, top: 1, bottom: 1 })
                    .borderRadius(4)
                    .backgroundColor('#80000000')
                    .margin(4)
                }
                .width(112)
                .aspectRatio(16 / 9)
                Column({ space: 4 }) {
                  Row({ space: 6 }) {
                    Row()
                      .width(6)
                      .height(6)
                      .borderRadius(999)
                      .backgroundColor(SiteStyle.color(f.siteId))
                    Text(f.userName)
                      .fontSize(14)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.onMedia ? C.onMedia : C.text1)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)
                  }
                  Text(f.title)
                    .fontSize(12)
                    .fontColor(this.onMedia ? C.onMedia2 : C.text2)
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .padding(8)
              .borderRadius(Radius.md)
              .backgroundColor(f.key === this.currentKey ? (this.onMedia ? '#26FFFFFF' : C.accentSoft) :
                Color.Transparent)
              .onClick(() => this.onPick(f))
            }
          }, (f: FollowItem) => f.key)
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%')
    .height('100%')
  }
}

@ComponentV2
export struct RoomInfo {
  @Param model: RoomModel = new RoomModel();

  @Builder
  row(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(13)
        .fontColor(C.text3)
        .width(64)
      Text(value)
        .fontSize(13)
        .fontColor(C.text1)
        .layoutWeight(1)
        .copyOption(CopyOptions.LocalDevice)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Row({ space: 12 }) {
          Avatar({ src: this.model.avatar, dim: 52, live: this.model.detail?.status ?? false })
          Column({ space: 4 }) {
            Text(this.model.userName)
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(C.text1)
            SiteBadge({ siteId: this.model.siteId, onMedia: false })
          }
          .alignItems(HorizontalAlign.Start)
        }
        Text(this.model.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(C.text1)
          .lineHeight(23)
        Column({ space: 10 }) {
          this.row('分区', this.model.area.length > 0 ? this.model.area : '—')
          this.row('房间号', this.model.detail?.roomId ?? this.model.roomId)
          this.row('人气', formatOnline(this.model.online))
          if ((this.model.detail?.startTime ?? 0) > 0) {
            this.row('开播', formatDuration(this.model.detail?.startTime ?? 0))
          }
          this.row('链接', this.model.detail?.url ?? '')
        }
        .padding(14)
        .borderRadius(Radius.md)
        .backgroundColor(C.surface2)
        if ((this.model.detail?.introduction ?? '').length > 0 &&
          this.model.detail?.introduction !== this.model.title) {
          Text(stripTags(this.model.detail?.introduction ?? ''))
            .fontSize(13)
            .lineHeight(20)
            .fontColor(C.text2)
        }
        if ((this.model.detail?.notice ?? '').length > 0) {
          Text(stripTags(this.model.detail?.notice ?? ''))
            .fontSize(13)
            .lineHeight(20)
            .fontColor(C.text2)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .padding(16)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .align(Alignment.Top)
  }
}

/** Translucent chat column over fullscreen video, newest at the bottom, fading toward the top. */
@ComponentV2
export struct SideChatOverlay {
  @Param model: RoomModel = new RoomModel();

  get tail(): ChatLine[] {
    const c = this.model.chats;
    return c.slice(Math.max(0, c.length - 14));
  }

  build() {
    Column({ space: 6 }) {
      ForEach(this.tail, (line: ChatLine) => {
        Text() {
          Span(`${line.user}  `)
            .fontColor('#A6FFFFFF')
          Span(line.text)
            .fontColor(Color.White)
        }
        .fontSize(14)
        .lineHeight(20)
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .borderRadius(Radius.sm)
        .backgroundColor('#26000000')
        .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 12 }))
          .animation({ curve: Motion.smooth }))
      }, (line: ChatLine) => `${line.id}`)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.End)
    .alignItems(HorizontalAlign.Start)
    .clip(true)
    .hitTestBehavior(HitTestMode.None)
  }
}

@ComponentV2
struct SettingRow {
  @Param label: string = '';
  @Param value: string = '';
  @Param onMedia: boolean = true;
  @BuilderParam control: () => void;

  build() {
    Column({ space: 6 }) {
      Row() {
        Text(this.label)
          .fontSize(14)
          .fontColor(this.onMedia ? C.onMedia : C.text1)
        Blank()
        Text(this.value)
          .fontSize(13)
          .fontColor(this.onMedia ? C.onMedia2 : C.text2)
          .fontFeature('"tnum" on')
      }
      .width('100%')
      this.control()
    }
    .width('100%')
  }
}

/** Danmaku appearance controls; writes and queues each Settings change. */
@ComponentV2
export struct DanmakuSettingsPanel {
  /** true over video (white text); false inside the settings page. */
  @Param onMedia: boolean = true;
  /** When embedded the host page scrolls, so no inner Scroll is created. */
  @Param embedded: boolean = false;
  @Event onChange: () => void = () => {};
  private s: Settings = Settings.inst;
  @Local danmakuOn: boolean = Settings.inst.danmakuOn;
  @Local dmSize: number = Settings.inst.danmakuSize;
  @Local dmOpacity: number = Settings.inst.danmakuOpacity;
  @Local speed: number = Settings.inst.danmakuSpeed;
  @Local max: number = Settings.inst.danmakuMax;
  @Local area: number = Settings.inst.danmakuArea;
  @Local stroke: DanmakuStroke = Settings.inst.danmakuStroke;
  @Local keepColor: boolean = Settings.inst.danmakuKeepColor;
  @Local sideChat: boolean = Settings.inst.sideChat;
  @Local showSuperChat: boolean = Settings.inst.showSuperChat;

  aboutToAppear(): void {
    this.danmakuOn = this.s.danmakuOn;
    this.dmSize = this.s.danmakuSize;
    this.dmOpacity = this.s.danmakuOpacity;
    this.speed = this.s.danmakuSpeed;
    this.max = this.s.danmakuMax;
    this.area = this.s.danmakuArea;
    this.stroke = this.s.danmakuStroke;
    this.keepColor = this.s.danmakuKeepColor;
    this.sideChat = this.s.sideChat;
    this.showSuperChat = this.s.showSuperChat;
  }

  @Builder
  toggle(label: string, on: boolean, change: (v: boolean) => void) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor(this.onMedia ? C.onMedia : C.text1)
      Blank()
      Toggle({ type: ToggleType.Switch, isOn: on })
        .selectedColor(C.accent)
        .onChange((v: boolean) => {
          change(v);
          this.s.scheduleSave();
          this.onChange();
        })
    }
    .width('100%')
  }

  build() {
    if (this.embedded) {
      this.body()
    } else {
      Scroll() {
        this.body()
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
  }

  @Builder
  body() {
      Column({ space: 22 }) {
        this.toggle('显示弹幕', this.danmakuOn, (v: boolean) => {
          this.danmakuOn = v;
          this.s.danmakuOn = v;
        })
        SettingRow({ onMedia: this.onMedia, label: '字号', value: `${this.dmSize}` }) {
          Slider({ value: this.dmSize, min: 14, max: 36, step: 1 })
            .selectedColor(C.accent)
            .onChange((v: number) => {
              this.dmSize = Math.round(v);
              this.s.danmakuSize = this.dmSize;
              this.s.scheduleSave();
              this.onChange();
            })
        }
        SettingRow({ onMedia: this.onMedia, label: '不透明度', value: `${Math.round(this.dmOpacity * 100)}%` }) {
          Slider({ value: this.dmOpacity * 100, min: 20, max: 100, step: 5 })
            .selectedColor(C.accent)
            .onChange((v: number) => {
              this.dmOpacity = v / 100;
              this.s.danmakuOpacity = this.dmOpacity;
              this.s.scheduleSave();
              this.onChange();
            })
        }
        SettingRow({ onMedia: this.onMedia, label: '速度', value: `${this.speed.toFixed(1)}x` }) {
          Slider({ value: this.speed * 10, min: 5, max: 20, step: 1 })
            .selectedColor(C.accent)
            .onChange((v: number) => {
              this.speed = v / 10;
              this.s.danmakuSpeed = this.speed;
              this.s.scheduleSave();
              this.onChange();
            })
        }
        SettingRow({ onMedia: this.onMedia, label: '同屏上限', value: `${this.max} 条` }) {
          Slider({ value: this.max, min: 20, max: 150, step: 10 })
            .selectedColor(C.accent)
            .onChange((v: number) => {
              this.max = Math.round(v);
              this.s.danmakuMax = this.max;
              this.s.scheduleSave();
              this.onChange();
            })
        }
        SettingRow({ onMedia: this.onMedia, label: '显示区域', value: '' }) {
          Segmented({
            items: ['1/4', '半屏', '3/4', '全屏'],
            selected: [0.25, 0.5, 0.75, 1].indexOf(this.area) >= 0 ?
              [0.25, 0.5, 0.75, 1].indexOf(this.area) : 1,
            segmentWidth: 70,
            onSelect: (i: number) => {
              this.area = [0.25, 0.5, 0.75, 1][i];
              this.s.danmakuArea = this.area;
              this.s.scheduleSave();
              this.onChange();
            }
          })
        }
        SettingRow({ onMedia: this.onMedia, label: '描边样式', value: '' }) {
          Segmented({
            items: ['描边', '阴影', '无'],
            selected: ['stroke', 'shadow', 'none'].indexOf(this.stroke),
            segmentWidth: 70,
            onSelect: (i: number) => {
              this.stroke = ['stroke', 'shadow', 'none'][i] as DanmakuStroke;
              this.s.danmakuStroke = this.stroke;
              this.s.scheduleSave();
              this.onChange();
            }
          })
        }
        this.toggle('保留弹幕颜色', this.keepColor, (v: boolean) => {
          this.keepColor = v;
          this.s.danmakuKeepColor = v;
        })
        this.toggle('全屏侧边聊天流', this.sideChat, (v: boolean) => {
          this.sideChat = v;
          this.s.sideChat = v;
        })
        this.toggle('全屏显示醒目留言', this.showSuperChat, (v: boolean) => {
          this.showSuperChat = v;
          this.s.showSuperChat = v;
        })
      }
      .padding(this.embedded ? 0 : { left: 20, right: 20, top: 4, bottom: 24 })
  }
}

/** Selectable list used for quality / line choice. */
@ComponentV2
export struct OptionList {
  @Param options: string[] = [];
  @Param selected: number = 0;
  @Event onPick: (i: number) => void = () => {
  };

  build() {
    List({ space: 4 }) {
      ForEach(this.options, (label: string, i: number) => {
        ListItem() {
          Row({ space: 10 }) {
            // The current choice is marked by an accent dot and text, not a filled block.
            Row()
              .width(6)
              .height(6)
              .borderRadius(Radius.pill)
              .backgroundColor(i === this.selected ? C.accent : Color.Transparent)
            Text(label)
              .fontSize(15)
              .fontWeight(i === this.selected ? FontWeight.Bold : FontWeight.Regular)
              .fontColor(i === this.selected ? C.accent : C.onMedia)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')
          .height(48)
          .padding({ left: 14, right: 14 })
          .borderRadius(Radius.md)
          .stateStyles({
            normal: { .backgroundColor(Color.Transparent) },
            pressed: { .backgroundColor('#1AFFFFFF') }
          })
          .onClick(() => this.onPick(i))
        }
      }, (label: string, i: number) => `${i}_${label}`)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 8, right: 8 })
    .scrollBar(BarState.Off)
  }
}
