import { deviceInfo } from '@kit.BasicServicesKit';
import { C, Radius } from '../theme/Theme';
import { AppEnv } from '../app/AppEnv';

/** New material APIs are never imported or invoked on our API 24 baseline. */
export async function loadDockMaterial(reduceMotion: boolean): Promise<SystemUiMaterial | undefined> {
  if (deviceInfo.sdkApiVersion < 26) return undefined;
  try {
    const module = await import('@ohos.arkui.uiMaterial');
    if (!module.default.isImmersiveMaterialSupported() ||
      module.default.getMaterialInfo().state === module.default.MaterialState.DISABLE) {
      return undefined;
    }
    return new module.default.ImmersiveMaterial({
      style: module.default.ImmersiveStyle.REGULAR,
      colorInvert: false,
      applyShadow: true,
      interactive: false,
      lightEffect: reduceMotion ? null : { color: Color.White }
    });
  } catch (e) {
    // Material is progressive enhancement; navigation must remain available.
    return undefined;
  }
}

export class DockMaterialModifier implements AttributeModifier<RowAttribute> {
  private material: SystemUiMaterial | undefined;

  constructor(material: SystemUiMaterial | undefined) {
    this.material = material;
  }

  applyNormalAttribute(instance: RowAttribute): void {
    if (deviceInfo.sdkApiVersion >= 26 && typeof instance.systemMaterial === 'function') {
      if (this.material !== undefined) {
        // Do not layer app backgrounds/borders/shadows over a system material.
        instance.backgroundEffect(undefined).backgroundColor(undefined).border(undefined).shadow(undefined);
        instance.systemMaterial(this.material).borderRadius(Radius.pill);
        return;
      }
      instance.systemMaterial(undefined);
    }
    // One backdrop filter, not blur plus an opaque foreground fill. AVERAGE needs alpha.
    instance.backgroundColor(Color.Transparent)
      .backgroundEffect({
        radius: 18,
        saturation: 1.12,
        brightness: AppEnv.inst.isDark ? 0.94 : 1.04,
        color: C.navSurface,
        adaptiveColor: AdaptiveColor.AVERAGE,
        policy: BlurStyleActivePolicy.FOLLOWS_WINDOW_ACTIVE_STATE,
        inactiveColor: C.bgElevated
      })
      .borderWidth(0.5)
      .borderColor(C.navStroke)
      .borderRadius(Radius.pill)
      .shadow({ radius: 12, color: C.navShadow, offsetY: 2 });
  }
}
