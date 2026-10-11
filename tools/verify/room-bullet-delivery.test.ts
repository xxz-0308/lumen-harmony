import assert from 'node:assert/strict';
import { mock } from 'node:test';
import { RoomBulletDelivery } from '../../entry/src/main/ets/danmaku/RoomBulletDelivery';

mock.timers.enable({apis:['setTimeout','Date']});
class Renderer {
  active=false; texts:string[]=[];
  setActive(active:boolean){this.active=active;}
  pushScoped(text:string){assert.equal(this.active,true);this.texts.push(text);}
}
try {
  const main=new Renderer(),pip=new Renderer();let latency=7000;
  const delivery=new RoomBulletDelivery(()=>latency);
  delivery.bindMain(main);delivery.setPresentation(true,false,true);
  delivery.push('queued before handoff',0xffffff);mock.timers.tick(1000);
  delivery.setPresentation(false,true,true);assert.equal(main.active,false);
  mock.timers.tick(6000);assert.deepEqual(main.texts,[]);
  delivery.bindPip(pip);assert.deepEqual(pip.texts,['queued before handoff'],'unready PiP retains original pending deadlines');
  delivery.push('pip while app hidden',0xffffff);mock.timers.tick(6000);
  assert.deepEqual(pip.texts,['queued before handoff','pip while app hidden']);
  delivery.push('restore pending',0xffffff);mock.timers.tick(1000);
  delivery.setPresentation(true,false,true);assert.equal(pip.active,false);assert.equal(main.active,true);
  mock.timers.tick(5000);assert.deepEqual(main.texts,['restore pending'],'one queue follows the active target without replaying chat history');
  latency=0;delivery.setPresentation(true,false,false);delivery.push('disabled',0xffffff);mock.timers.tick(10000);
  delivery.setPresentation(true,false,true);delivery.push('new after enable',0xffffff);
  assert.deepEqual(main.texts,['restore pending','new after enable']);
  delivery.setPresentation(false,false,true);delivery.push('genuinely hidden',0xffffff);
  delivery.setPresentation(true,false,true);assert.equal(main.texts.length,2);
  delivery.dispose();delivery.push('disposed',0xffffff);mock.timers.tick(10000);
  assert.equal(main.active,false);assert.equal(pip.active,false);assert.equal(main.texts.length,2);
} finally { mock.timers.reset(); }
console.log('Room bullet delivery: single active target, PiP readiness, preserved deadlines, background delivery, restore, off and disposal passed');
