import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { transform } from 'esbuild';
import { PlayState } from '../../entry/src/main/ets/player/PlayerApi';

// Compile the actual non-UI component methods. Native layout/rendering is checked by the SDK
// build and device smoke run, not by this fixture. No application method is reimplemented here.
async function logicStruct(file: string, name: string, end: string, mocks: Record<string, unknown>): Promise<any> {
  const src = readFileSync(new URL(file, import.meta.url), 'utf-8');
  const marker = `export struct ${name} {`;
  const start = src.indexOf(marker) + marker.length;
  assert.ok(start >= marker.length);
  let body = src.slice(start, src.indexOf(end, start));
  body = body.replace(/^\s*@(Param|Local|Event|BuilderParam)\s+/gm, '\n  ')
    .replace(/^\s*@Monitor\([^\n]*\)\s*\n/gm, '\n');
  const constants = (src.match(/^const (INFO_H|GAP): number = \d+;/gm) ?? []).join('\n');
  const key = `__fixture_${name}`;
  (globalThis as any)[key] = mocks;
  const code = `const {${Object.keys(mocks).join(',')}} = globalThis.${key};\n${constants}\nexport class ${name} {${body}\n}`;
  const out = await transform(code, { loader: 'ts', target: 'es2022', format: 'esm' });
  return (await import(`data:text/javascript,${encodeURIComponent(out.code)}`))[name];
}
function deferred<T>() {
  let resolve!: (value: T) => void, reject!: (error: Error) => void;
  const promise = new Promise<T>((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}
const flush = async () => { for (let i = 0; i < 5; i++) await Promise.resolve(); };
class Clock {
  now = 0; id = 0;
  jobs = new Map<number, { at: number; fn: () => void; period: number }>();
  timeout = (fn: () => void, delay: number) => this.add(fn, delay, 0);
  interval = (fn: () => void, delay: number) => this.add(fn, delay, delay);
  clear = (id: number) => { this.jobs.delete(id); };
  add(fn: () => void, delay: number, period: number) {
    const id = ++this.id; this.jobs.set(id, { at: this.now + delay, fn, period }); return id;
  }
  advance(delay: number) {
    const end = this.now + delay;
    while (true) {
      const next = [...this.jobs].filter(([, j]) => j.at <= end).sort((a,b) => a[1].at-b[1].at)[0];
      if (!next) break;
      const [id, job] = next; this.now = job.at;
      if (job.period) job.at += job.period; else this.jobs.delete(id);
      job.fn();
    }
    this.now = end;
  }
}
const clock = new Clock();
const originalTimers = { setTimeout, clearTimeout, setInterval, clearInterval };
Object.assign(globalThis, { setTimeout: clock.timeout, setInterval: clock.interval, clearTimeout: clock.clear, clearInterval: clock.clear });
const effects: string[] = [];
let pops = 0, capture = deferred<any>(), pipStart = deferred<void>();
const settings = { danmakuOn:true, sideChat:true, videoFill:false, theaterPanelOpen:true, volumeMode:'app', appVolume:1, leaveBehavior:'pip', scheduleSave:()=>effects.push('save') };
let volumeWrite: (value: number) => Promise<boolean> = async () => true;
const env: any = {
  winWidth:1200, winHeight:800, statusBarHeight:20, navBarHeight:20, reduceMotion:false, foreground:false,
  subscribeForeground:()=>effects.push('subscribe'), unsubscribeForeground:()=>effects.push('unsubscribe'),
  setKeepScreenOn:()=>effects.push('screen'), setBrightness:()=>effects.push('brightness'),
  setImmersive:()=>{}, setLandscape:()=>{}
};
class Model {
  siteId='huya'; roomId='1'; preview=null; disposals=0;
  player={ firstFrame:true, state:2, wantsPlayback:true, pause:()=>{}, setVolume:()=>{} };
  dispose(){ this.disposals++; this.player.state=0; }
}
class Pip {
  static supported(){ return true; }
  constructor(public handlers:any){}
  dispose(){ effects.push('pip-dispose'); }
  setContentSize(){ effects.push('pip-size'); }
  setPlaying(){ effects.push('pip-playing'); }
  setAutoStart(){ effects.push('pip-auto'); }
  start(){ return pipStart.promise; }
}
class Route { coverW=300; coverH=169; coverX=20; coverY=30; preview=null; }
try {
  const Page = await logicStruct('../../../entry/src/main/ets/pages/LiveRoomPage.ets', 'LiveRoomPage', '  // ---------- builders ----------', {
    RoomModel:Model, AppEnv:{inst:env}, Settings:{inst:settings}, LivePip:Pip, LiveRouteParam:Route,
    BackgroundAudio:{detach:()=>effects.push('detach'), setMetadata:()=>effects.push('metadata'), update:()=>effects.push('audio')},
    Nav:{stack:{pop:()=>pops++}}, Log:{i:()=>{},w:()=>{}}, MediaVolume:{write:(value:number)=>volumeWrite(value)},
    image:{createPixelMapFromSurface:()=>capture.promise}, promptAction:{showToast:()=>effects.push('toast')},
    PlayState, NavigationOperation:{PUSH:1,POP:2},
    Radius:{lg:16,xl:24}, Curve:{Friction:0,EaseIn:1,EaseOut:2},
    isNarrowTheater:(w:number)=>w<900, showTheaterPanel:()=>true
  });
  const fresh = () => {
    const p = new Page();
    p.sourceRoomKey='huya_1';
    p.videoXc={getXComponentSurfaceRect:()=>({surfaceWidth:320,surfaceHeight:180}),getXComponentSurfaceId:()=> 'surface'};
    return p;
  };
  let p=fresh(), pauses=0;
  p.pauseForBackground=()=>pauses++;
  p.pip.handlers.onActive(false,false);
  assert.equal(clock.jobs.size,1);
  clock.advance(500);
  assert.equal(pauses,1,'an active background room retains the PiP-close grace check');
  p.pip.handlers.onActive(false,false);
  p.disposeRoom('navigation');
  const count=effects.length;
  clock.advance(3000);
  p.pip.handlers.onActive(true,false);
  p.onForeground(); p.onPlayState(); p.onVideoSize(); p.onPanelVisibility(); p.armHide(); p.showHud('volume',0.5); p.setSleep(1); p.tickSleep(); p.finishSleep();
  assert.equal(effects.length,count,'disposed rooms cannot update system playback/window state');
  assert.equal(clock.jobs.size,0,'dispose cancels owned checks and blocks rescheduling');
  assert.equal(p.pipActive,false);
  p.disposeRoom('component');
  assert.equal(p.model.disposals,1,'PiP-cached navigation disposal is idempotent');

  p=fresh(); capture=deferred<any>(); let releases=0;
  p.goBack(); assert.equal(clock.jobs.size,1);
  p.disposeRoom('navigation');
  assert.equal(p.videoXc,null);
  capture.resolve({release:()=>releases++}); await flush(); clock.advance(500);
  assert.equal(pops,0,'a stale screenshot completion cannot pop the next room');
  assert.equal(releases,1,'a screenshot produced after disposal is released');
  assert.equal(clock.jobs.size,0);

  p=fresh(); capture=deferred<any>(); const pixel={release:()=>releases++};
  p.goBack(); capture.resolve(pixel); await flush();
  assert.equal(pops,1); assert.equal(clock.jobs.size,0);
  p.disposeRoom('navigation');
  assert.equal(p.morphPixel,pixel,'resource cleanup preserves the visible return snapshot');
  const transition=p.roomTransition(2,false);
  assert.equal(p.morphOn,true,'return animation still runs after willDisappear cleanup');
  transition[0].onTransitionEnd();
  assert.equal(p.morphPixel,null);

  p=fresh(); capture=deferred<any>(); p.goBack(); clock.advance(150);
  assert.equal(pops,2,'slow screenshots retain the original 150ms return deadline');
  capture.resolve({release:()=>releases++}); await flush();
  assert.equal(pops,2,'a late screenshot does not issue a second pop');
  p.disposeRoom('component');
  p=fresh(); pipStart=deferred<void>(); p.startPip(); p.disposeRoom('component');
  const toasts=effects.filter(e=>e==='toast').length;
  pipStart.reject(new Error('late failure')); await flush();
  assert.equal(effects.filter(e=>e==='toast').length,toasts);

  const written:number[]=[];
  let firstVolume=deferred<boolean>(),secondVolume=deferred<boolean>();
  volumeWrite=value=>{written.push(value);return written.length===1?firstVolume.promise:secondVolume.promise;};
  settings.volumeMode='media'; p=fresh();
  p.changeVolume(0.25); p.changeVolume(0.5); await flush();
  assert.deepEqual(written,[0.25]); p.disposeRoom('navigation');
  const afterDispose=effects.length;
  firstVolume.resolve(false); await flush(); secondVolume.resolve(false); await flush();
  assert.deepEqual(written,[0.25,0.5],'accepted system writes remain ordered even after their page leaves');
  assert.equal(settings.volumeMode,'media'); assert.equal(effects.length,afterDispose);
  p.changeVolume(0.75); await flush(); assert.equal(written.length,2);

  written.length=0;firstVolume=deferred<boolean>();secondVolume=deferred<boolean>();p=fresh();
  p.changeVolume(0.25);p.changeVolume(0.5);await flush();firstVolume.resolve(false);await flush();
  assert.equal(settings.volumeMode,'media','an earlier failure must not override a newer volume intent');
  secondVolume.resolve(true);await flush();assert.equal(settings.volumeMode,'media');
  p=fresh();volumeWrite=async()=>false;
  p.changeVolume(0.6);await flush();assert.equal(settings.volumeMode,'app','current failure retains the existing fallback');
  settings.volumeMode='media';p=fresh();const changedRoom=deferred<boolean>();volumeWrite=()=>changedRoom.promise;
  p.changeVolume(0.7);p.model.roomId='next-room';changedRoom.resolve(false);await flush();
  assert.equal(settings.volumeMode,'media','failure in a former room does not affect the replacement room');
  settings.volumeMode='app';

  const searchModel={keyword:'old',mode:'room',filter:'all',results:[],feed:null,searched:true,onUpdate:null as null|(()=>void)};
  const Search=await logicStruct('../../../entry/src/main/ets/views/SearchView.ets','SearchView','  @Builder\n  searchBar()',{
    SearchModel:{inst:searchModel},Settings:{inst:{searchHistory:[]}},Space:{md:12}
  });
  const oldSearch=new Search(),newSearch=new Search();oldSearch.aboutToAppear();const oldUpdate=searchModel.onUpdate!;
  newSearch.aboutToAppear();oldSearch.aboutToDisappear();searchModel.keyword='new';searchModel.onUpdate!();
  assert.equal(newSearch.keyword,'new');assert.equal(oldSearch.keyword,'old');oldUpdate();assert.equal(oldSearch.keyword,'old');
  newSearch.aboutToDisappear();assert.equal(searchModel.onUpdate,null,'old search cleanup preserves the newer owner');

  const tasks=new Map<string,ReturnType<typeof deferred<any>>>();
  const loads:string[]=[];
  const ImageView=await logicStruct('../../../entry/src/main/ets/components/Basics.ets','NetImage','  build() {',{
    image:{},C:{skeleton:0},ImageFit:{Cover:0},AppEnv:{inst:{foreground:true}},ImageLoader:{
      needsManual:(url:string)=>url.startsWith('manual:'),cached:()=>null,
      load:(url:string)=>{loads.push(url);if(!tasks.has(url))tasks.set(url,deferred<any>());return tasks.get(url)!.promise;}
    }
  });
  const one=new ImageView(),two=new ImageView();one.src=two.src='manual:A';
  one.aboutToAppear();two.aboutToAppear();one.aboutToDisappear();
  const pm={release:()=>{throw new Error('shared image must not be released by a view');}};
  tasks.get('manual:A')!.resolve(pm);await flush();
  assert.equal(one.pixel,null);assert.equal(two.pixel,pm,'another mounted owner still receives the shared download');
  two.src='manual:B';two.onSrc();two.src='manual:C';two.onSrc();
  tasks.get('manual:B')!.resolve({});await flush();assert.equal(two.pixel,null);
  const current={};tasks.get('manual:C')!.resolve(current);await flush();assert.equal(two.pixel,current);
  two.aboutToDisappear();const n=loads.length;two.src='manual:D';two.onSrc();
  assert.equal(loads.length,n,'an unmounted owner starts no new manual request');
  two.aboutToAppear();assert.equal(loads.at(-1),'manual:D');
  tasks.get('manual:D')!.resolve({});await flush();
  two.visible=false;two.onActivity();const beforeHidden=loads.length;two.src='manual:E';two.onSrc();
  assert.equal(loads.length,beforeHidden,'hidden manual-image consumers do not request replacements');
  two.visible=true;two.onActivity();assert.equal(loads.at(-1),'manual:E');
  two.env.foreground=false;two.onActivity();tasks.get('manual:E')!.resolve({});await flush();assert.equal(two.pixel,null);
  two.env.foreground=true;two.onActivity();await flush();assert.notEqual(two.pixel,null,'foreground consumer resumes shared completed work');
  const followState={items:[] as any[],contentRevision:0,refreshing:false,refreshFailures:0,storageError:'',saveError:'',lastRefreshAt:0,
    subscribe:()=>{},unsubscribe:()=>{},refreshAll:()=>{}};
  const Follow=await logicStruct('../../../entry/src/main/ets/views/FollowView.ets','FollowView','  get contentW(): number',{
    FollowStore:{inst:followState}
  });
  const followView=new Follow();followView.aboutToAppear();const followSnapshot=followView.snapshot;
  followState.refreshing=true;followState.saveError='fixture error';followView.syncFollows();
  assert.equal(followView.snapshot,followSnapshot);assert.equal(followView.refreshing,true);assert.equal(followView.saveError,'fixture error');
  followView.active=false;followState.items=[{}];followState.contentRevision++;followView.syncFollows();
  assert.equal(followView.snapshot,followSnapshot);followView.active=true;followView.onActive();assert.equal(followView.snapshot.length,1);
  followView.aboutToDisappear();const detachedSnapshot=followView.snapshot;followState.contentRevision++;followView.syncFollows();
  assert.equal(followView.snapshot,detachedSnapshot);

  const glowTasks=new Map<string,ReturnType<typeof deferred<any>>>(),glowLoads:string[]=[];
  const Glow=await logicStruct('../../../entry/src/main/ets/components/Decor.ets','AmbientGlow','  @Builder\n  layer(',{
    AppEnv:{inst:{foreground:true,reduceMotion:false}},GlowLoader:{cached:()=>null,load:(url:string)=>{
      glowLoads.push(url);if(!glowTasks.has(url))glowTasks.set(url,deferred<any>());return glowTasks.get(url)!.promise;
    }}
  });
  const glow=new Glow();glow.active=false;glow.src='A';glow.aboutToAppear();assert.equal(glowLoads.length,0);
  glow.active=true;glow.onSrc();glow.active=false;glow.onSrc();glow.src='B';glow.onSrc();
  const sharedGlow={release:()=>{throw new Error('shared output cannot be released by a view');}};
  glowTasks.get('A')!.resolve(sharedGlow);await flush();assert.equal(glow.front,null);
  glow.active=true;glow.onSrc();glowTasks.get('B')!.resolve(sharedGlow);await flush();assert.equal(glow.front,sharedGlow);
  glow.strength=0;glow.src='C';glow.onSrc();assert.deepEqual(glowLoads,['A','B']);
  glow.strength=1;glow.onSrc();glow.aboutToDisappear();glowTasks.get('C')!.resolve({});await flush();assert.equal(glow.front,sharedGlow);
  console.log('Component tasks: callback ownership, accepted volume intent, retained snapshots and offscreen shared glow passed');
} finally {
  Object.assign(globalThis,originalTimers);
}
