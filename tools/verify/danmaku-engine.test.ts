import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { emitFrame, resetSyncs, syncs } from './kit-display-sync';

Object.assign(globalThis, { ObservedV2: (value: unknown) => value, Trace: () => {} });
const { Settings } = await import('../../entry/src/main/ets/app/Settings');
const { DanmakuEngine } = await import('../../entry/src/main/ets/danmaku/DanmakuEngine');
const updating = process.env.UPDATE_DANMAKU_TRACE === '1';
const fixture = new URL('../fixtures/danmaku-engine-trace.json', import.meta.url);
const results: Record<string, object> = {};

// The golden trace was recorded from the unchanged v1.0.0 renderer before in-place compaction.
// These are Canvas command traces, not a claim about native GPU output or measured device FPS.
for (const style of ['none', 'stroke', 'shadow']) {
  resetSyncs();
  Object.assign(Settings.inst, {
    danmakuSize: 18, danmakuArea: 0.6, danmakuSpeed: 1,
    danmakuMax: 70, danmakuOpacity: 0.72, danmakuKeepColor: true, danmakuStroke: style
  });
  const hash = createHash('sha256');
  let fills = 0, strokes = 0, clears = 0;
  const ctx = {
    font: '', textBaseline: '', globalAlpha: 1, lineJoin: '', lineWidth: 1,
    strokeStyle: '', fillStyle: '', shadowBlur: 0, shadowColor: '', shadowOffsetX: 0, shadowOffsetY: 0,
    measureText(text: string): { width: number } {
      const size = Number(this.font.match(/(\d+)vp/)?.[1] ?? 18);
      return { width: text.length * size * 0.55 };
    },
    clearRect(...rect: number[]): void { clears++; hash.update(JSON.stringify(['clear', ...rect])); },
    fillText(text: string, x: number, y: number): void {
      fills++;
      hash.update(JSON.stringify(['fill', text, x, y, this.font, this.fillStyle, this.globalAlpha,
        this.shadowBlur, this.shadowColor, this.shadowOffsetX, this.shadowOffsetY]));
    },
    strokeText(text: string, x: number, y: number): void {
      strokes++;
      hash.update(JSON.stringify(['stroke', text, x, y, this.font, this.strokeStyle, this.lineWidth, this.globalAlpha]));
    }
  };
  const engine = new DanmakuEngine(ctx as never);
  const state = engine as unknown as { bullets: unknown[]; queue: unknown[]; laneTail: unknown[] };
  engine.resize(960, 540);
  engine.start();
  assert.deepEqual(syncs[0].range, { expected: 120, min: 60, max: 144 });
  let maxQueue = 0;
  for (let frame = 0; frame < 1800; frame++) {
    if (frame < 150 && frame % 3 === 0) {
      for (let n = 0; n < 5; n++) engine.push(`${frame}:${n} 弹幕测试 🎮 ${'长'.repeat(n * 16)}`, n ? 0xff8800 : 0);
    }
    if (frame === 165) {
      Settings.inst.danmakuMax = 12;
      Settings.inst.danmakuArea = 0.3;
      engine.trim();
    }
    if (frame === 200) { engine.visible = false; engine.clear(); }
    if (frame === 225) { engine.visible = true; engine.push('重新显示', 0xffffff); }
    if (frame === 260) { engine.resize(720, 480); engine.push('尺寸变化', 0x1e87f0); }
    if (frame === 280) { Settings.inst.danmakuSize = 24; engine.clear(); engine.push('样式变化', 0xffffff); }
    if (frame === 300) { Settings.inst.danmakuKeepColor = false; engine.push('统一白色', 0xff0000); }
    const bullets = state.bullets, queue = state.queue;
    emitFrame(Math.round((frame + 1) * 1e9 / 120));
    if (!updating) {
      assert.equal(state.bullets, bullets, 'a frame reuses the live-bullet container');
      assert.equal(state.queue, queue, 'a frame reuses the waiting container');
    }
    maxQueue = Math.max(maxQueue, state.queue.length);
    assert.ok(state.queue.length <= 30);
    assert.ok(state.bullets.length + state.queue.length <= Settings.inst.danmakuMax || frame === 165);
  }
  assert.equal(state.bullets.length, 0);
  assert.equal(state.queue.length, 0);
  assert.ok(syncs.every(s => !s.running && s.callback === null), 'empty drawing parks and detaches the frame listener');
  engine.push('空闲后重启', 0xffffff);
  emitFrame(20e9);
  assert.ok(syncs.some(s => s.running));
  engine.stop();
  assert.ok(syncs.every(s => !s.running && s.callback === null));
  results[style] = { hash: hash.digest('hex'), fills, strokes, clears, maxQueue };
}
if (updating) {
  writeFileSync(fixture, JSON.stringify(results, null, 2) + '\n');
  console.log('Recorded the baseline renderer traces.');
} else {
  assert.deepEqual(results, JSON.parse(readFileSync(fixture, 'utf-8')),
    'positions, ordering, font/colour/stroke/shadow, queueing, resize, hide and idle match the baseline');
  console.log('Danmaku engine: baseline draw traces preserved; no per-frame container replacements');
}
