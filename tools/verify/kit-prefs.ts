const data = new Map<string, string>();
let openUnavailable = false;
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
    putSync: (key: string, value: string): void => { data.set(`${options.name}:${key}`, value); },
    flush: async (): Promise<void> => {},
    flushSync: (): void => {}
    };
  }
};
