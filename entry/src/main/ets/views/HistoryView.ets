import { promptAction } from '@kit.ArkUI';
import { HistoryItem, HistoryStore } from '../app/Stores';
import { AppEnv } from '../app/AppEnv';
import { C, Layout, Radius, relativeTime, Space } from '../theme/Theme';
import { RoomCard } from '../components/RoomCard';
import { StateView } from '../components/Basics';
import { PageTitle, SectionTitle } from '../components/Decor';
import { Appear } from '../components/RoomGrid';

class DayGroup {
  title: string = '';
  items: HistoryItem[] = [];
}

function startOfDay(ms: number): number {
  const d = new Date(ms);
  d.setHours(0, 0, 0, 0);
  return d.getTime();
}

@ComponentV2
export struct HistoryView {
  @Param topPadding: number = Space.md;
  @Local areaW: number = 1100;
  @Local entries: HistoryItem[] = HistoryStore.inst.items;
  @Local storageError: string = HistoryStore.inst.storageError;
  @Local saveError: string = HistoryStore.inst.saveError;
  private syncEntries: () => void = () => {
    this.entries = HistoryStore.inst.items;
    this.storageError = HistoryStore.inst.storageError;
    this.saveError = HistoryStore.inst.saveError;
  };

  aboutToAppear(): void {
    HistoryStore.inst.subscribe(this.syncEntries);
    this.syncEntries();
  }

  aboutToDisappear(): void {
    HistoryStore.inst.unsubscribe(this.syncEntries);
  }

  get contentW(): number {
    return Math.max(160, this.areaW - Space.page * 2);
  }

  get cols(): number {
    return Layout.columns(this.contentW, 236, Space.lg);
  }

  get cardW(): number {
    return (this.contentW - Space.lg * (this.cols - 1)) / this.cols;
  }

  @Computed
  get groups(): DayGroup[] {
    const today = startOfDay(Date.now());
    const day = 24 * 3600 * 1000;
    const out: DayGroup[] = [];
    const bucket = (title: string): DayGroup => {
      let g = out.find((x: DayGroup) => x.title === title);
      if (g === undefined) {
        g = new DayGroup();
        g.title = title;
        out.push(g);
      }
      return g;
    };
    for (const h of this.entries) {
      const title = h.watchedAt >= today ? '今天' : h.watchedAt >= today - day ? '昨天' :
        h.watchedAt >= today - 7 * day ? '本周' : '更早';
      bucket(title).items.push(h);
    }
    return out;
  }

  private confirmClear(): void {
    promptAction.showDialog({
      title: '清空观看历史？',
      message: '此操作无法撤销',
      buttons: [{ text: '取消', color: '#99999999' }, { text: '清空', color: C.accentHighlight }]
    }).then((r: promptAction.ShowDialogSuccessResponse) => {
      if (r.index === 1) {
        HistoryStore.inst.clear();
        if (HistoryStore.inst.storageError.length > 0) {
          promptAction.showToast({ message: HistoryStore.inst.storageError });
        }
      }
    }).catch(() => {
    });
  }

  @Builder
  trailing() {
    if (this.entries.length > 0 && this.storageError.length === 0) {
      Button('清空', { type: ButtonType.Normal })
        .height(Layout.touchTarget)
        .fontSize(14)
        .fontColor(C.text2)
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .borderRadius(Radius.pill)
        .backgroundColor(C.surface2)
        .onClick(() => this.confirmClear())
    }
  }

  private rowStarts(count: number): number[] {
    const out: number[] = [];
    for (let i = 0; i < count; i += this.cols) {
      out.push(i);
    }
    return out;
  }

  /** Bound each virtual ListItem to one row instead of mounting 200 cards in a day group. */
  @Builder
  dayRow(g: DayGroup, start: number) {
    Row({ space: Space.lg }) {
      ForEach(g.items.slice(start, start + this.cols), (h: HistoryItem, i: number) => {
        Column() {
          Appear({ delay: start + i < 12 ? (start + i) * 30 : 0 }) {
            RoomCard({
              item: h.toRoomItem(),
              scope: 'history',
              live: false,
              inactiveLabel: '看过',
              meta: `${h.userName} · ${relativeTime(h.watchedAt)}`
            })
          }
        }
        .width(this.cardW)
      }, (h: HistoryItem) => h.key)
    }
    .width('100%')
  }

  @Builder
  dayHeader(g: DayGroup) {
    SectionTitle({ title: g.title, subtitle: `${g.items.length}` })
  }

  build() {
    // A plain Scroll+Column mounts every card at once; the list virtualizes long histories.
    List({ space: Space.xl }) {
      ListItem() {
        PageTitle({
          title: '',
          subtitle: this.storageError.length > 0 ? this.storageError :
            (this.saveError.length > 0 ? this.saveError :
              (this.entries.length > 0 ? `最近看过的 ${this.entries.length} 个直播间` : ''))
        }) {
          this.trailing()
        }
      }
      if (this.entries.length === 0) {
        ListItem() {
          StateView({
            icon: $r('sys.symbol.clock'),
            title: this.storageError.length > 0 ? '历史数据暂不可用' : '还没有观看记录',
            subtitle: this.storageError.length > 0 ? this.storageError : '看过的直播间会出现在这里'
          })
            .width('100%')
            .margin({ top: 60 })
        }
      }
      ForEach(this.groups, (g: DayGroup) => {
        ListItemGroup({ header: this.dayHeader(g), space: Space.xl }) {
          ForEach(this.rowStarts(g.items.length), (start: number) => {
            ListItem() {
              this.dayRow(g, start)
            }
          }, (start: number) => `${g.title}_${start}`)
        }
      }, (g: DayGroup) => g.title)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .alignListItem(ListItemAlign.Start)
    .cachedCount(4)
    // Padding on a List clips its viewport; the end offset lets cards scroll to the screen edge.
    .padding({
      left: Space.page,
      right: Space.page,
      top: this.topPadding
    })
    .contentEndOffset(Layout.pageBottom)
    .onAreaChange((o: Area, n: Area) => {
      this.areaW = n.width as number;
    })
  }
}
