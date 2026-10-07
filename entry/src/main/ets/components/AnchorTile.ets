import { promptAction } from '@kit.ArkUI';
import { SymbolGlyphModifier } from '@kit.ArkUI';
import { SiteId } from '../core/model/Models';
import { FollowStore } from '../app/Stores';
import { Nav } from '../app/Nav';
import { AppEnv } from '../app/AppEnv';
import { C, Motion, Radius, SiteStyle } from '../theme/Theme';
import { Avatar } from './Basics';

/** Compact anchor tile: avatar with live ring, name, platform and a follow toggle. */
@ComponentV2
export struct AnchorTile {
  @Param siteId: SiteId = 'huya';
  @Param roomId: string = '';
  @Param userName: string = '';
  @Param avatar: string = '';
  @Param live: boolean = false;
  @Param subtitle: string = '';
  @Param showFollow: boolean = true;
  @Local pressed: boolean = false;

  get followed(): boolean {
    return FollowStore.inst.isFollowed(this.siteId, this.roomId);
  }

  @Builder
  menu() {
    Menu() {
      if (this.followed) {
        MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.heart_slash')), content: '取消关注' })
          .onClick(() => {
            FollowStore.inst.unfollow(this.siteId, this.roomId);
          })
      }
    }
  }

  build() {
    Row({ space: 12 }) {
      Avatar({ src: this.avatar, dim: 48, live: this.live })
      Column({ space: 4 }) {
        Text(this.userName)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(C.text1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: 6 }) {
          Row()
            .width(6)
            .height(6)
            .borderRadius(3)
            .backgroundColor(SiteStyle.color(this.siteId))
          Text(this.subtitle.length > 0 ? this.subtitle : SiteStyle.label(this.siteId))
            .fontSize(12)
            .fontColor(this.live ? C.live : C.text3)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      if (this.showFollow) {
        Button({ type: ButtonType.Circle }) {
          // Separate branches: a SymbolGlyph does not redraw when only its resource changes.
          if (this.followed) {
            SymbolGlyph($r('sys.symbol.heart_fill'))
              .fontSize(18)
              .fontColor([C.accent])
              .transition(TransitionEffect.scale({ x: 0.6, y: 0.6 }).combine(TransitionEffect.OPACITY)
                .animation({ duration: 200, curve: Curve.EaseOut }))
          } else {
            SymbolGlyph($r('sys.symbol.heart'))
              .fontSize(18)
              .fontColor([C.text2])
          }
        }
        .width(44)
        .height(44)
        .borderRadius(Radius.pill)
        .accessibilityText(this.followed ? `取消关注 ${this.userName}` : `关注 ${this.userName}`)
        .backgroundColor(this.followed ? C.accentSoft : C.surface2)
        .onClick(() => {
          if (FollowStore.inst.storageError.length > 0) {
            promptAction.showToast({ message: FollowStore.inst.storageError });
            return;
          }
          if (this.followed) {
            FollowStore.inst.unfollow(this.siteId, this.roomId);
          } else {
            FollowStore.inst.followAnchor(this.siteId, this.roomId, this.userName, this.avatar, this.live);
            promptAction.showToast({ message: `已关注 ${this.userName}` });
          }
        })
      }
    }
    .width('100%')
    .padding(12)
    .borderRadius(Radius.lg)
    .backgroundColor(C.bgElevated)
    .borderWidth(1)
    .borderColor(C.stroke)
    .scale({ x: this.pressed && !AppEnv.inst.reduceMotion ? 0.98 : 1,
      y: this.pressed && !AppEnv.inst.reduceMotion ? 0.98 : 1 })
    .animation({ curve: Motion.snappy })
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Down) {
        this.pressed = true;
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.pressed = false;
      }
    })
    .onClick(() => Nav.openRoom(this.siteId, this.roomId))
    .bindContextMenu(this.menu(), ResponseType.LongPress)
  }
}
