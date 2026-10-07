/**
 * Minimal zlib/DEFLATE decoder (RFC 1950/1951), adapted from tiny-inflate.
 * Only used for Bilibili danmaku frames, which are small.
 */

class Tree {
  table: Uint16Array = new Uint16Array(16);
  trans: Uint16Array = new Uint16Array(288);
}

class InflateState {
  source: Uint8Array;
  sourceIndex: number = 0;
  tag: number = 0;
  bitcount: number = 0;
  dest: number[] = [];
  ltree: Tree = new Tree();
  dtree: Tree = new Tree();

  constructor(source: Uint8Array, start: number) {
    this.source = source;
    this.sourceIndex = start;
  }
}

const sltree = new Tree();
const sdtree = new Tree();
const lengthBits = new Uint8Array(30);
const lengthBase = new Uint16Array(30);
const distBits = new Uint8Array(30);
const distBase = new Uint16Array(30);
const clcidx = new Uint8Array([16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]);
const codeTree = new Tree();
const lengths = new Uint8Array(288 + 32);
const offs = new Uint16Array(16);

function buildBitsBase(bits: Uint8Array, base: Uint16Array, delta: number, first: number): void {
  for (let i = 0; i < delta; ++i) {
    bits[i] = 0;
  }
  for (let i = 0; i < 30 - delta; ++i) {
    bits[i + delta] = Math.floor(i / delta);
  }
  let sum = first;
  for (let i = 0; i < 30; ++i) {
    base[i] = sum;
    sum += 1 << bits[i];
  }
}

function buildFixedTrees(lt: Tree, dt: Tree): void {
  for (let i = 0; i < 7; ++i) {
    lt.table[i] = 0;
  }
  lt.table[7] = 24;
  lt.table[8] = 152;
  lt.table[9] = 112;
  for (let i = 0; i < 24; ++i) {
    lt.trans[i] = 256 + i;
  }
  for (let i = 0; i < 144; ++i) {
    lt.trans[24 + i] = i;
  }
  for (let i = 0; i < 8; ++i) {
    lt.trans[24 + 144 + i] = 280 + i;
  }
  for (let i = 0; i < 112; ++i) {
    lt.trans[24 + 144 + 8 + i] = 144 + i;
  }
  for (let i = 0; i < 5; ++i) {
    dt.table[i] = 0;
  }
  dt.table[5] = 32;
  for (let i = 0; i < 32; ++i) {
    dt.trans[i] = i;
  }
}

function buildTree(t: Tree, lens: Uint8Array, off: number, num: number): void {
  for (let i = 0; i < 16; ++i) {
    t.table[i] = 0;
  }
  for (let i = 0; i < num; ++i) {
    t.table[lens[off + i]]++;
  }
  t.table[0] = 0;
  let sum = 0;
  for (let i = 0; i < 16; ++i) {
    offs[i] = sum;
    sum += t.table[i];
  }
  for (let i = 0; i < num; ++i) {
    if (lens[off + i] !== 0) {
      t.trans[offs[lens[off + i]]++] = i;
    }
  }
}

/** Danmaku frames are small; a corrupt stream must not grow the output without bound. */
const MAX_OUTPUT: number = 1 << 20;

function getBit(d: InflateState): number {
  if (d.bitcount-- === 0) {
    if (d.sourceIndex >= d.source.length) {
      throw new Error('inflate: unexpected end of input');
    }
    d.tag = d.source[d.sourceIndex++];
    d.bitcount = 7;
  }
  const bit = d.tag & 1;
  d.tag >>>= 1;
  return bit;
}

function readBits(d: InflateState, num: number, base: number): number {
  if (num === 0) {
    return base;
  }
  while (d.bitcount < 24) {
    d.tag |= (d.sourceIndex < d.source.length ? d.source[d.sourceIndex] : 0) << d.bitcount;
    d.sourceIndex++;
    d.bitcount += 8;
  }
  const val = d.tag & (0xffff >>> (16 - num));
  d.tag >>>= num;
  d.bitcount -= num;
  return val + base;
}

function decodeSymbol(d: InflateState, t: Tree): number {
  while (d.bitcount < 24) {
    d.tag |= (d.sourceIndex < d.source.length ? d.source[d.sourceIndex] : 0) << d.bitcount;
    d.sourceIndex++;
    d.bitcount += 8;
  }
  let sum = 0;
  let cur = 0;
  let len = 0;
  let tag = d.tag;
  do {
    cur = 2 * cur + (tag & 1);
    tag >>>= 1;
    ++len;
    sum += t.table[len];
    cur -= t.table[len];
  } while (cur >= 0);
  d.tag = tag;
  d.bitcount -= len;
  return t.trans[sum + cur];
}

function decodeTrees(d: InflateState, lt: Tree, dt: Tree): void {
  const hlit = readBits(d, 5, 257);
  const hdist = readBits(d, 5, 1);
  const hclen = readBits(d, 4, 4);
  for (let i = 0; i < 19; ++i) {
    lengths[i] = 0;
  }
  for (let i = 0; i < hclen; ++i) {
    lengths[clcidx[i]] = readBits(d, 3, 0);
  }
  buildTree(codeTree, lengths, 0, 19);
  let num = 0;
  while (num < hlit + hdist) {
    const sym = decodeSymbol(d, codeTree);
    if (sym === 16) {
      const prev = lengths[num - 1];
      for (let length = readBits(d, 2, 3); length > 0; --length) {
        lengths[num++] = prev;
      }
    } else if (sym === 17) {
      for (let length = readBits(d, 3, 3); length > 0; --length) {
        lengths[num++] = 0;
      }
    } else if (sym === 18) {
      for (let length = readBits(d, 7, 11); length > 0; --length) {
        lengths[num++] = 0;
      }
    } else {
      lengths[num++] = sym;
    }
  }
  buildTree(lt, lengths, 0, hlit);
  buildTree(dt, lengths, hlit, hdist);
}

function inflateBlockData(d: InflateState, lt: Tree, dt: Tree): void {
  while (true) {
    if (d.dest.length > MAX_OUTPUT) {
      throw new Error('inflate: output too large');
    }
    let sym = decodeSymbol(d, lt);
    if (sym === 256) {
      return;
    }
    if (sym < 256) {
      d.dest.push(sym);
    } else {
      sym -= 257;
      const length = readBits(d, lengthBits[sym], lengthBase[sym]);
      const dist = decodeSymbol(d, dt);
      const offset = d.dest.length - readBits(d, distBits[dist], distBase[dist]);
      for (let i = offset; i < offset + length; ++i) {
        d.dest.push(d.dest[i]);
      }
    }
  }
}

function inflateUncompressedBlock(d: InflateState): void {
  while (d.bitcount > 8) {
    d.sourceIndex--;
    d.bitcount -= 8;
  }
  const length = d.source[d.sourceIndex + 1] * 256 + d.source[d.sourceIndex];
  d.sourceIndex += 4;
  for (let i = length; i > 0; --i) {
    d.dest.push(d.source[d.sourceIndex++]);
  }
  d.bitcount = 0;
}

buildFixedTrees(sltree, sdtree);
buildBitsBase(lengthBits, lengthBase, 4, 3);
buildBitsBase(distBits, distBase, 2, 1);
lengthBits[28] = 0;
lengthBase[28] = 258;

export class Inflate {
  /** Inflates a zlib stream (2-byte header) or raw deflate when `raw` is true. */
  static zlib(data: Uint8Array, raw: boolean = false): Uint8Array {
    const d = new InflateState(data, raw ? 0 : 2);
    let bfinal = 0;
    do {
      bfinal = getBit(d);
      const btype = readBits(d, 2, 0);
      if (btype === 0) {
        inflateUncompressedBlock(d);
      } else if (btype === 1) {
        inflateBlockData(d, sltree, sdtree);
      } else if (btype === 2) {
        decodeTrees(d, d.ltree, d.dtree);
        inflateBlockData(d, d.ltree, d.dtree);
      } else {
        throw new Error('inflate: invalid block type');
      }
    } while (bfinal === 0);
    return new Uint8Array(d.dest);
  }
}
