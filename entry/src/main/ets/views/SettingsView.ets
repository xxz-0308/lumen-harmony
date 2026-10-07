import { promptAction } from '@kit.ArkUI';
import { ThemeMode } from '../app/AppEnv';
import { AccentPalette, LeaveBehavior, PlayerEngineChoice, Settings, StartPage, VolumeMode } from '../app/Settings';
import { MediaVolume } from '../platform/MediaVolume';
import { AppEnv } from '../app/AppEnv';
import { HistoryStore } from '../app/Stores';
import { C, Layout, Radius, Space } from '../theme/Theme';
import { Segmented } from '../components/Basics';
import { DanmakuSettingsPanel } from '../room/RoomPanels';
import { BiliQrLogin } from '../core/sites/BiliQrLogin';
import { BiliSession } from '../app/BiliSession';
import { LivePip } from '../platform/LivePip';
import { Log } from '../util/Log';

function broadBlockWord(word: string): boolean {
  if (!word.startsWith('/') || !word.endsWith('/') || word.length < 3) {
    return false;
  }
  try {
    const rule = new RegExp(word.substring(1, word.length - 1));
    return ['文字', 'hello', '123', ' '].every((text: string) => rule.test(text));
  } catch (e) {
    return false;
  }
}

@ComponentV2
struct SettingsCard {
  @Param title: string = '';
  @BuilderParam content: () => void;

  build() {
    Column({ space: 12 }) {
      if (this.title.length > 0) {
        Text(this.title)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(C.text3)
          .padding({ left: 4 })
      }
      Column({ space: 18 }) {
        this.content()
      }
      .width('100%')
      .padding(20)
      .borderRadius(Radius.xl)
      .backgroundColor(C.bgElevated)
      .borderWidth(1)
      .borderColor(C.stroke)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

@ComponentV2
struct SettingItem {
  @Param title: string = '';
  @Param desc: string = '';
  @BuilderParam control: () => void;
  @Local rowW: number = AppEnv.inst.winWidth;

  build() {
    Flex({ direction: this.rowW < 520 ? FlexDirection.Column : FlexDirection.Row,
      alignItems: this.rowW < 520 ? ItemAlign.Start : ItemAlign.Center }) {
      Column({ space: 3 }) {
        Text(this.title)
          .fontSize(15)
          .fontColor(C.text1)
        if (this.desc.length > 0) {
          Text(this.desc)
            .fontSize(12)
            .fontColor(C.text3)
        }
      }
      .layoutWeight(this.rowW < 520 ? 0 : 1)
      .margin(this.rowW < 520 ? { bottom: 12 } : { right: 16 })
      .alignItems(HorizontalAlign.Start)
      this.control()
    }
    .width('100%')
    .onAreaChange((o: Area, n: Area) => { this.rowW = n.width as number; })
  }
}

@ComponentV2
export struct SettingsView {
  @Param topPadding: number = Space.md;
  /** Keep login subscriptions, polling and cancellation in one implementation. */
  @Param accountOnly: boolean = false;
  @Param active: boolean = false;
  @Local env: AppEnv = AppEnv.inst;
  @Local s: Settings = Settings.inst;
  @Local appearanceMode: ThemeMode = Settings.inst.themeMode;
  @Local appearancePalette: AccentPalette = Settings.inst.accentPalette;
  @Local displayedStartPage: StartPage = Settings.inst.startPage;
  @Local displayedFill: boolean = Settings.inst.videoFill;
  @Local displayedVolumeMode: VolumeMode = Settings.inst.volumeMode;
  @Local displayedLeave: LeaveBehavior = Settings.inst.leaveBehavior;
  @Local displayedEngine: PlayerEngineChoice = Settings.inst.playerEngine;
  @Local blockInput: string = '';
  @Local displayedWords: string[] = Settings.inst.blockWords.slice();
  @Local areaW: number = AppEnv.inst.winWidth;
  @Local storageMessage: string = Settings.inst.storageError;
  private syncStorage: () => void = () => {
    this.storageMessage = this.s.storageError;
  };
  private foregroundListener: () => void = () => {
    if (!this.env.foreground) {
      this.stopQr();
    }
  };
  @Local qrUrl: string = '';
  @Local qrState: string = '';
  @Local qrBusy: boolean = false;
  @Local accountUid: number = Settings.inst.biliUid;
  @Local accountName: string = Settings.inst.biliName;
  @Local accountExpired: boolean = Settings.inst.biliExpired;
  @Local accountError: string = Settings.inst.accountError;
  private syncAccount: () => void = () => {
    this.accountUid = this.s.biliUid;
    this.accountName = this.s.biliName;
    this.accountExpired = this.s.biliExpired;
    this.accountError = this.s.accountError;
  };
  private qrKey: string = '';
  private qrExpiresAt: number = 0;
  private qrSeq: number = 0;
  private qrTimer: number = -1;
  private qrLogin: BiliQrLogin = new BiliQrLogin();
  private pipSupported: boolean = LivePip.supported();
  private leaveKeys: LeaveBehavior[] = this.pipSupported ? ['pip', 'pause', 'audio'] : ['pause', 'audio'];

  get centerInset(): number {
    const available = this.areaW - Space.page * 2;
    return Math.max(0, (available - 820) / 2);
  }

  @Monitor('active')
  onActive(): void {
    if (!this.active) {
      this.stopQr();
    } else {
      this.appearanceMode = this.s.themeMode;
      this.appearancePalette = this.s.accentPalette;
      this.displayedStartPage = this.s.startPage;
      this.displayedFill = this.s.videoFill;
      this.displayedVolumeMode = this.s.volumeMode;
      this.displayedLeave = this.s.leaveBehavior;
      this.displayedEngine = this.s.playerEngine;
      this.displayedWords = this.s.blockWords.slice();
      this.storageMessage = this.s.storageError;
      this.syncAccount();
    }
  }

  aboutToAppear(): void {
    this.env.subscribeForeground(this.foregroundListener);
    this.s.subscribeStorage(this.syncStorage);
    this.s.subscribeAccount(this.syncAccount);
    this.syncStorage();
    this.syncAccount();
  }

  aboutToDisappear(): void {
    this.env.unsubscribeForeground(this.foregroundListener);
    this.s.unsubscribeStorage(this.syncStorage);
    this.s.unsubscribeAccount(this.syncAccount);
    this.stopQr();
  }

  private stopQr(): void {
    this.qrSeq++;
    if (this.qrTimer >= 0) {
      clearTimeout(this.qrTimer);
      this.qrTimer = -1;
    }
    this.qrKey = '';
    this.qrUrl = '';
    this.qrBusy = false;
    this.qrState = '';
  }

  private async startQr(): Promise<void> {
    if (!this.active || !this.env.foreground) return;
    this.stopQr();
    const seq = this.qrSeq;
    this.qrBusy = true;
    this.qrState = '正在获取二维码…';
    try {
      const ticket = await this.qrLogin.begin();
      if (seq !== this.qrSeq || !this.active || !this.env.foreground) {
        return;
      }
      this.qrKey = ticket.key;
      this.qrExpiresAt = ticket.expiresAt;
      this.qrUrl = ticket.url;
      this.qrState = '请使用哔哩哔哩 App 扫码并确认';
      this.qrTimer = setTimeout(() => this.pollQr(seq), 1500);
    } catch (e) {
      // QR generation has no secret key in its request URL; keep the failure visible in hilog
      // so a network/API rejection can be diagnosed without exposing poll tokens or cookies.
      Log.w('bili-auth', `QR generation failed: ${e}`);
      if (seq === this.qrSeq) {
        this.qrState = '二维码获取失败，请重试';
      }
    } finally {
      if (seq === this.qrSeq) {
        this.qrBusy = false;
      }
    }
  }

  private async pollQr(seq: number): Promise<void> {
    this.qrTimer = -1;
    if (seq !== this.qrSeq || !this.active || !this.env.foreground || !this.qrKey) {
      return;
    }
    if (Date.now() >= this.qrExpiresAt) {
      this.qrState = '二维码已过期，请刷新';
      this.qrKey = '';
      return;
    }
    let nextPollMs = 4000;
    try {
      const result = await this.qrLogin.poll(this.qrKey);
      if (seq !== this.qrSeq || !this.active || !this.env.foreground) {
        return;
      }
      if (result.state === 'success' && result.account) {
        this.qrBusy = true;
        this.qrState = '正在保存账号…';
        await BiliSession.signIn(result.account);
        this.accountUid = result.account.userId;
        this.accountName = result.account.name;
        if (seq === this.qrSeq) {
          this.stopQr();
          if (this.active && this.env.foreground) {
            promptAction.showToast({ message: '哔哩哔哩登录成功' });
          }
        }
        return;
      }
      if (result.state === 'expired') {
        this.qrState = '二维码已过期，请刷新';
        this.qrKey = '';
        return;
      }
      this.qrState = result.state === 'scanned' ? '已扫码，请在手机上确认' : '请使用哔哩哔哩 App 扫码并确认';
      nextPollMs = result.state === 'scanned' ? 2000 : 4000;
    } catch (e) {
      // Native network errors may contain the poll URL and its secret key; never log them.
      Log.w('bili-auth', 'QR poll/sign-in failed');
      if (seq === this.qrSeq) {
        const code = `${e}`.match(/扫码请求失败（(-?\d+)）/);
        this.qrState = code !== null ? `B站扫码请求失败（${code[1]}），请稍后重试` :
          '登录或保存失败，请刷新二维码重试';
        this.qrKey = '';
        this.qrBusy = false;
      }
      return;
    }
    if (seq === this.qrSeq && this.active && this.env.foreground && this.qrKey) {
      this.qrTimer = setTimeout(() => this.pollQr(seq), nextPollMs);
    }
  }

  private async signOut(): Promise<void> {
    try {
      await BiliSession.signOut();
      this.accountUid = 0;
      this.accountName = '';
      this.stopQr();
    } catch (e) {
      promptAction.showToast({ message: '退出失败，请重试' });
    }
  }

  @Builder
  toggle(on: boolean, change: (v: boolean) => void) {
    Toggle({ type: ToggleType.Switch, isOn: on })
      .selectedColor(C.accent)
      .onChange((v: boolean) => {
        change(v);
        this.s.scheduleSave();
        this.storageMessage = this.s.storageError;
      })
  }

  @Builder
  appearance() {
    SettingItem({ title: '外观', desc: '' }) {
      Segmented({
        items: ['跟随系统', '浅色', '深色'],
        selected: this.appearanceMode,
        segmentWidth: 72,
        onSelect: (i: number) => {
          this.appearanceMode = i as ThemeMode;
          this.s.themeMode = this.appearanceMode;
          this.env.setThemeMode(this.appearanceMode);
          this.s.flush().catch(() => Log.w('settings', 'Could not save theme mode'));
        }
      })
    }
    SettingItem({ title: '主题色', desc: '界面强调色，可随时切换' }) {
      Segmented({
        items: ['暖橙', '海蓝', '薄荷', '兰紫'],
        selected: ['ember', 'ocean', 'mint', 'orchid'].indexOf(this.appearancePalette),
        segmentWidth: 48,
        onSelect: (i: number) => {
          this.appearancePalette = ['ember', 'ocean', 'mint', 'orchid'][i] as AccentPalette;
          this.s.accentPalette = this.appearancePalette;
          this.s.flush().catch(() => Log.w('settings', 'Could not save accent color'));
        }
      })
    }
    SettingItem({ title: '启动页', desc: '打开 App 时进入的页面' }) {
      Segmented({
        items: ['首页', '分类', '关注', '我的'],
        selected: ['home', 'category', 'follow', 'mine'].indexOf(
          this.displayedStartPage === 'history' ? 'mine' : this.displayedStartPage),
        segmentWidth: 48,
        onSelect: (i: number) => {
          this.displayedStartPage = ['home', 'category', 'follow', 'mine'][i] as StartPage;
          this.s.startPage = this.displayedStartPage;
          this.s.scheduleSave();
        }
      })
    }
    SettingItem({ title: '首页大图自动轮播', desc: '关闭时只在手动滑动时切换' }) {
      this.toggle(this.s.heroAutoPlay, (v: boolean) => {
        this.s.heroAutoPlay = v;
      })
    }
  }

  @Builder
  playback() {
    SettingItem({ title: '进入直播间自动全屏', desc: '' }) {
      this.toggle(this.s.autoFullscreen, (v: boolean) => {
        this.s.autoFullscreen = v;
      })
    }
    SettingItem({ title: '画质不超过 1080P', desc: '默认选择最高画质；开启后可降低流量和发热' }) {
      this.toggle(this.s.capAt1080, (v: boolean) => {
        this.s.capAt1080 = v;
      })
    }
    SettingItem({
      title: '播放内核',
      desc: this.displayedEngine === 'ijk' ? 'ijkplayer：多缓冲几秒换取不卡顿，下次进入直播间生效' :
        '系统播放器：延迟更低，网络波动时更容易卡顿，下次进入直播间生效'
    }) {
      Segmented({
        items: ['ijkplayer', '系统播放器'],
        selected: this.displayedEngine === 'ijk' ? 0 : 1,
        segmentWidth: 84,
        onSelect: (i: number) => {
          this.displayedEngine = i === 0 ? 'ijk' : 'avplayer';
          this.s.playerEngine = this.displayedEngine;
          this.s.scheduleSave();
        }
      })
    }
    SettingItem({ title: '自动切换线路', desc: '卡顿或出错时自动尝试下一条线路' }) {
      this.toggle(this.s.autoSwitchLine, (v: boolean) => {
        this.s.autoSwitchLine = v;
      })
    }
    SettingItem({
      title: '手势调节音量',
      desc: this.displayedVolumeMode === 'media' ? '调整平板媒体音量，与实体音量键同步' :
        '仅调整 Lumen 播放音量，退出直播间后保持'
    }) {
      Segmented({
        items: ['媒体音量', '应用音量'],
        selected: this.displayedVolumeMode === 'media' ? 0 : 1,
        segmentWidth: 72,
        onSelect: (i: number) => {
          if (i === 0 && MediaVolume.read() === null) {
            promptAction.showToast({ message: '此设备暂不可读取媒体音量' });
            return;
          }
          this.displayedVolumeMode = i === 0 ? 'media' : 'app';
          this.s.volumeMode = this.displayedVolumeMode;
          this.s.scheduleSave();
        }
      })
    }
    SettingItem({ title: '全屏画面', desc: '剧场和全屏下都可双指捏合切换' }) {
      Segmented({
        items: ['完整画面', '填充屏幕'],
        selected: this.displayedFill ? 1 : 0,
        segmentWidth: 72,
        onSelect: (i: number) => {
          this.displayedFill = i === 1;
          this.s.videoFill = this.displayedFill;
          this.s.scheduleSave();
        }
      })
    }
    SettingItem({
      title: '离开 App 时',
      desc: this.displayedLeave === 'pip' ? '画中画：回到桌面时缩成小窗继续播放' :
        (this.displayedLeave === 'pause' ? '暂停：回到桌面时暂停播放，回来继续' : '后台播放：回到桌面后只保留声音')
    }) {
      Segmented({
        items: this.leaveKeys.map((k: LeaveBehavior) => k === 'pip' ? '画中画' : k === 'pause' ? '暂停' : '后台播放'),
        selected: Math.max(0, this.leaveKeys.indexOf(this.displayedLeave)),
        segmentWidth: 72,
        onSelect: (i: number) => {
          this.displayedLeave = this.leaveKeys[i];
          this.s.leaveBehavior = this.displayedLeave;
          this.s.scheduleSave();
        }
      })
    }
  }

  @Builder
  blockWords() {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        TextInput({ text: this.blockInput, placeholder: '添加屏蔽词，/正则/ 形式支持正则表达式' })
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .backgroundColor(C.surface2)
          .borderRadius(Radius.pill)
          .onChange((v: string) => {
            this.blockInput = v;
          })
          .onSubmit(() => this.addBlock())
        Text('添加')
          .fontSize(14)
          .fontColor(Color.White)
          .height(40)
          .padding({ left: 18, right: 18 })
          .borderRadius(Radius.pill)
          .backgroundColor(C.accent)
          .onClick(() => this.addBlock())
      }
      if (this.displayedWords.some((w: string) => broadBlockWord(w))) {
        Text('有屏蔽规则会拦截几乎所有弹幕，连接正常时聊天也可能为空')
          .fontSize(12)
          .fontColor(C.accent)
      }
      if (this.displayedWords.length > 0) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.displayedWords, (w: string) => {
            Row({ space: 6 }) {
              Text(w)
                .fontSize(13)
                .fontColor(C.text1)
              SymbolGlyph($r('sys.symbol.xmark'))
                .fontSize(12)
                .fontColor([C.text3])
            }
            .height(32)
            .padding({ left: 12, right: 10 })
            .margin({ right: 8, bottom: 8 })
            .borderRadius(Radius.pill)
            .backgroundColor(C.surface2)
            .onClick(() => {
              this.displayedWords = this.displayedWords.filter((x: string) => x !== w);
              this.s.blockWords = this.displayedWords.slice();
              this.s.scheduleSave();
            })
          }, (w: string) => w)
        }
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  private addBlock(): void {
    const w = this.blockInput.trim();
    if (w.length === 0 || this.displayedWords.indexOf(w) >= 0) {
      return;
    }
    this.displayedWords = this.displayedWords.concat([w]);
    this.s.blockWords = this.displayedWords.slice();
    this.s.scheduleSave();
    this.blockInput = '';
    if (broadBlockWord(w)) {
      promptAction.showToast({ message: '此规则会屏蔽几乎所有弹幕' });
    }
  }

  @Builder
  account() {
    if (this.accountUid > 0) {
      SettingItem({ title: '哔哩哔哩', desc: `已登录：${this.accountName || '用户 ' + this.accountUid}` }) {
        Button('退出登录', { type: ButtonType.Normal })
          .height(Layout.touchTarget)
          .backgroundColor(C.accentSoft)
          .borderRadius(Radius.pill)
          .fontSize(14)
          .fontColor(C.accent)
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .onClick(() => {
            promptAction.showDialog({
              title: '退出哔哩哔哩账号？',
              message: '此设备将不再使用当前账号播放直播',
              buttons: [{ text: '取消', color: '#99999999' }, { text: '退出', color: C.accentHighlight }]
            }).then((r: promptAction.ShowDialogSuccessResponse) => {
              if (r.index === 1) {
                this.signOut();
              }
            }).catch(() => {});
          })
      }
    } else {
      SettingItem({
        title: '哔哩哔哩',
        desc: this.accountError || (this.accountExpired ? '登录已过期，请重新扫码登录' :
          '扫码登录可申请更高画质；实际画质由平台返回结果决定')
      }) {
        Button(this.qrUrl ? '刷新二维码' : '扫码登录', { type: ButtonType.Normal })
          .height(Layout.touchTarget)
          .enabled(!this.qrBusy)
          .backgroundColor(C.accentSoft)
          .borderRadius(Radius.pill)
          .fontSize(14)
          .fontColor(C.accent)
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .onClick(() => {
            if (!this.qrBusy) {
              this.startQr();
            }
          })
      }
      if (this.qrUrl.length > 0) {
        Column({ space: 12 }) {
          QRCode(this.qrUrl)
            .width(180)
            .height(180)
            .color(Color.Black)
            .backgroundColor(Color.White)
          Text(this.qrState)
            .fontSize(13)
            .fontColor(Color.Black)
        }
        .width('100%')
        .padding(16)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(Color.White)
        .borderRadius(Radius.lg)
      } else if (this.qrState.length > 0) {
        Text(this.qrState)
          .fontSize(13)
          .fontColor(C.text2)
      }
    }
  }

  @Builder
  data() {
    SettingItem({ title: '清空观看历史', desc: `${HistoryStore.inst.items.length} 条记录` }) {
      Text('清空')
        .fontSize(14)
        .fontColor(C.accent)
        .height(40)
        .padding({ left: 12, right: 12 })
        .onClick(() => {
          promptAction.showDialog({
            title: '清空观看历史？',
            message: '此操作无法撤销',
            buttons: [{ text: '取消', color: '#99999999' }, { text: '清空', color: C.accentHighlight }]
          }).then((r: promptAction.ShowDialogSuccessResponse) => {
            if (r.index === 1) {
              HistoryStore.inst.clear();
              promptAction.showToast({ message: HistoryStore.inst.storageError || '已清空观看历史' });
            }
          }).catch(() => {
          });
        })
    }
    SettingItem({ title: '清空搜索记录', desc: '' }) {
      Text('清空')
        .fontSize(14)
        .fontColor(C.accent)
        .height(40)
        .padding({ left: 12, right: 12 })
        .onClick(() => {
          this.s.searchHistory = [];
          this.s.scheduleSave();
          promptAction.showToast({ message: '已清空搜索记录' });
        })
    }
  }

  build() {
    Scroll() {
      Column({ space: Space.xl }) {
        if (this.storageMessage.length > 0) {
          Row({ space: 12 }) {
            Text(this.storageMessage)
              .fontSize(13)
              .fontColor(C.live)
            Text('重试')
              .fontSize(14)
              .fontColor(C.accent)
              .height(40)
              .padding({ left: 12, right: 12 })
              .onClick(() => {
                this.s.retryStorage();
                this.storageMessage = this.s.storageError;
                this.onActive();
              })
          }
        }
        if (!this.accountOnly) {
          SettingsCard({ title: '通用' }) {
            this.appearance()
          }
          SettingsCard({ title: '播放' }) {
            this.playback()
          }
          SettingsCard({ title: '弹幕' }) {
            DanmakuSettingsPanel({ onMedia: false, embedded: true })
          }
          SettingsCard({ title: '弹幕屏蔽词' }) {
            this.blockWords()
          }
        }
        SettingsCard({ title: this.accountOnly ? '' : '账号' }) {
          this.account()
        }
        if (!this.accountOnly) {
          SettingsCard({ title: '数据' }) {
            this.data()
          }
        }
        Column({ space: 6 }) {
          Row({ space: 8 }) {
            Row()
              .width(10)
              .height(10)
              .borderRadius(5)
              .linearGradient({ angle: 135, colors: [['#FFE1B8', 0], [C.accentHighlight, 1]] })
            Text('Lumen 1.0')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(C.text2)
          }
          Text('参考 dart_simple_live 实现，仅供个人学习交流')
            .fontSize(12)
            .fontColor(C.text3)
        }
        .width('100%')
        .margin({ top: 8 })
      }
      .width('100%')
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
    .align(Alignment.TopStart)
    .onAreaChange((o: Area, n: Area) => {
      this.areaW = n.width as number;
    })
  }
}
