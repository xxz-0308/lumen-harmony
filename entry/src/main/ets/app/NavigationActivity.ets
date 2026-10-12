/** Freeze retained root content before navigation and through the visual return animation. */
@ObservedV2
export class NavigationActivity {
  static readonly inst: NavigationActivity = new NavigationActivity();
  @Trace rootActive: boolean = true;
  private rootVisible: boolean = true;
  private holds: number = 0;

  setRootVisible(visible: boolean, hasDestination: boolean = false): void {
    this.rootVisible = visible && !hasDestination;
    this.rootActive = this.rootVisible && this.holds === 0;
  }

  holdRoot(): void {
    this.holds++;
    this.rootActive = false;
  }

  releaseRoot(): void {
    this.holds = Math.max(0, this.holds - 1);
    this.rootActive = this.rootVisible && this.holds === 0;
  }
}
