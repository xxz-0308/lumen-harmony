import { LiveRoomItem } from '../core/model/Models';
import { C, formatOnline, Motion, Radius, SiteStyle } from '../theme/Theme';
import { Avatar, NetImage } from './Basics';
import { Nav } from '../app/Nav';
import { FollowStore } from '../app/Stores';
import { AppEnv } from '../app/AppEnv';
import { promptAction, SymbolGlyphModifier } from '@kit.ArkUI';

/**
 * Lumen Editorial Room Card:
 * Supports both standard 3-Up gallery cards and 2-Up featured spotlight cards (`featured = true`).
 * Borderless 16:9 floating artwork with soft elevation shadow, minimal bottom-left live viewer
 * indicator, and clean editorial typography below.
 */
@ComponentV2
export struct RoomCard {
  @Param item: LiveRoomItem = new LiveRoomItem();
  @Param scope: string = 'grid';
  @Param showSite: boolean = true;
  @Param live: boolean = true;
  @Param featured: boolean = false;
  @Param inactiveLabel: string = '未开播';
  @Param meta: string = '';
  @Local pressed: boolean = false;
  private coverRect: number[] = [];

  get subtitleText(): string {
    if (this.meta.length > 0) {
      return this.meta;
    }
    const parts: string[] = [this.item.userName];
    if (this.showSite) {
      parts.push(SiteStyle.label(this.item.siteId));
    }
    if (this.item.area.length > 0) {
      parts.push(this.item.area);
    }
    return parts.join(' · ');
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
    Column({ space: this.featured ? 14 : 12 }) {
      Stack({ alignContent: Alignment.BottomStart }) {
        NetImage({
          src: this.item.cover,
          decodeW: this.featured ? 640 : 360,
          decodeH: this.featured ? 320 : 202
        })
        Column()
          .width('100%')
          .height(this.featured ? '62%' : '46%')
          .linearGradient({ angle: 180, colors: [['#00000000', 0], [this.featured ? '#D908080A' : '#B8000000', 1]] })

        if (this.featured) {
          Column({ space: 6 }) {
            Row({ space: 6 }) {
              Row()
                .width(6)
                .height(6)
                .borderRadius(999)
                .backgroundColor(C.live)
              Text(`${formatOnline(this.item.online)} · ${this.item.area.length > 0 ? this.item.area : SiteStyle.label(this.item.siteId)}`)
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor('#D9FFFFFF')
                .fontFeature('"tnum" on')
            }
            Text(this.item.title.length > 0 ? this.item.title : this.item.userName)
              .fontSize(19)
              .fontWeight(FontWeight.Bolder)
              .fontColor(C.onMedia)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding({ left: 18, right: 18, bottom: 16 })
        } else {
          Row({ space: 6 }) {
            if (this.live) {
              Row()
                .width(6)
                .height(6)
                .borderRadius(999)
                .backgroundColor(C.live)
              Text(formatOnline(this.item.online))
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor(C.onMedia)
                .fontFeature('"tnum" on')
            } else {
              Text(this.inactiveLabel)
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor(C.onMedia2)
            }
          }
          .padding({ left: 14, right: 14, bottom: 12 })
        }
      }
      .width('100%')
      .aspectRatio(this.featured ? 18 / 9 : 16 / 9)
      .borderRadius(this.featured ? Radius.xl : Radius.lg)
      .clip(true)
      .shadow({ radius: this.featured ? 28 : 22, color: C.shadow, offsetY: 10 })
      .onAreaChange((_old: Area, area: Area) => {
        this.coverRect = [area.globalPosition.x as number, area.globalPosition.y as number,
          area.width as number, area.height as number];
      })

      Row({ space: 12 }) {
        Avatar({ src: this.item.avatar, dim: this.featured ? 36 : 34, live: false })
        if (this.featured) {
          Text(this.subtitleText)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(C.text2)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        } else {
          Column({ space: 4 }) {
            Text(this.item.title.length > 0 ? this.item.title : this.item.userName)
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(C.text1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.subtitleText)
              .fontSize(12)
              .fontColor(C.text2)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
      }
      .width('100%')
      .padding({ left: 2, right: 2 })
    }
    .id(`room_${this.scope}_${this.item.siteId}_${this.item.roomId}`)
    .width('100%')
    .renderGroup(true)
    .scale({ x: this.pressed && !AppEnv.inst.reduceMotion ? 0.97 : 1,
      y: this.pressed && !AppEnv.inst.reduceMotion ? 0.97 : 1 })
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
      Nav.openLive(this.item, this.coverRect);
    })
    .bindContextMenu(this.menu(), ResponseType.LongPress)
  }
}
