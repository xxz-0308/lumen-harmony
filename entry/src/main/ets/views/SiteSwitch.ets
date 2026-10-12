import { SiteId } from '../core/model/Models';

/**
 * Shared platform-switch geometry and gesture helpers for HomeView and CategoryView.
 */
export class SiteSwitch {
  static readonly LABELS: string[] = ['虎牙', '斗鱼', 'B站'];
  static readonly DURATION_MS: number = 280;

  static offset(ids: SiteId[], site: SiteId, current: SiteId, reduceMotion: boolean): number {
    if (reduceMotion || site === current) return 0;
    return ids.indexOf(site) < ids.indexOf(current) ? -28 : 28;
  }

  static swipedIndex(ids: SiteId[], current: SiteId, dx: number, dy: number): number {
    if (Math.abs(dx) < 36 || Math.abs(dx) < Math.abs(dy) * 1.15) return -1;
    const cur = ids.indexOf(current);
    if (dx < 0 && cur < ids.length - 1) return cur + 1;
    if (dx > 0 && cur > 0) return cur - 1;
    return -1;
  }

  static include(list: SiteId[], id: SiteId): SiteId[] {
    return list.includes(id) ? list : list.concat(id);
  }
}
