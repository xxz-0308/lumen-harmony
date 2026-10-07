/** Window adaptation never mutates the saved theater-panel preference. */
export function isNarrowTheater(width: number): boolean {
  return width < 900;
}

export function showTheaterPanel(width: number, fullscreen: boolean,
  preferredOpen: boolean, drawerOpen: boolean): boolean {
  return !fullscreen && preferredOpen && (!isNarrowTheater(width) || drawerOpen);
}
