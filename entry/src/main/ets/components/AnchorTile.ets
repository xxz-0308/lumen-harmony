import { promptAction, SymbolGlyphModifier } from '@kit.ArkUI';
import { SiteId } from '../core/model/Models';
import { FollowStore } from '../app/Stores';
import { Nav } from '../app/Nav';
import { AppEnv } from '../app/AppEnv';
import { C, Motion, Radius, SiteStyle } from '../theme/Theme';
import { Avatar } from './Basics';

/** Lumen 2.0 Sleek Anchor Capsule: compact high-density glass capsule for followed anchors. */
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
  @Local followed: boolean = false;
  private syncFollow: () => void = () => {
    this.followed = FollowStore.inst.isFollowed(this.siteId, this.roomId);
  };

  @Monitor('siteId', 'roomId')
  onKeyChange(): void {
    this.syncFollow();
  }

  aboutToAppear(): void {
    FollowStore.inst.subscribe(this.syncFollow);
    this.syncFollow();
  }

  aboutToDisappear(): void {
    FollowStore.inst.unsubscribe(this.syncFollow);
  }

  @Builder
  menu() {
    Menu() {
      if (this.followed) {
        MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.heart_slash')), content: '取消关注' })
          .onClick(() => {
            FollowStore.inst.unfollow(this.siteId, this.roomId);
            this.syncFollow();
          })
      }
    }
  }

  build() {
    Row({ space: 10 }) {
      Avatar({ src: this.avatar, dim: 38, live: this.live })
      Column({ space: 3 }) {
        Text(this.userName)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(C.text1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: 5 }) {
          Row()
            .width(6)
            .height(6)
            .borderRadius(3)
            .backgroundColor(SiteStyle.color(this.siteId))
          Text(this.subtitle.length > 0 ? this.subtitle : SiteStyle.label(this.siteId))
            .fontSize(11)
            .fontColor(this.live ? C.live : C.text2)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.showFollow) {
        Button({ type: ButtonType.Circle }) {
          Stack() {
            ForEach([this.followed], (on: boolean) => {
              SymbolGlyph(on ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
                .fontSize(15)
                .fontColor([on ? C.live : C.text2])
                .transition(TransitionEffect.scale({ x: 0.6, y: 0.6 }).combine(TransitionEffect.OPACITY)
                  .animation({ duration: 200, curve: Curve.EaseOut }))
            }, (on: boolean) => `${on}`)
          }
        }
        .width(34)
        .height(34)
        .borderRadius(Radius.pill)
        .accessibilityText(this.followed ? `取消关注 ${this.userName}` : `关注 ${this.userName}`)
        .backgroundColor(this.followed ? '#1FFF3B30' : C.surface2)
        .onClick(() => {
          if (FollowStore.inst.storageError.length > 0) {
            promptAction.showToast({ message: FollowStore.inst.storageError });
            return;
          }
          if (this.followed) {
            this.followed = false;
            FollowStore.inst.unfollow(this.siteId, this.roomId);
          } else {
            this.followed = true;
            FollowStore.inst.followAnchor(this.siteId, this.roomId, this.userName, this.avatar, this.live);
            promptAction.showToast({ message: `已关注 ${this.userName}` });
          }
        })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .borderRadius(Radius.lg)
    .backgroundColor(C.surface)
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
