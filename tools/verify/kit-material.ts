(globalThis as any).materialModuleLoads = ((globalThis as any).materialModuleLoads ?? 0) + 1;
export const materialState = { supported: true, disabled: false, fail: false };
class ImmersiveMaterial {
  constructor(public options: Record<string, unknown>) {}
}
export default {
  isImmersiveMaterialSupported: () => {
    if (materialState.fail) throw new Error('fixture unsupported service');
    return materialState.supported;
  },
  getMaterialInfo: () => ({ state: materialState.disabled ? 2 : 0 }),
  MaterialState: { DISABLE: 2 },
  ImmersiveStyle: { REGULAR: 2 },
  ImmersiveMaterial
};
