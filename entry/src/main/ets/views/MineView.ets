import { LengthMetrics } from '@kit.ArkUI';
import { AppEnv } from '../app/AppEnv';
import { HistoryItem, HistoryStore } from '../app/Stores';
import { Settings } from '../app/Settings';
import { Nav } from '../app/Nav';
import { C, Layout, Motion, Radius, relativeTime, Space } from '../theme/Theme';
import { RoomCard } from '../components/RoomCard';
import { SectionTitle } from '../components/Decor';
import { StateView } from '../components/Basics';

/**
 * Lumen Editorial MineView:
 * Spacious 3-column borderless recent watch gallery + 2 clean borderless surface cards
 * for Account & Preferences.
 */
@ComponentV2
export struct MineView {
  @Param active: boolean = true;
  @Local areaW: number = AppEnv.inst.winWidth;
  @Local recent: HistoryItem[] = [];
  @Local historyError: string = '';
  @Local accountLabel: string = '';
  @Local pressedCard: string = '';
  private mounted: boolean = false;
  private syncHistory: () => void = () => {
    if (!this.mounted || !this.active) return;
    this.recent = HistoryStore.inst.items.slice(0, 3);
    this.historyError = HistoryStore.inst.storageError || HistoryStore.inst.saveError;
  };
  private syncAccount: () => void = () => {
    if (!this.mounted || !this.active) return;
    const s = Settings.inst;
    this.accountLabel = s.accountError || (s.biliExpired ? '哔哩哔哩登录已过期，请重新扫码' :
      (s.biliUid > 0 ? `哔哩哔哩 · ${s.biliName || '已登录'}` : '哔哩哔哩未登录 · 扫码可申请原画画质'));
  };

  @Monitor('active')
  onActive(): void {
    if (this.active) {
      this.syncHistory();
      this.syncAccount();
    } else {
      this.pressedCard = '';
    }
  }

  aboutToAppear(): void {
    this.mounted = true;
    HistoryStore.inst.subscribe(this.syncHistory);
    Settings.inst.subscribeAccount(this.syncAccount);
    this.syncHistory();
    this.syncAccount();
  }

  aboutToDisappear(): void {
    this.mounted = false;
    HistoryStore.inst.unsubscribe(this.syncHistory);
    Settings.inst.unsubscribeAccount(this.syncAccount);
  }

  get contentW(): number { return Math.max(160, this.areaW - Space.page * 2); }
  get compact(): boolean { return this.contentW < 760; }
  get columns(): number { return Math.min(3, Layout.columns(this.contentW, 320, Space.xl)); }
  get cardW(): number { return (this.contentW - Space.xl * (this.columns - 1)) / this.columns; }

  @Builder
  entryCard(key: string, icon: Resource, title: string, subtitle: string, action: () => void) {
    Row({ space: 18 }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph(icon)
          .fontSize(22)
          .fontColor([C.text1])
      }
      .width(48)
      .height(48)
      .borderRadius(16)
      .backgroundColor(C.surface2)

      Column({ space: 5 }) {
        Text(title)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(C.text1)
        Text(subtitle)
          .fontSize(13)
          .fontColor(C.text2)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([C.text3])
    }
    .layoutWeight(this.compact ? 0 : 1)
    .width(this.compact ? '100%' : undefined)
    .padding({ left: 24, right: 24, top: 22, bottom: 22 })
    .borderRadius(Radius.xl)
    .backgroundColor(C.surface)
    .scale({
      x: this.pressedCard === key && !AppEnv.inst.reduceMotion ? 0.98 : 1,
      y: this.pressedCard === key && !AppEnv.inst.reduceMotion ? 0.98 : 1
    })
    .animation({ curve: Motion.snappy })
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Down) this.pressedCard = key;
      else if (e.type === TouchType.Up || e.type === TouchType.Cancel) this.pressedCard = '';
    })
    .onClick(() => action())
  }

  build() {
    Scroll() {
      Column({ space: Space.xxl }) {
        Row() {
          Text('我的')
            .fontSize(34)
            .fontWeight(FontWeight.Bolder)
            .fontColor(C.text1)
            .letterSpacing(-0.5)
          Blank()
        }
        .width('100%')

        // 1. Spacious 3-Column Borderless Recent Watch Gallery
        Column({ space: 20 }) {
          Row() {
            SectionTitle({ title: '最近观看', subtitle: '继续上次的直播间' })
            Blank()
            Text('全部历史')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(C.text2)
              .padding({ left: 12, right: 4, top: 6, bottom: 6 })
              .onClick(() => Nav.openHistory())
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          if (this.historyError.length > 0) {
            Text(this.historyError).fontSize(13).fontColor(C.live)
          }
          if (this.recent.length === 0) {
            StateView({
              icon: $r('sys.symbol.clock'),
              title: this.historyError.length > 0 ? '历史数据暂不可用' : '还没有观看记录',
              subtitle: '看过的直播间会出现在这里'
            })
              .width('100%')
          } else {
            Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(Space.xl), cross: LengthMetrics.vp(Space.xl) } }) {
              ForEach(this.recent, (h: HistoryItem) => {
                RoomCard({
                  item: h.toRoomItem(),
                  scope: 'mine_recent',
                  live: false,
                  inactiveLabel: '看过',
                  meta: `${h.userName} · ${relativeTime(h.watchedAt)}`
                }).width(this.cardW)
              }, (h: HistoryItem) => h.key)
            }
            .width('100%')
          }
        }
        .width('100%')

        // 2. Two Clean Borderless Surface Cards for Account & Settings
        Column({ space: 18 }) {
          SectionTitle({ title: '偏好与账号' })
          if (this.compact) {
            Column({ space: 16 }) {
              this.entryCard('account', $r('sys.symbol.person_crop_circle_fill_1'), '账号', this.accountLabel,
                () => Nav.openAccount())
              this.entryCard('settings', $r('sys.symbol.slider_horizontal_2'), '设置', '外观、播放内核、弹幕与屏蔽词',
                () => Nav.openSettings())
            }
            .width('100%')
          } else {
            Row({ space: Space.xl }) {
              this.entryCard('account', $r('sys.symbol.person_crop_circle_fill_1'), '账号', this.accountLabel,
                () => Nav.openAccount())
              this.entryCard('settings', $r('sys.symbol.slider_horizontal_2'), '设置', '外观、播放内核、弹幕与屏蔽词',
                () => Nav.openSettings())
            }
            .width('100%')
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({
        left: Space.page,
        right: Space.page,
        top: AppEnv.inst.statusBarHeight + 16,
        bottom: Layout.bottomNavInset
      })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .onAreaChange((_o: Area, n: Area) => { this.areaW = n.width as number; })
  }
}
