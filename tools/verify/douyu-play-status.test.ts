import assert from 'node:assert/strict';
import { DouyuSite } from '../../entry/src/main/ets/core/sites/DouyuSite';
import { LiveRoomDetail } from '../../entry/src/main/ets/core/model/Models';
import { HttpRequest, HttpResponse, Platform } from '../../entry/src/main/ets/core/common/Transport';

let streamStatus = 0;
Platform.http = {
  send: async (req: HttpRequest): Promise<HttpResponse> => {
    const response = new HttpResponse();
    response.status = 200;
    const data = req.url.includes('getEncryption') ? {
      key: 'key', rand_str: 'seed', enc_time: 1, is_special: 0, enc_data: 'public-fixture',
      expire_at: Math.floor(Date.now() / 1000) + 300
    } : {
      streamStatus,
      cdnsWithName: [{ cdn: 'edge' }],
      multirates: [{ name: '原画', rate: 0, bit: 3000 }],
      rtmp_url: 'https://example.invalid', rtmp_live: 'test.flv'
    };
    response.text = JSON.stringify({ error: 0, data });
    return response;
  }
};
const site = new DouyuSite();
const detail = new LiveRoomDetail();
detail.roomId = '100';
const qualities = await site.getPlayQualities(detail);
assert.equal(qualities.length, 1);
await assert.rejects(site.getPlayUrls(detail, qualities[0]), /直播流暂不可用/,
  'a room marked live with streamStatus=0 must not thrash 404 CDN lines');
streamStatus = 1;
const playable = await site.getPlayUrls(detail, qualities[0]);
assert.equal(playable.urls.length, 1, 'playable stream still produces a URL');
console.log('Douyu streamStatus: explicit unavailable state and playable URL passed');
