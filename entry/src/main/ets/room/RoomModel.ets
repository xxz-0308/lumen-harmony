import {
  LiveMessage,
  LiveMessageType,
  LiveRoomDetail,
  LiveRoomItem,
  PlayQuality,
  PlayUrls,
  SiteId,
  SuperChatMessage
} from '../core/model/Models';
import { LiveSite } from '../core/sites/LiveSite';
import { Sites } from '../core/sites/Sites';
import { LiveDanmaku } from '../core/danmaku/LiveDanmaku';
import { BiliDanmakuArgs } from '../core/danmaku/BiliDanmaku';
import { PlayState } from '../player/LivePlayer';
import { LivePlayerApi } from '../player/PlayerApi';
import { createLivePlayer } from '../player/PlayerFactory';
import { DouyuStreamRelay } from '../player/DouyuStreamRelay';
import { FollowStore, HistoryStore } from '../app/Stores';
import { Settings } from '../app/Settings';
import { Log } from '../util/Log';

export class ChatLine {
  id: number = 0;
  user: string = '';
  text: string = '';
  color: number = 0xffffff;
}

export class ScCard {
  id: number = 0;
  sc: SuperChatMessage = new SuperChatMessage();
}

const MAX_CHAT = 300;
const EXPIRY_RETRY_DELAY_MS = 200;
const EXPIRY_RETRY_BUDGET_MS = 8600; // 200ms delay + <=8000ms relay attempt, leaving recovery headroom.

/** Everything a live room page needs: detail, playback selection, danmaku and chat. */
@ObservedV2
export class RoomModel {
  @Trace siteId: SiteId = 'huya';
  @Trace roomId: string = '';
  @Trace preview: LiveRoomItem | null = null;
  @Trace detail: LiveRoomDetail | null = null;
  @Trace loading: boolean = true;
  @Trace error: string = '';
  @Trace qualities: PlayQuality[] = [];
  @Trace qualityIndex: number = 0;
  @Trace lines: string[] = [];
  @Trace lineQualityIds: number[] = [];
  @Trace chats: ChatLine[] = [];
  @Trace online: number = 0;
  @Trace superChats: ScCard[] = [];
  /** Latest SC pushed while watching, for the fullscreen toast. */
  @Trace latestSc: ScCard | null = null;
  @Trace danmakuStatus: string = '';
  @Trace danmakuConnected: boolean = false;
  @Trace blockedChats: number = 0;
  /** Bumped when switching rooms so the video layer can cross-fade. */
  @Trace switchSeq: number = 0;

  @Trace readonly player: LivePlayerApi = createLivePlayer();
  /** Receives every chat message for on-video rendering; set by the danmaku canvas. */
  onBullet: ((text: string, color: number) => void) | null = null;

  private danmaku: LiveDanmaku | null = null;
  private seq: number = 0;
  private chatId: number = 0;
  private headers: Record<string, string> = {};
  private pendingChats: ChatLine[] = [];
  private flushTimer: number = -1;
  private blockedPending: number = 0;
  private blockedTimer: number = -1;
  private expiryTimer: number = -1;
  private recoverTimes: number[] = [];
  private recovering: boolean = false;
  /** The signed URLs expired while paused; resume must re-resolve instead of reopening them. */
  private expiryDue: boolean = false;
  private disposed: boolean = false;
  private playSeq: number = 0;
  private relay: DouyuStreamRelay | null = null;

  constructor() {
    // A transient failure (quality change, refresh) must not leave an error overlay
    // over a stream that is actually playing.
    this.player.onPlaying = () => {
      if (this.error.length > 0 && this.error !== '主播暂未开播') {
        this.error = '';
      }
    };
    this.player.onStreamEnded = () => {
      if (!this.recover('直播流中断')) {
        this.player.giveUp('直播流中断');
      }
    };
    this.player.onLinesExhausted = (reason: string): boolean => this.recover(reason);
    this.player.onSuspended = () => {
      this.expiryDue = true;
    };
  }

  /**
   * Signed stream URLs expire (Douyu cuts the connection at `expire` seconds) and CDNs occasionally
   * drop us. Re-resolve fresh URLs and resume in place, at most 4 times per 2 minutes.
   */
  private recover(reason: string): boolean {
    const now = Date.now();
    this.recoverTimes = this.recoverTimes.filter((t: number) => now - t < 120000);
    if (this.recovering) {
      return true;
    }
    if (this.recoverTimes.length >= 4 || this.detail === null || this.qualities.length === 0) {
      return false;
    }
    // A second drop shortly after the last recovery points at a bad CDN edge rather than an
    // expired signature: move to the next returned line instead of retrying the same edge.
    const last = this.recoverTimes.length > 0 ? this.recoverTimes[this.recoverTimes.length - 1] : 0;
    const advance = now - last < 30000 && this.player.autoSwitch;
    this.recoverTimes.push(now);
    this.recovering = true;
    Log.i('room', `recover after: ${reason}${advance ? ' (next line)' : ''}`);
    const seq = this.seq;
    this.playQuality(this.qualityIndex, seq, true, advance).catch((e: Error) => {
      if (seq === this.seq) {
        this.player.giveUp(reason);
      }
    }).finally(() => {
      if (seq === this.seq) {
        this.recovering = false;
      }
    });
    return true;
  }

  /** Refreshes the URL 30s before a signed `expire=` window closes, so one 8s handoff attempt plus
   * one re-signed retry both fit inside the remaining token life so playback never hits the cutoff. */
  private scheduleExpiryRefresh(urls: string[], seq: number, requestedAt: number = Date.now()): void {
    if (this.expiryTimer >= 0) {
      clearTimeout(this.expiryTimer);
      this.expiryTimer = -1;
    }
    this.expiryDue = false;
    // Failover may move to any returned line, so refresh before the earliest one expires.
    let ttl = Number.MAX_VALUE;
    const now = Date.now();
    for (const url of urls) {
      const m = url.match(/[?&]expire=(\d+)/);
      if (m !== null) {
        const secs = Number(m[1]);
        // Relative TTL is conservatively anchored BEFORE URL lookup, not after player startup
        // or handoff/retry. Those waits must not extend the old or newly signed source lifetime.
        ttl = Math.min(ttl, secs > 1e9 ? secs - now / 1000 : secs - Math.max(0, now - requestedAt) / 1000);
      }
    }
    if (ttl <= 30 || ttl > 6 * 3600) {
      return;
    }
    const expiresAt = now + ttl * 1000;
    const scheduledRequest = this.playSeq;
    this.expiryTimer = setTimeout(() => {
      this.expiryTimer = -1;
      if (this.disposed || seq !== this.seq || scheduledRequest !== this.playSeq || this.detail === null) {
        return;
      }
      if (!this.player.wantsPlayback || this.player.state === PlayState.Error) {
        // Never restart a stream the user paused; resume() re-resolves instead.
        this.expiryDue = true;
        return;
      }
      if (this.recovering) {
        // Recovery is already fetching fresh URLs and will reschedule this timer.
        return;
      }
      Log.i('room', 'renewing signed stream before expiry');
      const request = this.playSeq;
      const quality = this.qualityIndex;
      const detail = this.detail;
      const relay = this.relay;
      if (this.siteId !== 'douyu' || relay === null || detail === null) {
        this.playQuality(quality, seq, true).catch(() => {
          if (seq === this.seq) {
            this.expiryDue = true;
          }
        });
        return;
      }
      // A retained old stream is not a successful handoff. Retry the SAME fresh signed URL
      // once, without another network lookup, using the existing cancellable expiry timer.
      const freshRequestedAt = Date.now();
      this.site.getPlayUrls(detail, this.qualities[quality]).then(async (fresh) => {
        const attempt = async (retried: boolean, source: PlayUrls, signedAt: number): Promise<void> => {
          if (this.disposed || seq !== this.seq || request !== this.playSeq || this.relay !== relay || this.recovering) {
            return;
          }
          if (!this.player.wantsPlayback || this.player.state === PlayState.Error) {
            this.expiryDue = true;
            return;
          }
          const remaining = expiresAt - Date.now();
          // An attempt must fit inside the remaining token life, or the old connection dies mid-handoff.
          const canAttempt = remaining >= (retried ? EXPIRY_RETRY_BUDGET_MS - EXPIRY_RETRY_DELAY_MS : EXPIRY_RETRY_BUDGET_MS) &&
            (!retried || relay.canKeepCurrentStream);
          const handedOff = canAttempt && await relay.renew(source.urls, source.headers);
          if (this.disposed || seq !== this.seq || request !== this.playSeq || this.relay !== relay) {
            return;
          }
          if (!this.player.wantsPlayback) {
            this.expiryDue = true;
            return;
          }
          if (handedOff) {
            this.scheduleExpiryRefresh(source.urls, seq, signedAt);
            return;
          }
          const budget = expiresAt - Date.now();
          if (!retried && relay.canKeepCurrentStream && budget >= EXPIRY_RETRY_BUDGET_MS) {
            this.expiryDue = true;
            Log.w('room', `relay handoff retained old stream; retry=1 delayMs=${EXPIRY_RETRY_DELAY_MS} remainingMs=${Math.floor(budget)}; no seamless claim`);
            this.expiryTimer = setTimeout(() => {
              this.expiryTimer = -1;
              // A signed address admits exactly one upstream connection, so the failed attempt
              // has already burnt the first signature. The retry must sign again instead of
              // replaying an address the CDN will answer with a cached burst and then drop.
              const retrySignedAt = Date.now();
              this.site.getPlayUrls(detail, this.qualities[quality]).then((resigned) => {
                if (this.disposed || seq !== this.seq || request !== this.playSeq || this.relay !== relay || this.recovering) {
                  return;
                }
                return attempt(true, resigned, retrySignedAt);
              }).catch(() => {
                if (!this.disposed && seq === this.seq && request === this.playSeq) {
                  this.expiryDue = true;
                  if (this.player.wantsPlayback) {
                    this.recover('直播源续期失败');
                  }
                }
              });
            }, EXPIRY_RETRY_DELAY_MS);
            return;
          }
          this.expiryDue = true;
          Log.w('room', `relay handoff unavailable retry=${retried ? 1 : 0} remainingMs=${Math.floor(budget)}; restoring player before expiry, no seamless claim`);
          await this.playQuality(quality, seq, true);
        };
        await attempt(false, fresh, freshRequestedAt);
      }).catch(() => {
        if (!this.disposed && seq === this.seq && request === this.playSeq) {
          Log.w('room', 'signed stream renewal failed; requesting bounded recovery');
          this.expiryDue = true;
          if (this.player.wantsPlayback) {
            this.recover('直播源续期失败');
          }
        }
      });
    }, (ttl - 30) * 1000);
  }

  /** Resumes after a pause, re-resolving URLs if their signature ran out in the meantime. */
  resume(): void {
    if (this.disposed) {
      return;
    }
    // Relayed Douyu signatures are single-use: reconnecting the paused relay path reaches a
    // CDN that drops the second connection, so resuming always signs a fresh URL.
    const singleUse = this.relay !== null;
    if ((this.expiryDue || singleUse) && this.detail !== null && this.qualities.length > 0) {
      this.expiryDue = false;
      const seq = this.seq;
      this.playQuality(this.qualityIndex, seq).catch((e: Error) => {
        if (seq === this.seq) {
          this.player.giveUp(`${e.message}`);
        }
      });
      return;
    }
    this.player.resume();
  }

  get site(): LiveSite {
    return Sites.of(this.siteId);
  }

  @Computed
  get qualityLabel(): string {
    const requested = this.qualities[this.qualityIndex];
    if (!requested) {
      return '清晰度';
    }
    if (this.siteId !== 'bilibili') {
      return requested.name;
    }
    const actual = this.lineQualityIds[this.player.lineIndex] ?? 0;
    if (actual <= 0) {
      return `${requested.name} · 实际画质未核实`;
    }
    const found = this.qualities.find((q: PlayQuality) => q.sort === actual);
    const name = found ? found.name : `${actual}`;
    return actual === requested.sort ? name : `${requested.name} · 实际${name}`;
  }

  get title(): string {
    return this.detail?.title ?? this.preview?.title ?? '';
  }

  get userName(): string {
    return this.detail?.userName ?? this.preview?.userName ?? '';
  }

  get avatar(): string {
    return this.detail?.userAvatar ?? this.preview?.avatar ?? '';
  }

  get cover(): string {
    // Reuse the card's already-loaded image during the first room transition. Detail endpoints
    // often return a different URL for the same cover, which forces a cold image load and flash.
    const preview = this.preview?.cover ?? '';
    return preview.length > 0 ? preview : (this.detail?.cover ?? '');
  }

  get area(): string {
    return this.detail?.area ?? this.preview?.area ?? '';
  }

  get isFollowed(): boolean {
    return FollowStore.inst.isFollowed(this.siteId, this.detail?.roomId ?? this.roomId);
  }

  async open(siteId: SiteId, roomId: string, preview: LiveRoomItem | null): Promise<void> {
    const seq = ++this.seq;
    this.playSeq++;
    this.relay?.dispose();
    this.relay = null;
    if (this.expiryTimer >= 0) {
      clearTimeout(this.expiryTimer);
      this.expiryTimer = -1;
    }
    this.recoverTimes = [];
    this.recovering = false;
    this.stopDanmaku();
    this.player.stop();
    this.siteId = siteId;
    this.roomId = roomId;
    this.preview = preview;
    this.detail = null;
    this.loading = true;
    this.error = '';
    this.qualities = [];
    this.lines = [];
    this.lineQualityIds = [];
    this.chats = [];
    this.blockedChats = 0;
    this.danmakuConnected = false;
    this.danmakuStatus = '';
    this.superChats = [];
    this.latestSc = null;
    this.online = preview?.online ?? 0;
    this.player.autoSwitch = Settings.inst.autoSwitchLine;
    try {
      const d = await this.site.getRoomDetail(roomId);
      if (seq !== this.seq) {
        return;
      }
      this.detail = d;
      this.online = d.online > 0 ? d.online : this.online;
      HistoryStore.inst.record(d);
      FollowStore.inst.updateFromDetail(d);
      this.startDanmaku(d);
      this.loadSuperChats(d, seq);
      if (!d.status && !d.isRecord) {
        this.loading = false;
        this.error = '主播暂未开播';
        return;
      }
      const qs = await this.site.getPlayQualities(d);
      if (seq !== this.seq) {
        return;
      }
      this.qualities = qs;
      if (qs.length === 0) {
        throw new Error('没有可用的清晰度');
      }
      await this.playQuality(this.pickDefaultQuality(qs), seq);
    } catch (e) {
      if (seq === this.seq) {
        Log.w('room', 'open failed');
        this.error = `${e}`.replace('Error: ', '') || '加载失败';
      }
    } finally {
      if (seq === this.seq) {
        this.loading = false;
      }
    }
  }

  private pickDefaultQuality(qs: PlayQuality[]): number {
    let best = 0;
    for (let i = 1; i < qs.length; i++) {
      if (qs[i].sort > qs[best].sort) {
        best = i;
      }
    }
    if (!Settings.inst.capAt1080) {
      return best;
    }
    // skip qualities that clearly exceed 1080p
    const tooHigh = /4K|2K|1440|20M|杜比|HDR/i;
    let pick = -1;
    for (let i = 0; i < qs.length; i++) {
      if (!tooHigh.test(qs[i].name) && (pick < 0 || qs[i].sort > qs[pick].sort)) {
        pick = i;
      }
    }
    return pick >= 0 ? pick : best;
  }

  private async playQuality(index: number, seq: number, seamless: boolean = false,
    nextLine: boolean = false): Promise<void> {
    const d = this.detail;
    if (d === null || this.disposed) {
      return;
    }
    const request = ++this.playSeq;
    const sameQuality = index === this.qualityIndex && this.lines.length > 0;
    const line = sameQuality ? this.player.lineIndex : 0;
    Log.i('room', `request quality ${index} (${this.qualities[index].name})`);
    const urlsRequestedAt = Date.now();
    const urls = await this.site.getPlayUrls(d, this.qualities[index]);
    if (seq !== this.seq || request !== this.playSeq) {
      return;
    }
    const upstreamUrls = urls.urls;
    if (d.siteId === 'douyu' && upstreamUrls.length > 0) {
      if (this.relay === null) {
        this.relay = new DouyuStreamRelay();
      }
      urls.urls = await this.relay.register(upstreamUrls, urls.headers);
      if (seq !== this.seq || request !== this.playSeq) {
        return;
      }
    }
    if (urls.urls.length === 0) {
      throw new Error('没有可用的播放线路');
    }
    // A failed relay registration must not advertise a quality that never started.
    this.qualityIndex = index;
    this.lines = urls.urls;
    this.lineQualityIds = urls.qualityIds;
    this.headers = urls.headers;
    const start = nextLine && urls.urls.length > 1 ? (line + 1) % urls.urls.length :
      Math.min(line, urls.urls.length - 1);
    // Seamless refreshes (expiry, recovery) must not un-pause a stream the user paused meanwhile.
    await this.player.open(urls.urls, urls.headers, start, seamless, !seamless || this.player.wantsPlayback);
    if (seq === this.seq && request === this.playSeq) {
      this.scheduleExpiryRefresh(upstreamUrls, seq, urlsRequestedAt);
    }
  }

  async selectQuality(index: number): Promise<void> {
    if (index === this.qualityIndex && this.lines.length > 0) {
      return;
    }
    const seq = this.seq;
    this.error = '';
    try {
      await this.playQuality(index, seq);
    } catch (e) {
      if (seq === this.seq) {
        const message = `${e}`.replace('Error: ', '');
        if (this.player.state === PlayState.Playing || this.player.state === PlayState.Buffering) {
          this.player.notice = `${message}，继续当前播放`;
          this.player.noticeSeq++;
        } else {
          this.error = message;
        }
      }
    }
  }

  selectLine(index: number): void {
    this.player.selectLine(index);
  }

  /** Re-resolves URLs (they expire) and restarts playback on the current quality. */
  async refresh(): Promise<void> {
    if (this.detail === null || this.qualities.length === 0) {
      await this.open(this.siteId, this.roomId, this.preview);
      return;
    }
    const seq = this.seq;
    this.error = '';
    try {
      await this.playQuality(this.qualityIndex, seq);
    } catch (e) {
      if (seq === this.seq) {
        const message = `${e}`.replace('Error: ', '');
        if (this.player.state === PlayState.Playing || this.player.state === PlayState.Buffering) {
          this.player.notice = `${message}，继续当前播放`;
          this.player.noticeSeq++;
        } else {
          this.error = message;
        }
      }
    }
  }

  async switchTo(siteId: SiteId, roomId: string, preview: LiveRoomItem | null): Promise<void> {
    if (siteId === this.siteId && roomId === this.roomId) {
      return;
    }
    this.switchSeq++;
    await this.open(siteId, roomId, preview);
  }

  toggleFollow(): boolean {
    const d = this.detail;
    if (d === null) {
      return false;
    }
    if (FollowStore.inst.isFollowed(d.siteId, d.roomId)) {
      FollowStore.inst.unfollow(d.siteId, d.roomId);
      return false;
    }
    FollowStore.inst.follow(d);
    return true;
  }

  private async loadSuperChats(d: LiveRoomDetail, seq: number): Promise<void> {
    try {
      const list = await this.site.getSuperChats(d.roomId);
      if (seq !== this.seq) {
        return;
      }
      const now = Date.now() / 1000;
      this.superChats = list.filter((s: SuperChatMessage) => s.endTime === 0 || s.endTime > now)
        .map((s: SuperChatMessage) => {
          const c = new ScCard();
          c.id = ++this.chatId;
          c.sc = s;
          return c;
        });
    } catch (e) {
      // SC is optional
    }
  }

  /** Compiled block list; rebuilt only when the setting changes (this runs per message). */
  private blockPlain: string[] = [];
  private blockRegex: RegExp[] = [];
  private blockSource: string = ' ';

  private syncBlockWords(): void {
    const words = Settings.inst.blockWords;
    const key = words.join('');
    if (key === this.blockSource) {
      return;
    }
    this.blockSource = key;
    this.blockPlain = [];
    this.blockRegex = [];
    for (const w of words) {
      if (w.length === 0) {
        continue;
      }
      if (w.length > 2 && w.startsWith('/') && w.endsWith('/')) {
        try {
          this.blockRegex.push(new RegExp(w.substring(1, w.length - 1)));
        } catch (e) {
          // invalid pattern: ignore
        }
      } else {
        this.blockPlain.push(w);
      }
    }
  }

  private isBlocked(text: string): boolean {
    this.syncBlockWords();
    for (const w of this.blockPlain) {
      if (text.indexOf(w) >= 0) {
        return true;
      }
    }
    for (const re of this.blockRegex) {
      if (re.test(text)) {
        return true;
      }
    }
    return false;
  }

  private startDanmaku(d: LiveRoomDetail): void {
    this.stopDanmaku();
    if (d.siteId === 'bilibili' && (d.danmakuArgs as BiliDanmakuArgs).token.length === 0) {
      this.danmakuStatus = '弹幕服务暂不可用，视频仍可播放';
      return;
    }
    const dm = this.site.createDanmaku();
    const seq = this.seq;
    dm.onMessage = (m: LiveMessage) => {
      if (seq === this.seq && this.danmaku === dm) {
        this.onMessage(m);
      }
    };
    dm.onStatus = (s: string) => {
      if (seq === this.seq && this.danmaku === dm) {
        this.danmakuConnected = false;
        this.danmakuStatus = s;
      }
    };
    dm.onReady = () => {
      if (seq === this.seq && this.danmaku === dm) {
        this.danmakuConnected = true;
        this.danmakuStatus = '';
      }
    };
    this.danmaku = dm;
    dm.start(d.danmakuArgs);
  }

  private stopDanmaku(): void {
    this.danmaku?.stop();
    this.danmaku = null;
    this.danmakuConnected = false;
    if (this.flushTimer >= 0) {
      clearTimeout(this.flushTimer);
      this.flushTimer = -1;
    }
    this.pendingChats = [];
    if (this.blockedTimer >= 0) {
      clearTimeout(this.blockedTimer);
      this.blockedTimer = -1;
    }
    this.blockedPending = 0;
  }

  private onMessage(m: LiveMessage): void {
    if (m.type === LiveMessageType.Online) {
      if (m.online > 0) {
        this.online = m.online;
      }
      return;
    }
    if (m.type === LiveMessageType.SuperChat && m.superChat !== null) {
      const c = new ScCard();
      c.id = ++this.chatId;
      c.sc = m.superChat;
      this.superChats = [c].concat(this.superChats).slice(0, 30);
      if (Settings.inst.showSuperChat) {
        this.latestSc = c;
      }
      return;
    }
    if (this.isBlocked(m.text)) {
      this.blockedPending++;
      if (this.blockedTimer < 0) {
        this.blockedTimer = setTimeout(() => {
          this.blockedTimer = -1;
          this.blockedChats += this.blockedPending;
          this.blockedPending = 0;
        }, 300);
      }
      return;
    }
    this.onBullet?.(m.text, m.color);
    const line = new ChatLine();
    line.id = ++this.chatId;
    line.user = m.userName;
    line.text = m.text;
    line.color = m.color;
    this.pendingChats.push(line);
    // batch list updates so a busy room doesn't rebuild the chat list per message
    if (this.flushTimer < 0) {
      this.flushTimer = setTimeout(() => {
        this.flushTimer = -1;
        const merged = this.chats.concat(this.pendingChats);
        this.pendingChats = [];
        this.chats = merged.length > MAX_CHAT ? merged.slice(merged.length - MAX_CHAT) : merged;
      }, 200);
    }
  }

  dispose(): void {
    this.disposed = true;
    this.seq++;
    this.playSeq++;
    this.relay?.dispose();
    this.relay = null;
    if (this.expiryTimer >= 0) {
      clearTimeout(this.expiryTimer);
      this.expiryTimer = -1;
    }
    this.stopDanmaku();
    this.player.release();
    this.onBullet = null;
  }
}
