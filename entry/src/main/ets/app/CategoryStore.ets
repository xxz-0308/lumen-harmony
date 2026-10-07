import { LiveCategory, LiveSubCategory, SiteId } from '../core/model/Models';
import { Sites } from '../core/sites/Sites';
import { Settings } from './Settings';

@ObservedV2
export class SiteCategories {
  siteId: SiteId = 'huya';
  @Trace groups: LiveCategory[] = [];
  @Trace loading: boolean = false;
  @Trace error: string = '';

  constructor(siteId: SiteId) {
    this.siteId = siteId;
  }

  async load(): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    this.error = '';
    try {
      const groups = await Sites.of(this.siteId).getCategories();
      this.groups = groups.filter((g: LiveCategory) => g.children.length > 0);
    } catch (e) {
      this.error = '分类加载失败';
    } finally {
      this.loading = false;
    }
  }
}

export class CategoryStore {
  private static cache: Map<string, SiteCategories> = new Map<string, SiteCategories>();
  private static favoriteListeners: Set<() => void> = new Set<() => void>();

  static subscribeFavorites(listener: () => void): void {
    CategoryStore.favoriteListeners.add(listener);
  }

  static unsubscribeFavorites(listener: () => void): void {
    CategoryStore.favoriteListeners.delete(listener);
  }

  private static notifyFavorites(): void {
    CategoryStore.favoriteListeners.forEach((listener: () => void) => listener());
  }

  /** Pure lookup. Call `ensure(site)` from lifecycle code, never from a @Computed getter. */
  static of(site: SiteId): SiteCategories {
    let c = CategoryStore.cache.get(site);
    if (c === undefined) {
      c = new SiteCategories(site);
      CategoryStore.cache.set(site, c);
    }
    return c;
  }

  /** Starts the first load if the site has never been fetched. Safe to call repeatedly. */
  static ensure(site: SiteId): void {
    const c = CategoryStore.of(site);
    if (c.groups.length === 0 && !c.loading) {
      c.load();
    }
  }

  static encode(c: LiveSubCategory): string {
    return [c.siteId, c.id, c.parentId, c.name.replace(/\|/g, ' '), c.pic].join('|');
  }

  static decode(s: string): LiveSubCategory | null {
    const p = s.split('|');
    if (p.length < 5 || !Sites.isSiteId(p[0])) {
      return null;
    }
    const c = new LiveSubCategory();
    c.siteId = p[0] as SiteId;
    c.id = p[1];
    c.parentId = p[2];
    c.name = p[3];
    c.pic = p.slice(4).join('|');
    return c;
  }

  static favorites(): LiveSubCategory[] {
    const out: LiveSubCategory[] = [];
    for (const s of Settings.inst.favCategories) {
      const c = CategoryStore.decode(s);
      if (c !== null) {
        out.push(c);
      }
    }
    return out;
  }

  static isFavorite(c: LiveSubCategory): boolean {
    return Settings.inst.favCategories.some((s: string) => s.startsWith(`${c.siteId}|${c.id}|`));
  }

  static toggleFavorite(c: LiveSubCategory): boolean {
    if (CategoryStore.isFavorite(c)) {
      Settings.inst.favCategories =
        Settings.inst.favCategories.filter((s: string) => !s.startsWith(`${c.siteId}|${c.id}|`));
      Settings.inst.scheduleSave();
      CategoryStore.notifyFavorites();
      return false;
    }
    Settings.inst.favCategories = [CategoryStore.encode(c)].concat(Settings.inst.favCategories).slice(0, 40);
    Settings.inst.scheduleSave();
    CategoryStore.notifyFavorites();
    return true;
  }
}
