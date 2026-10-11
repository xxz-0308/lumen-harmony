const data = new Map<string, string>();
let openUnavailable = false;
const stats = new Map<string, { putSync: number; flush: number }>();
const flushHooks = new Map<string, () => Promise<void>>();
function counts(name: string) {
  if (!stats.has(name)) stats.set(name, { putSync: 0, flush: 0 });
  return stats.get(name)!;
}
export function getTestPreferenceStats(name: string) { return { ...counts(name) }; }
export function resetTestPreferenceStats(name: string): void { stats.delete(name); }
export function setTestFlushHook(name: string, hook: (() => Promise<void>) | null): void {
  if (hook) flushHooks.set(name, hook); else flushHooks.delete(name);
}
export function setTestOpenUnavailable(unavailable: boolean): void {
  openUnavailable = unavailable;
}
export function setTestPreference(name: string, key: string, value: string): void {
  data.set(`${name}:${key}`, value);
}
export function getTestPreference(name: string, key: string): string | undefined {
  return data.get(`${name}:${key}`);
}
export const preferences = {
  getPreferencesSync: (_context: unknown, options: { name: string }) => {
    if (openUnavailable) throw new Error('test preference store unavailable');
    return {
    getSync: (key: string, fallback: string): string => data.get(`${options.name}:${key}`) ?? fallback,
    putSync: (key: string, value: string): void => { counts(options.name).putSync++; data.set(`${options.name}:${key}`, value); },
    flush: async (): Promise<void> => { counts(options.name).flush++; const hook = flushHooks.get(options.name); if (hook) await hook(); },
    flushSync: (): void => {}
    };
  }
};
