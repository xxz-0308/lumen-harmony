import { LiveRoomItem } from '../core/model/Models';
import { C, formatOnline, Motion, Radius } from '../theme/Theme';
import { Avatar, NetImage, SiteBadge } from './Basics';
import { Nav } from '../app/Nav';
import { FollowStore } from '../app/Stores';
import { HeroSource } from '../room/HeroSources';
import { AppEnv } from '../app/AppEnv';
import { promptAction, SymbolGlyphModifier } from '@kit.ArkUI';

export function heroIdFor(scope: string, item: LiveRoomItem): string {
  return `hero_${scope}_${item.siteId}_${item.roomId}`;
}

/**
 * The primary room tile: 16:9 cover with an ambient bottom scrim, then avatar/title/meta.
 * The cover carries a geometryTransition id so it can morph into the player.
 */
@ComponentV2
export struct RoomCard {
  @Param item: LiveRoomItem = new LiveRoomItem();
  @Param scope: string = 'grid';
  @Param showSite: boolean = true;
  @Param live: boolean = true;
  @Param inactiveLabel: string = '未开播';
  @Param meta: string = '';
  @Local pressed: boolean = false;
  /** Window rect (vp) of the cover, where the room's player morphs from and back to. */
  private coverRect: number[] = [];
  private heroSource: HeroSource = new HeroSource();

  aboutToAppear(): void {
    this.syncHeroSource();
  }

  @Monitor('item', 'scope')
  syncHeroSource(): void {
    const id = heroIdFor(this.scope, this.item);
    if (this.heroSource.id !== id) this.heroSource.mount(id);
  }

  aboutToDisappear(): void {
    this.heroSource.unmount();
  }

  @Builder
  menu() {
    Menu() {
      if (FollowStore.inst.storageError.length > 0) {
        MenuItem({ content: FollowStore.inst.storageError })
      } else if (FollowStore.inst.isFollowed(this.item.siteId, this.item.roomId)) {
        MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.heart_slash')), content: '取消关注' })
          .onClick(() => {
            FollowStore.inst.unfollow(this.item.siteId, this.item.roomId);
            promptAction.showToast({ message: `已取消关注 ${this.item.userName}` });
          })
      } else {
        MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.heart')), content: '关注主播' })
          .onClick(() => {
            FollowStore.inst.followAnchor(this.item.siteId, this.item.roomId, this.item.userName, this.item.avatar,
              true);
            promptAction.showToast({ message: `已关注 ${this.item.userName}` });
          })
      }
    }
  }

  build() {
    Column({ space: 10 }) {
      Stack({ alignContent: Alignment.BottomStart }) {
        NetImage({ src: this.item.cover })
        Column()
          .width('100%')
          .height('50%')
          .linearGradient({ angle: 180, colors: [['#00000000', 0], ['#A6000000', 1]] })
        Row({ space: 4 }) {
          if (this.live) {
            SymbolGlyph($r('sys.symbol.flame_fill'))
              .fontSize(12)
              .fontColor(['#FFB27A'])
            Text(formatOnline(this.item.online))
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(C.onMedia)
              .fontFeature('"tnum" on')
          } else {
            Text(this.inactiveLabel)
              .fontSize(12)
              .fontColor(C.onMedia2)
          }
          Blank()
          if (this.item.area.length > 0) {
            Text(this.item.area)
              .fontSize(11)
              .fontColor(C.onMedia2)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: '50%' })
          }
        }
        .width('100%')
        .padding({ left: 10, right: 10, bottom: 8 })

        if (this.showSite) {
          SiteBadge({ siteId: this.item.siteId })
            .position({ x: 8, y: 8 })
        }
      }
      .width('100%')
      .aspectRatio(16 / 9)
      .borderRadius(Radius.lg)
      .clip(true)
      .onVisibleAreaChange([0, 1], (visible: boolean, ratio: number) => {
        this.heroSource.setVisible(visible && ratio >= 1);
      })
      .onAreaChange((_old: Area, area: Area) => {
        this.heroSource.setBounds(`${area.globalPosition.x},${area.globalPosition.y},${area.width},${area.height}`);
        this.coverRect = [area.globalPosition.x as number, area.globalPosition.y as number,
          area.width as number, area.height as number];
      })

      Row({ space: 10 }) {
        Avatar({ src: this.item.avatar, dim: 30 })
        Column({ space: 3 }) {
          Text(this.item.title.length > 0 ? this.item.title : this.item.userName)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(C.text1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.meta.length > 0 ? this.meta : this.item.userName)
            .fontSize(12)
            .fontColor(C.text2)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding({ left: 2, right: 2 })
    }
    .id(`room_${this.scope}_${this.item.siteId}_${this.item.roomId}`)
    .width('100%')
    .renderGroup(true)
    .scale({ x: this.pressed && !AppEnv.inst.reduceMotion ? 0.965 : 1,
      y: this.pressed && !AppEnv.inst.reduceMotion ? 0.965 : 1 })
    .opacity(this.pressed ? 0.9 : 1)
    .animation({ curve: Motion.snappy })
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Down) {
        this.pressed = true;
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.pressed = false;
      }
    })
    .onClick(() => {
      Nav.openLive(this.item, '', this.coverRect);
    })
    .bindContextMenu(this.menu(), ResponseType.LongPress)
  }
}
