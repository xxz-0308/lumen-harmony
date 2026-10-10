import { LengthMetrics } from '@kit.ArkUI';
import { LinkParser, RoomRef } from '../core/sites/Sites';
import { SearchMode, SearchModel, SiteResult } from '../app/SearchModel';
import { RoomFeed } from '../app/RoomFeed';
import { Settings } from '../app/Settings';
import { AppEnv } from '../app/AppEnv';
import { Nav } from '../app/Nav';
import { C, Layout, Motion, Radius, SiteStyle, Space } from '../theme/Theme';
import { Segmented, StateView } from '../components/Basics';
import { SearchSiteRow } from './SearchSiteRow';
import { FilterChip } from '../components/Decor';
import { RoomGrid } from '../components/RoomGrid';

@ComponentV2
export struct SearchView {
  @Param topPadding: number = Space.md;
  @Param active: boolean = false;
  @Local m: SearchModel = SearchModel.inst;
  @Local input: string = '';
  @Local areaW: number = 1100;
  @Local focused: boolean = false;
  /** Mirrors of the shared model; observing its @Trace fields from a component is unreliable. */
  @Local searched: boolean = false;
  @Local mode: SearchMode = 'room';
  @Local filter: string = 'all';
  @Local results: SiteResult[] = [];
  @Local feed: RoomFeed | null = null;
  @Local keyword: string = '';
  @Local history: string[] = [];
  @Local bodyW: number = 0;
  private mounted: boolean = false;
  private onModelUpdate: () => void = () => this.sync();

  @Monitor('active')
  onActive(): void {
    if (this.active) {
      this.history = Settings.inst.searchHistory.slice();
    }
  }

  aboutToAppear(): void {
    this.mounted = true;
    this.input = this.m.keyword;
    this.m.onUpdate = this.onModelUpdate;
    this.sync();
  }

  aboutToDisappear(): void {
    this.mounted = false;
    if (this.m.onUpdate === this.onModelUpdate) this.m.onUpdate = null;
  }

  private sync(): void {
    if (!this.mounted) return;
    this.searched = this.m.searched;
    this.mode = this.m.mode;
    this.filter = this.m.filter;
    this.keyword = this.m.keyword;
    this.results = this.m.results.slice();
    this.feed = this.m.feed;
    this.history = Settings.inst.searchHistory.slice();
  }

  get contentW(): number {
    return Math.max(160, this.areaW - Space.page * 2);
  }

  get centerInset(): number {
    return Math.max(0, (this.contentW - 980) / 2);
  }

  get tileW(): number {
    const width = this.bodyW > 0 ? this.bodyW : this.contentW - this.centerInset * 2;
    const cols = Layout.columns(width, 280, Space.md);
    return (width - Space.md * (cols - 1)) / cols;
  }

  get links(): RoomRef[] {
    return LinkParser.parse(this.input);
  }

  private submit(): void {
    if (this.input.trim().length === 0) {
      return;
    }
    this.m.search(this.input);
  }

  @Builder
  searchBar() {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(20)
          .fontColor([this.focused ? C.accent : C.text3])
        TextInput({ text: this.input, placeholder: '搜索直播间、主播，或粘贴直播间链接' })
          .id('searchInput')
          .layoutWeight(1)
          .height(52)
          .fontSize(17)
          .fontColor(C.text1)
          .placeholderColor(C.text3)
          .backgroundColor(Color.Transparent)
          .padding(0)
          .caretColor(C.accent)
          .enterKeyType(EnterKeyType.Search)
          .onChange((v: string) => {
            this.input = v;
          })
          .onSubmit(() => this.submit())
          .onFocus(() => {
            this.focused = true;
          })
          .onBlur(() => {
            this.focused = false;
          })
        if (this.input.length > 0) {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
              .fontSize(20)
              .fontColor([C.text3])
          }
            .width(44)
            .height(44)
            .backgroundColor(Color.Transparent)
            .accessibilityText('清空搜索内容')
            .onClick(() => {
              this.input = '';
              this.m.clear();
            })
            .transition(TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.6, y: 0.6 }))
              .animation({ curve: Motion.snappy }))
        }
      }
      .width('100%')
      .height(56)
      .padding({ left: 18, right: 16 })
      .borderRadius(Radius.pill)
      .backgroundColor(C.bgElevated)
      .borderWidth(1.5)
      .borderColor(this.focused ? C.accent : C.stroke)
      .shadow(this.focused ? { radius: 24, color: C.accentGlow, offsetY: 6 } : { radius: 12, color: '#14000000', offsetY: 4 })
      .animation({ curve: Motion.snappy })

      Row({ space: 12 }) {
        Button('搜索', { type: ButtonType.Normal })
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .height(48)
          .padding({ left: 20, right: 20 })
          .borderRadius(Radius.pill)
          .backgroundColor(C.accent)
          .enabled(this.input.trim().length > 0)
          .opacity(this.input.trim().length > 0 ? 1 : 0.45)
          .onClick(() => this.submit())

        Blank()
        Segmented({
          items: ['直播间', '主播'],
          selected: this.mode === 'room' ? 0 : 1,
          segmentWidth: 76,
          barHeight: 48,
          onSelect: (i: number) => this.m.setMode(i === 0 ? 'room' : 'anchor')
        })
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  linkCards() {
    if (this.links.length > 0) {
      Row({ space: 10 }) {
        SymbolGlyph($r('sys.symbol.link'))
          .fontSize(18)
          .fontColor([C.accent])
        Text(this.links.length === 1 ? '识别到直播间' : '按房间号直接打开')
          .fontSize(14)
          .fontColor(C.text2)
        ForEach(this.links, (r: RoomRef) => {
          Row({ space: 6 }) {
            Row()
              .width(7)
              .height(7)
              .borderRadius(4)
              .backgroundColor(SiteStyle.color(r.siteId))
            Text(`${SiteStyle.label(r.siteId)} ${r.roomId}`)
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(C.text1)
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(14)
              .fontColor([C.text2])
          }
          .id(`direct_${r.siteId}_${r.roomId}`)
          .height(44)
          .padding({ left: 14, right: 10 })
          .borderRadius(Radius.pill)
          .backgroundColor(C.surface2)
          .onClick(() => Nav.openRoom(r.siteId, r.roomId))
        }, (r: RoomRef) => `${r.siteId}_${r.roomId}`)
      }
      .width('100%')
      .padding(14)
      .borderRadius(Radius.lg)
      .backgroundColor(C.accentSoft)
      .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -8 }))
        .animation({ curve: Motion.smooth }))
    }
  }

  @Builder
  historyBlock() {
    if (this.history.length > 0) {
      Column({ space: 14 }) {
        Row() {
          Text('搜索记录')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(C.text1)
          Blank()
          Text('清除')
            .fontSize(13)
            .fontColor(C.text3)
            .height(48)
            .padding({ left: 12, right: 12 })
            .onClick(() => {
              Settings.inst.searchHistory = [];
              this.history = [];
              Settings.inst.scheduleSave();
            })
        }
        .width('100%')
        Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(10), cross: LengthMetrics.vp(10) } }) {
          ForEach(this.history, (k: string) => {
            Text(k)
              .fontSize(14)
              .fontColor(C.text1)
              .height(36)
              .padding({ left: 16, right: 16 })
              .borderRadius(Radius.pill)
              .backgroundColor(C.surface2)
              .onClick(() => {
                this.input = k;
                this.m.search(k);
              })
          }, (k: string) => k)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    } else {
      Row() {
        StateView({
          icon: $r('sys.symbol.magnifyingglass'),
          title: '一次搜遍三个平台',
          subtitle: '虎牙、斗鱼、B站同时搜索；也可以直接粘贴直播间链接或输入房间号'
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .margin({ top: 40 })
    }
  }

  @Builder
  filters() {
    Row({ space: 8 }) {
      FilterChip({
        label: '全部',
        selected: this.filter === 'all',
        onTap: () => this.m.setFilter('all')
      })
      Repeat<SiteResult>(this.results)
        .each((r: RepeatItem<SiteResult>) => {
          FilterChip({
            label: `${SiteStyle.label(r.item.siteId)}${r.item.loading ? '' : ' ' + r.item.count}`,
            selected: this.filter === r.item.siteId,
            dotColor: SiteStyle.color(r.item.siteId),
            onTap: () => this.m.setFilter(r.item.siteId)
          })
        })
        .key((r: SiteResult) => r.siteId)
    }
  }

  @Builder
  header() {
    Column({ space: Space.xl }) {
      this.searchBar()
      this.linkCards()
      if (this.searched) {
        this.filters()
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ bottom: 8 })
    .onAreaChange((o: Area, n: Area) => {
      this.bodyW = n.width as number;
    })
  }

  build() {
    Column() {
      if (this.searched && this.filter !== 'all' && this.mode === 'room' && this.feed !== null) {
        RoomGrid({ feed: this.feed, active: this.active, scope: 'search_full', topPadding: this.topPadding,
          inset: this.centerInset, rightInset: Space.page + this.centerInset }) {
          this.header()
        }
      } else {
        Scroll() {
          Column({ space: Space.xxl }) {
            this.header()
            if (!this.searched) {
              this.historyBlock()
            } else if (this.filter === 'all') {
              Repeat<SiteResult>(this.results)
                .each((r: RepeatItem<SiteResult>) => {
                  SearchSiteRow({ result: r.item, revision: r.item.revision, mode: this.mode,
                    filter: this.filter, tileW: this.tileW,
                    onMore: () => this.m.setFilter(r.item.siteId), onRetry: (result: SiteResult) => this.m.retry(result) })
                })
                .key((r: SiteResult) => `${this.keyword}_${this.mode}_${r.siteId}`)
            } else {
              Repeat<SiteResult>(this.results.filter((r: SiteResult) => r.siteId === this.filter))
                .each((r: RepeatItem<SiteResult>) => {
                  SearchSiteRow({ result: r.item, revision: r.item.revision, mode: this.mode,
                    filter: this.filter, tileW: this.tileW,
                    onMore: () => this.m.setFilter(r.item.siteId), onRetry: (result: SiteResult) => this.m.retry(result) })
                })
                .key((r: SiteResult) => `${this.keyword}_${this.mode}_${r.siteId}`)
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({
            left: Space.page + this.centerInset,
            right: Space.page + this.centerInset,
            top: this.topPadding,
            bottom: Layout.pageBottom
          })
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .align(Alignment.Top)
      }
    }
    .width('100%')
    .height('100%')
    .onAreaChange((o: Area, n: Area) => {
      this.areaW = n.width as number;
    })
  }
}
