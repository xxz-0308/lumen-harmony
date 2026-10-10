import { LengthMetrics } from '@kit.ArkUI';
import { LiveAnchorItem, LiveRoomItem } from '../core/model/Models';
import { SearchMode, SiteResult } from '../app/SearchModel';
import { AppEnv } from '../app/AppEnv';
import { C, Radius, SiteStyle, Space } from '../theme/Theme';
import { RoomCard } from '../components/RoomCard';
import { AnchorTile } from '../components/AnchorTile';
import { RoomCardSkeleton, Shimmer, SiteBadge } from '../components/Basics';

/** One platform owns its result updates; other completions do not remount this list. */
@ComponentV2
export struct SearchSiteRow {
  @Param result: SiteResult = new SiteResult('huya');
  @Param revision: number = 0;
  @Param mode: SearchMode = 'room';
  @Param filter: string = 'all';
  @Param tileW: number = 280;
  @Event onMore: () => void = () => {};
  @Event onRetry: (result: SiteResult) => void = () => {};
  @Local loading: boolean = false;
  @Local error: string = '';
  @Local rooms: LiveRoomItem[] = [];
  @Local anchors: LiveAnchorItem[] = [];

  aboutToAppear(): void {
    this.sync();
  }

  @Monitor('result', 'revision')
  onResult(): void {
    this.sync();
  }

  private sync(): void {
    this.loading = this.result.loading;
    this.error = this.result.error;
    this.rooms = this.result.rooms;
    this.anchors = this.result.anchors;
  }

  get count(): number {
    return this.rooms.length + this.anchors.length;
  }

  @Builder
  failure() {
    Row({ space: 10 }) {
      Text(this.error).fontSize(14).fontColor(C.text2).layoutWeight(1)
      Button('重试', { type: ButtonType.Normal })
        .fontSize(14).fontColor(C.accent).height(48)
        .backgroundColor(Color.Transparent)
        .onClick(() => this.onRetry(this.result))
    }
    .width('100%')
    .constraintSize({ minHeight: 48 })
  }

  build() {
    Column({ space: 14 }) {
      Row({ space: 10 }) {
        SiteBadge({ siteId: this.result.siteId, onMedia: false })
        if (this.loading && this.count > 0) {
          LoadingProgress().width(16).height(16).color(C.text3)
          Text('更新中').fontSize(13).fontColor(C.text3)
        } else if (!this.loading && this.error.length === 0) {
          Text(`${this.count} 个结果`).fontSize(13).fontColor(C.text3)
        }
        Blank()
        if (this.count > 0) {
          Button({ type: ButtonType.Normal }) {
            Row({ space: 2 }) {
              Text('更多').fontSize(13).fontColor(C.text2)
              SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor([C.text2])
            }
          }
          .height(48)
          .padding({ left: 8, right: 8 })
          .backgroundColor(Color.Transparent)
          .onClick(() => this.onMore())
        }
      }
      .width('100%')
      if (this.error.length > 0) {
        this.failure()
      }
      if (this.count === 0 && this.loading) {
        Row({ space: Space.md }) {
          ForEach([0, 1, 2, 3], (i: number) => {
            Column() {
              if (this.mode === 'room') {
                RoomCardSkeleton()
              } else {
                Shimmer({ radius: Radius.lg }).height(72)
              }
            }
            .width(this.mode === 'room' ? 260 : this.tileW)
          }, (i: number) => `sk${i}`)
        }
        .width('100%')
        .clip(true)
      } else if (this.count === 0 && this.error.length === 0) {
        Text('没有找到相关结果').fontSize(14).fontColor(C.text3).height(48)
      } else if (this.count > 0 && this.mode === 'room') {
        List({ space: Space.md }) {
          Repeat<LiveRoomItem>(this.rooms.slice(0, 12))
            .each((item: RepeatItem<LiveRoomItem>) => {
              ListItem() {
                RoomCard({ item: item.item, scope: 'search', showSite: false }).width(260)
              }
            })
            .key((item: LiveRoomItem) => `${item.siteId}_${item.roomId}`)
        }
        .listDirection(Axis.Horizontal)
        .scrollBar(BarState.Off)
        .height(210)
        .width('100%')
        .clip(false)
      } else if (this.count > 0) {
        Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(Space.md), cross: LengthMetrics.vp(Space.md) } }) {
          Repeat<LiveAnchorItem>(this.anchors.slice(0, this.filter === 'all' ? 6 : 60))
            .each((item: RepeatItem<LiveAnchorItem>) => {
              AnchorTile({
                siteId: item.item.siteId, roomId: item.item.roomId,
                userName: item.item.userName, avatar: item.item.avatar, live: item.item.liveStatus,
                subtitle: item.item.liveStatus ? '直播中' : `${SiteStyle.label(item.item.siteId)} · 未开播`
              })
                .width(this.tileW)
            })
            .key((item: LiveAnchorItem) => `${item.siteId}_${item.roomId}`)
        }
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .transition(TransitionEffect.OPACITY.animation({ duration: AppEnv.inst.reduceMotion ? 0 : 240 }))
  }
}
