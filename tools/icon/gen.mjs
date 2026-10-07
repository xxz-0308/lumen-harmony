// Generates Lumen layered icon PNGs (1024x1024) with no dependencies.
import zlib from 'node:zlib';
import fs from 'node:fs';
import path from 'node:path';

const S = 1024;
function crc32(buf) {
  let c, crc = 0xffffffff;
  for (let n = 0; n < buf.length; n++) {
    c = (crc ^ buf[n]) & 0xff;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    crc = (crc >>> 8) ^ c;
  }
  return (crc ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type), data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td));
  return Buffer.concat([len, td, crc]);
}
function png(w, h, rgba) {
  const raw = Buffer.alloc((w * 4 + 1) * h);
  for (let y = 0; y < h; y++) {
    raw[y * (w * 4 + 1)] = 0;
    rgba.copy(raw, y * (w * 4 + 1) + 1, y * w * 4, (y + 1) * w * 4);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; ihdr[9] = 6; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw, { level: 9 })), chunk('IEND', Buffer.alloc(0)),
  ]);
}
const clamp = (v) => Math.max(0, Math.min(1, v));
const mix = (a, b, t) => a + (b - a) * t;
const smooth = (e0, e1, x) => { const t = clamp((x - e0) / (e1 - e0)); return t * t * (3 - 2 * t); };

function render(size, fn) {
  const buf = Buffer.alloc(size * size * 4);
  for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
    const [r, g, b, a] = fn(x / size, y / size);
    const i = (y * size + x) * 4;
    buf[i] = Math.round(clamp(r) * 255); buf[i + 1] = Math.round(clamp(g) * 255);
    buf[i + 2] = Math.round(clamp(b) * 255); buf[i + 3] = Math.round(clamp(a) * 255);
  }
  return png(size, size, buf);
}

// Background: near-black with a warm ember glow rising from the lower center.
const background = (u, v) => {
  const base = [0x0b / 255, 0x0b / 255, 0x10 / 255];
  const d = Math.hypot(u - 0.5, v - 0.62);
  const glow = Math.exp(-d * d * 7.5);
  const violet = Math.exp(-((u - 0.2) ** 2 + (v - 0.15) ** 2) * 6) * 0.22;
  return [
    base[0] + glow * 0.42 + violet * 0.35,
    base[1] + glow * 0.16 + violet * 0.12,
    base[2] + glow * 0.12 + violet * 0.55,
    1,
  ];
};

// Foreground: glowing live dot with a soft halo ring (within the safe zone).
const foreground = (u, v) => {
  const d = Math.hypot(u - 0.5, v - 0.5);
  const coreR = 0.105;
  const core = 1 - smooth(coreR - 0.004, coreR + 0.004, d);
  const t = clamp(d / coreR);
  const coreCol = [1, mix(0.93, 0.56, t), mix(0.8, 0.38, t)];
  const halo = Math.exp(-((d - coreR) ** 2) / 0.0035) * 0.55 * (d > coreR ? 1 : 0);
  const ringR = 0.225;
  const ring = Math.exp(-((d - ringR) ** 2) / 0.00006) * 0.55 + Math.exp(-((d - ringR) ** 2) / 0.0012) * 0.18;
  const glowA = clamp(halo + ring);
  const glowCol = [1, 0.55, 0.36];
  const a = clamp(core + glowA * (1 - core));
  if (a <= 0) return [0, 0, 0, 0];
  const w = core / a;
  return [mix(glowCol[0], coreCol[0], w), mix(glowCol[1], coreCol[1], w), mix(glowCol[2], coreCol[2], w), a];
};

const startIcon = (u, v) => {
  const f = foreground(u, v);
  return f;
};

const out = (p) => path.resolve(process.argv[2] ?? '.', p);
fs.writeFileSync(out('background.png'), render(S, background));
fs.writeFileSync(out('foreground.png'), render(S, foreground));
fs.writeFileSync(out('startIcon.png'), render(288, startIcon));
console.log('icons written');
