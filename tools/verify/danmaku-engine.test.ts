import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { emitFrame, resetSyncs, setScopeCheck, syncs } from './kit-display-sync';

Object.assign(globalThis, { ObservedV2: (value: unknown) => value, Trace: () => {} });
const { Settings } = await import('../../entry/src/main/ets/app/Settings');
const { DanmakuEngine } = await import('../../entry/src/main/ets/danmaku/DanmakuEngine');
const updating = process.env.UPDATE_DANMAKU_TRACE === '1';
const fixture = new URL('../fixtures/danmaku-engine-trace.json', import.meta.url);
const results: Record<string, object> = {};

// Keep the historical motion trace by supplying its already-shortened message samples.
// Full-length rendering is checked separately below; no golden regeneration hides this change.
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
      for (let n = 0; n < 5; n++) {
        const sample = `${frame}:${n} 弹幕测试 🎮 ${'长'.repeat(n * 16)}`;
        const historicalText = sample.length > 40 ? sample.substring(0, 40) + '…' : sample;
        engine.push(historicalText, n ? 0xff8800 : 0);
      }
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
  console.log('Danmaku engine: historical motion traces preserved; no per-frame container replacements');
}

resetSyncs();
Object.assign(Settings.inst, { danmakuSize: 18, danmakuArea: 0.6, danmakuSpeed: 1,
  danmakuMax: 70, danmakuOpacity: 1, danmakuKeepColor: true, danmakuStroke: 'none' });
const measured: string[] = [], drawn: string[] = [];
const longContext = {
  font: '', measureText(text: string) { measured.push(text); return { width: text.length * 10 }; },
  clearRect() {}, fillText(text: string) { drawn.push(text); }, strokeText() {}
};
const completeText = '长'.repeat(39) + '🎮' + '后面的内容必须完整显示🙂'.repeat(12);
const fullEngine = new DanmakuEngine(longContext as never);
fullEngine.resize(960, 540); fullEngine.push(completeText, 0xffffff); emitFrame(1e9);
assert.equal(measured[0], completeText, 'width and collision calculations use the full original text');
assert.equal(drawn[0], completeText, 'Canvas receives every character, including emoji across the old boundary');
assert.equal(drawn[0].endsWith('…'), false, 'the client does not append a truncation marker');
fullEngine.stop();
console.log('Danmaku engine: long messages are measured and drawn without client truncation');

resetSyncs();
Object.assign(Settings.inst, { danmakuMax:70, danmakuSize:18, danmakuArea:0.6, danmakuSpeed:1 });
const costEngine=new DanmakuEngine({font:'',measureText:()=>({width:100}),clearRect(){},fillText(){},strokeText(){}} as never);
costEngine.resize(960,80);
const cost=costEngine as unknown as {bullets:any[];queue:any[];place:(b:any)=>boolean};
let scans=0,placements=0;
cost.bullets.indexOf=function(b:any){scans++;return Array.prototype.indexOf.call(this,b);};
const place=cost.place;cost.place=function(b:any){placements++;return place.call(this,b);};
for(let n=0;n<70;n++)costEngine.push(`fixture ${n}`,0xffffff);
assert.equal(cost.queue.length,30,'the saturation benchmark exercises waiting placement');
for(let frame=0;frame<240;frame++)emitFrame(Math.round((frame+1)*1e9/120));
assert.ok(placements>1000);assert.equal(scans,0,'saturated lane admission performs no live-array membership scans');
const expired=cost.bullets[0];expired.x=-10000;emitFrame(Math.round(241*1e9/120));
assert.equal(expired.alive,false,'expiry invalidates the former tail');
const retained=cost.bullets.slice();costEngine.clear();assert.ok(retained.every(b=>!b.alive));costEngine.stop();
console.log(`Danmaku engine: ${placements} saturated placement attempts, zero live-array scans, explicit tail lifetime passed`);

resetSyncs();Object.assign(Settings.inst,{danmakuSize:18,danmakuStroke:'stroke',danmakuKeepColor:true});
const setters:Record<string,number>={};
const paint:any={measureText:()=>({width:100}),clearRect(){},fillText(){},strokeText(){}};
for(const [key,initial] of Object.entries({font:'',textBaseline:'',lineJoin:'',lineWidth:1,strokeStyle:'',fillStyle:'',shadowColor:'',shadowOffsetX:0,shadowOffsetY:0})){
  let value=initial;
  Object.defineProperty(paint,key,{get:()=>value,set:(next:any)=>{setters[key]=(setters[key]??0)+1;value=next;}});
}
const paintEngine=new DanmakuEngine(paint);paintEngine.resize(960,540);paintEngine.push('stable paint',0xffffff);
for(let frame=0;frame<240;frame++)emitFrame(Math.round((frame+1)*1e9/120));
for(const key of ['font','textBaseline','lineJoin','lineWidth','strokeStyle','fillStyle']){
  assert.equal(setters[key],1,`${key} is submitted once for 240 unchanged drawing frames`);
}
assert.equal(paint.globalAlpha,1);assert.equal(paint.shadowBlur,0,'per-frame opacity/shadow cleanup is preserved');
paintEngine.resize(720,480);paintEngine.push('after resize',0xffffff);emitFrame(3e9);
assert.equal(setters.font,2);assert.equal(setters.fillStyle,2,'resize re-establishes the context paint state');
Settings.inst.danmakuStroke='shadow';emitFrame(3.01e9);emitFrame(3.02e9);
assert.equal(setters.shadowColor,1);assert.equal(setters.shadowOffsetX,1);assert.equal(setters.shadowOffsetY,1);
assert.equal(paint.shadowBlur,0);Settings.inst.danmakuSize=24;paintEngine.push('new font size',0xffffff);emitFrame(3.03e9);
assert.equal(setters.font,3,'measurement applies the new font immediately');
paintEngine.clear();paintEngine.push('after clear',0xffffff);emitFrame(3.04e9);assert.equal(setters.font,4);
paintEngine.stop();console.log('Danmaku engine: stable paint setters submitted once over 240 frames; resize/style/font/clear invalidation and cleanup passed');

resetSyncs();let scopeDepth=0;
const frameTasks:(()=>void)[]=[];
const scopedEngine=new DanmakuEngine({font:'',measureText:()=>({width:100}),clearRect(){},fillText(){assert.ok(scopeDepth>0);},strokeText(){assert.ok(scopeDepth>0);}} as never);
scopedEngine.setScope(task=>{frameTasks.push(task);scopeDepth++;try{task();}finally{scopeDepth--;}});
setScopeCheck(()=>scopeDepth>0);
try{
  scopedEngine.resize(960,540);scopedEngine.push('scoped fixture',0xffffff);
  emitFrame(1e9);emitFrame(1.01e9);
  const stableTask=(scopedEngine as unknown as {frameTask:()=>void}).frameTask;
  assert.equal(frameTasks.filter(task=>task===stableTask).length,2,'frame callbacks reuse one scoped task instead of allocating a closure per frame');
  scopedEngine.clear();emitFrame(1.02e9);
  assert.ok(syncs.every(s=>!s.running&&s.callback===null),'idle stop and unsubscribe run in the same owning UI scope');
  scopedEngine.push('resume scoped fixture',0xffffff);emitFrame(2e9);scopedEngine.stop();
  assert.ok(syncs.every(s=>!s.running&&s.callback===null));
}finally{setScopeCheck(null);}
console.log('Danmaku engine: create/start/frame/idle-stop/unsubscribe retain the owning UI context with a stable frame task');
