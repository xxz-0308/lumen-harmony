import { LengthMetrics } from '@kit.ArkUI';
import { AppEnv } from '../app/AppEnv';
import { HistoryItem, HistoryStore } from '../app/Stores';
import { Settings } from '../app/Settings';
import { Nav } from '../app/Nav';
import { C, Layout, Radius, relativeTime, Space } from '../theme/Theme';
import { RoomCard } from '../components/RoomCard';
import { PageTitle, SectionTitle } from '../components/Decor';
import { StateView } from '../components/Basics';

@ComponentV2
export struct MineView {
  @Local areaW: number = AppEnv.inst.winWidth;
  @Local recent: HistoryItem[] = [];
  @Local historyError: string = '';
  @Local accountLabel: string = '';
  private syncHistory: () => void = () => {
    this.recent = HistoryStore.inst.items.slice(0, 4);
    this.historyError = HistoryStore.inst.storageError || HistoryStore.inst.saveError;
  };
  private syncAccount: () => void = () => {
    const s = Settings.inst;
    this.accountLabel = s.accountError || (s.biliExpired ? 'B站登录已过期，请重新登录' :
      (s.biliUid > 0 ? `哔哩哔哩 · ${s.biliName || '已登录'}` : '哔哩哔哩扫码登录'));
  };

  aboutToAppear(): void {
    HistoryStore.inst.subscribe(this.syncHistory);
    Settings.inst.subscribeAccount(this.syncAccount);
    this.syncHistory();
    this.syncAccount();
  }

  aboutToDisappear(): void {
    HistoryStore.inst.unsubscribe(this.syncHistory);
    Settings.inst.unsubscribeAccount(this.syncAccount);
  }

  get contentW(): number { return Math.max(160, this.areaW - Space.page * 2); }
  get columns(): number { return Math.min(4, Layout.columns(this.contentW, 236, Space.lg)); }
  get cardW(): number { return (this.contentW - Space.lg * (this.columns - 1)) / this.columns; }

  @Builder
  entry(title: string, subtitle: string, icon: Resource, action: () => void) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 16 }) {
        SymbolGlyph(icon).fontSize(22).fontColor([C.accent])
        Column({ space: 5 }) {
          Text(title).fontSize(17).fontWeight(FontWeight.Medium).fontColor(C.text1)
          Text(subtitle).fontSize(13).fontColor(C.text2)
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16).fontColor([C.text3])
      }
      .width('100%')
      .padding(Space.lg)
    }
    .width('100%')
    .constraintSize({ minHeight: Layout.touchTarget })
    .padding(0)
    .borderRadius(Radius.lg)
    .backgroundColor(C.bgElevated)
    .borderWidth(1)
    .borderColor(C.stroke)
    .accessibilityText(`${title}，${subtitle}`)
    .onClick(action)
  }

  build() {
    Scroll() {
      Column({ space: Space.xl }) {
        PageTitle({ title: '我的', subtitle: '继续观看，也照顾自己的偏好' })
        Row({ space: 8 }) {
          SectionTitle({ title: '最近观看' }).layoutWeight(1)
          Button('全部历史', { type: ButtonType.Normal })
            .height(Layout.touchTarget)
            .fontSize(14)
            .fontColor(C.accent)
            .backgroundColor(C.accentSoft)
            .borderRadius(Radius.pill)
            .onClick(() => Nav.openHistory())
        }
        .width('100%')
        if (this.historyError.length > 0) {
          Text(this.historyError).fontSize(13).fontColor(C.live)
        }
        if (this.recent.length === 0) {
          StateView({ icon: $r('sys.symbol.clock'),
            title: this.historyError.length > 0 ? '历史数据暂不可用' : '还没有观看记录',
            subtitle: '看过的直播间会出现在这里' }).width('100%')
        } else {
          Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(Space.lg), cross: LengthMetrics.vp(Space.xl) } }) {
            ForEach(this.recent, (h: HistoryItem) => {
              RoomCard({ item: h.toRoomItem(), scope: 'mine_recent', live: false, inactiveLabel: '看过',
                meta: `${h.userName} · ${relativeTime(h.watchedAt)}` }).width(this.cardW)
            }, (h: HistoryItem) => h.key)
          }
          .width('100%')
        }
        this.entry('账号', this.accountLabel, $r('sys.symbol.person'), () => Nav.openAccount())
        this.entry('设置', '外观、播放与弹幕偏好', $r('sys.symbol.gearshape'), () => Nav.openSettings())
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: Space.page, right: Space.page, top: AppEnv.inst.statusBarHeight + 24,
        bottom: Layout.bottomNavInset })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .onAreaChange((o: Area, n: Area) => { this.areaW = n.width as number; })
  }
}
