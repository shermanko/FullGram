#!/usr/bin/env node
/**
 * Generates:
 * 1) 50 custom animated APNG avatar frames in assets/frames/fg_*.png
 *    (strictly transparent center so they NEVER overlap the avatar face or nickname)
 * 2) 12 custom FullGram alternate app icons based on FullGramDefault & FullGramMascot
 *    in Telegram/Telegram-iOS/<Name>.alticon/ + Resources/FullGramIcon_<Name>.png
 */

import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");

// ============================================================
// Minimal PNG / APNG Decoder & Encoder (pure Node + zlib)
// ============================================================

const CRC_TABLE = new Uint32Array(256);
for (let n = 0; n < 256; n++) {
  let c = n;
  for (let k = 0; k < 8; k++) {
    c = (c & 1) ? (0xedb88320 ^ (c >>> 1)) : (c >>> 1);
  }
  CRC_TABLE[n] = c >>> 0;
}

function crc32(buf) {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) {
    c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  }
  return (c ^ 0xffffffff) >>> 0;
}

function makeChunk(type, data) {
  const typeBuf = Buffer.from(type, "ascii");
  const lenBuf = Buffer.alloc(4);
  lenBuf.writeUInt32BE(data.length, 0);
  const crcInput = Buffer.concat([typeBuf, data]);
  const crcBuf = Buffer.alloc(4);
  crcBuf.writeUInt32BE(crc32(crcInput), 0);
  return Buffer.concat([lenBuf, typeBuf, data, crcBuf]);
}

const PNG_SIG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

function encodeRawRGBA(width, height, rgba) {
  const bpp = 4;
  const stride = width * bpp;
  const raw = Buffer.alloc((stride + 1) * height);
  const candidates = [
    new Uint8Array(stride), // 0: None
    new Uint8Array(stride), // 1: Sub
    new Uint8Array(stride), // 2: Up
    new Uint8Array(stride), // 4: Paeth
  ];

  for (let y = 0; y < height; y++) {
    const rowOff = y * stride;
    const prevOff = (y - 1) * stride;
    let sad0 = 0, sad1 = 0, sad2 = 0, sad4 = 0;

    for (let x = 0; x < stride; x++) {
      const cur = rgba[rowOff + x];
      const left = x >= bpp ? rgba[rowOff + x - bpp] : 0;
      const up = y > 0 ? rgba[prevOff + x] : 0;
      const upLeft = (x >= bpp && y > 0) ? rgba[prevOff + x - bpp] : 0;

      const f0 = cur;
      const f1 = (cur - left) & 0xff;
      const f2 = (cur - up) & 0xff;
      const f4 = (cur - paeth(left, up, upLeft)) & 0xff;

      candidates[0][x] = f0;
      candidates[1][x] = f1;
      candidates[2][x] = f2;
      candidates[3][x] = f4;

      sad0 += f0 < 128 ? f0 : 256 - f0;
      sad1 += f1 < 128 ? f1 : 256 - f1;
      sad2 += f2 < 128 ? f2 : 256 - f2;
      sad4 += f4 < 128 ? f4 : 256 - f4;
    }

    let bestType = 0;
    let bestBuf = candidates[0];
    let bestSad = sad0;
    if (sad1 < bestSad) { bestSad = sad1; bestType = 1; bestBuf = candidates[1]; }
    if (sad2 < bestSad) { bestSad = sad2; bestType = 2; bestBuf = candidates[2]; }
    if (sad4 < bestSad) { bestSad = sad4; bestType = 4; bestBuf = candidates[3]; }

    const outRow = y * (stride + 1);
    raw[outRow] = bestType;
    raw.set(bestBuf, outRow + 1);
  }
  return zlib.deflateSync(raw, { level: 9 });
}

function encodeRawIndexed(width, height, indices) {
  const raw = Buffer.alloc((width + 1) * height);
  const candidates = [
    new Uint8Array(width), // 0: None
    new Uint8Array(width), // 1: Sub
    new Uint8Array(width), // 2: Up
    new Uint8Array(width), // 4: Paeth
  ];

  for (let y = 0; y < height; y++) {
    const rowOff = y * width;
    const prevOff = (y - 1) * width;
    let sad0 = 0, sad1 = 0, sad2 = 0, sad4 = 0;

    for (let x = 0; x < width; x++) {
      const cur = indices[rowOff + x];
      const left = x >= 1 ? indices[rowOff + x - 1] : 0;
      const up = y > 0 ? indices[prevOff + x] : 0;
      const upLeft = (x >= 1 && y > 0) ? indices[prevOff + x - 1] : 0;

      const f0 = cur;
      const f1 = (cur - left) & 0xff;
      const f2 = (cur - up) & 0xff;
      const f4 = (cur - paeth(left, up, upLeft)) & 0xff;

      candidates[0][x] = f0;
      candidates[1][x] = f1;
      candidates[2][x] = f2;
      candidates[3][x] = f4;

      sad0 += f0 < 128 ? f0 : 256 - f0;
      sad1 += f1 < 128 ? f1 : 256 - f1;
      sad2 += f2 < 128 ? f2 : 256 - f2;
      sad4 += f4 < 128 ? f4 : 256 - f4;
    }

    let bestType = 0;
    let bestBuf = candidates[0];
    let bestSad = sad0;
    if (sad1 < bestSad) { bestSad = sad1; bestType = 1; bestBuf = candidates[1]; }
    if (sad2 < bestSad) { bestSad = sad2; bestType = 2; bestBuf = candidates[2]; }
    if (sad4 < bestSad) { bestSad = sad4; bestType = 4; bestBuf = candidates[3]; }

    const outRow = y * (width + 1);
    raw[outRow] = bestType;
    raw.set(bestBuf, outRow + 1);
  }
  return zlib.deflateSync(raw, { level: 9 });
}

function quantizeFramesToPalette(framesRGBA) {
  const buckets = new Map();
  for (const rgba of framesRGBA) {
    for (let i = 0; i < rgba.length; i += 4) {
      const a = rgba[i + 3];
      if (a < 4) continue;
      const r = rgba[i];
      const g = rgba[i + 1];
      const b = rgba[i + 2];
      const key = ((r >> 3) << 15) | ((g >> 3) << 10) | ((b >> 3) << 5) | (a >> 3);
      let bkt = buckets.get(key);
      if (!bkt) {
        bkt = { count: 0, sr: 0, sg: 0, sb: 0, sa: 0 };
        buckets.set(key, bkt);
      }
      bkt.count++;
      bkt.sr += r;
      bkt.sg += g;
      bkt.sb += b;
      bkt.sa += a;
    }
  }

  const sorted = Array.from(buckets.values()).sort((x, y) => y.count - x.count).slice(0, 255);
  const palette = [[0, 0, 0, 0]];
  for (const bkt of sorted) {
    palette.push([
      Math.round(bkt.sr / bkt.count),
      Math.round(bkt.sg / bkt.count),
      Math.round(bkt.sb / bkt.count),
      Math.round(bkt.sa / bkt.count),
    ]);
  }

  const lookupCache = new Map();
  const findNearest = (r, g, b, a) => {
    const key = ((r >> 3) << 15) | ((g >> 3) << 10) | ((b >> 3) << 5) | (a >> 3);
    const cached = lookupCache.get(key);
    if (cached !== undefined) return cached;
    let bestIdx = 1;
    let bestDist = Infinity;
    for (let j = 1; j < palette.length; j++) {
      const p = palette[j];
      const dr = r - p[0];
      const dg = g - p[1];
      const db = b - p[2];
      const da = a - p[3];
      const d = dr * dr + dg * dg + db * db + da * da * 2;
      if (d < bestDist) {
        bestDist = d;
        bestIdx = j;
        if (d === 0) break;
      }
    }
    lookupCache.set(key, bestIdx);
    return bestIdx;
  };

  const indexedFrames = framesRGBA.map((rgba) => {
    const pxCount = rgba.length >> 2;
    const out = new Uint8Array(pxCount);
    for (let i = 0; i < pxCount; i++) {
      const off = i << 2;
      const a = rgba[off + 3];
      if (a < 4) {
        out[i] = 0;
      } else {
        out[i] = findNearest(rgba[off], rgba[off + 1], rgba[off + 2], a);
      }
    }
    return out;
  });

  return { palette, indexedFrames };
}

function encodePNG(width, height, rgba) {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 6; // RGBA
  ihdr[10] = 0;
  ihdr[11] = 0;
  ihdr[12] = 0;

  const compressed = encodeRawRGBA(width, height, Buffer.from(rgba.buffer, rgba.byteOffset, rgba.byteLength));
  return Buffer.concat([
    PNG_SIG,
    makeChunk("IHDR", ihdr),
    makeChunk("IDAT", compressed),
    makeChunk("IEND", Buffer.alloc(0)),
  ]);
}

function encodeAPNG(width, height, framesRGBA, delayNum = 75, delayDen = 1000) {
  const { palette, indexedFrames } = quantizeFramesToPalette(framesRGBA);

  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 3; // Indexed-color (PLTE + tRNS)
  ihdr[10] = 0;
  ihdr[11] = 0;
  ihdr[12] = 0;

  const plte = Buffer.alloc(palette.length * 3);
  const trns = Buffer.alloc(palette.length);
  for (let i = 0; i < palette.length; i++) {
    plte[i * 3] = palette[i][0];
    plte[i * 3 + 1] = palette[i][1];
    plte[i * 3 + 2] = palette[i][2];
    trns[i] = palette[i][3];
  }

  const actl = Buffer.alloc(8);
  actl.writeUInt32BE(indexedFrames.length, 0);
  actl.writeUInt32BE(0, 4); // infinite loop

  const parts = [
    PNG_SIG,
    makeChunk("IHDR", ihdr),
    makeChunk("PLTE", plte),
    makeChunk("tRNS", trns),
    makeChunk("acTL", actl),
  ];
  let seq = 0;

  for (let i = 0; i < indexedFrames.length; i++) {
    const fctl = Buffer.alloc(26);
    fctl.writeUInt32BE(seq++, 0);
    fctl.writeUInt32BE(width, 4);
    fctl.writeUInt32BE(height, 8);
    fctl.writeUInt32BE(0, 12);
    fctl.writeUInt32BE(0, 16);
    fctl.writeUInt16BE(delayNum, 20);
    fctl.writeUInt16BE(delayDen, 22);
    fctl[24] = 1; // APNG_DISPOSE_OP_BACKGROUND
    fctl[25] = 0; // APNG_BLEND_OP_SOURCE
    parts.push(makeChunk("fcTL", fctl));

    const compressed = encodeRawIndexed(width, height, indexedFrames[i]);
    if (i === 0) {
      parts.push(makeChunk("IDAT", compressed));
    } else {
      const seqBuf = Buffer.alloc(4);
      seqBuf.writeUInt32BE(seq++, 0);
      parts.push(makeChunk("fdAT", Buffer.concat([seqBuf, compressed])));
    }
  }

  parts.push(makeChunk("IEND", Buffer.alloc(0)));
  return Buffer.concat(parts);
}

function paeth(a, b, c) {
  const p = a + b - c;
  const pa = Math.abs(p - a);
  const pb = Math.abs(p - b);
  const pc = Math.abs(p - c);
  if (pa <= pb && pa <= pc) return a;
  if (pb <= pc) return b;
  return c;
}

function decodePNG(filePath) {
  const buf = fs.readFileSync(filePath);
  let offset = 8;
  let width = 0, height = 0, colorType = 6, bitDepth = 8;
  const idatChunks = [];
  let palette = null;

  while (offset < buf.length) {
    const len = buf.readUInt32BE(offset);
    const type = buf.toString("ascii", offset + 4, offset + 8);
    const data = buf.subarray(offset + 8, offset + 8 + len);
    if (type === "IHDR") {
      width = data.readUInt32BE(0);
      height = data.readUInt32BE(4);
      bitDepth = data[8];
      colorType = data[9];
    } else if (type === "PLTE") {
      palette = data;
    } else if (type === "IDAT") {
      idatChunks.push(data);
    } else if (type === "IEND") {
      break;
    }
    offset += 12 + len;
  }

  const raw = zlib.inflateSync(Buffer.concat(idatChunks));
  const bpp = colorType === 6 ? 4 : colorType === 2 ? 3 : colorType === 4 ? 2 : 1;
  const stride = width * bpp;
  const unfilt = new Uint8Array(height * stride);

  let inPos = 0;
  for (let y = 0; y < height; y++) {
    const filter = raw[inPos++];
    const rowOut = y * stride;
    const prevRow = (y - 1) * stride;
    for (let x = 0; x < stride; x++) {
      const val = raw[inPos++];
      const a = x >= bpp ? unfilt[rowOut + x - bpp] : 0;
      const b = y > 0 ? unfilt[prevRow + x] : 0;
      const c = (x >= bpp && y > 0) ? unfilt[prevRow + x - bpp] : 0;
      let res = val;
      if (filter === 1) res = (val + a) & 0xff;
      else if (filter === 2) res = (val + b) & 0xff;
      else if (filter === 3) res = (val + ((a + b) >> 1)) & 0xff;
      else if (filter === 4) res = (val + paeth(a, b, c)) & 0xff;
      unfilt[rowOut + x] = res;
    }
  }

  const rgba = new Uint8Array(width * height * 4);
  for (let i = 0; i < width * height; i++) {
    if (colorType === 6) {
      rgba[i * 4] = unfilt[i * 4];
      rgba[i * 4 + 1] = unfilt[i * 4 + 1];
      rgba[i * 4 + 2] = unfilt[i * 4 + 2];
      rgba[i * 4 + 3] = unfilt[i * 4 + 3];
    } else if (colorType === 2) {
      rgba[i * 4] = unfilt[i * 3];
      rgba[i * 4 + 1] = unfilt[i * 3 + 1];
      rgba[i * 4 + 2] = unfilt[i * 3 + 2];
      rgba[i * 4 + 3] = 255;
    } else if (colorType === 3 && palette) {
      const idx = unfilt[i] * 3;
      rgba[i * 4] = palette[idx];
      rgba[i * 4 + 1] = palette[idx + 1];
      rgba[i * 4 + 2] = palette[idx + 2];
      rgba[i * 4 + 3] = 255;
    } else {
      const v = unfilt[i * bpp];
      rgba[i * 4] = v;
      rgba[i * 4 + 1] = v;
      rgba[i * 4 + 2] = v;
      rgba[i * 4 + 3] = bpp === 2 ? unfilt[i * bpp + 1] : 255;
    }
  }
  return { width, height, rgba };
}

function resizeRGBA(src, dstW, dstH) {
  const dst = new Uint8Array(dstW * dstH * 4);
  const scaleX = src.width / dstW;
  const scaleY = src.height / dstH;
  for (let y = 0; y < dstH; y++) {
    const sy = (y + 0.5) * scaleY - 0.5;
    const y0 = Math.max(0, Math.min(src.height - 1, Math.floor(sy)));
    const y1 = Math.max(0, Math.min(src.height - 1, y0 + 1));
    const fy = Math.max(0, Math.min(1, sy - y0));
    for (let x = 0; x < dstW; x++) {
      const sx = (x + 0.5) * scaleX - 0.5;
      const x0 = Math.max(0, Math.min(src.width - 1, Math.floor(sx)));
      const x1 = Math.max(0, Math.min(src.width - 1, x0 + 1));
      const fx = Math.max(0, Math.min(1, sx - x0));
      const i00 = (y0 * src.width + x0) * 4;
      const i10 = (y0 * src.width + x1) * 4;
      const i01 = (y1 * src.width + x0) * 4;
      const i11 = (y1 * src.width + x1) * 4;
      const o = (y * dstW + x) * 4;
      for (let c = 0; c < 4; c++) {
        const top = src.rgba[i00 + c] * (1 - fx) + src.rgba[i10 + c] * fx;
        const bot = src.rgba[i01 + c] * (1 - fx) + src.rgba[i11 + c] * fx;
        dst[o + c] = Math.round(top * (1 - fy) + bot * fy);
      }
    }
  }
  return { width: dstW, height: dstH, rgba: dst };
}

// ============================================================
// Color Helpers
// ============================================================

function hexToRGB(hex) {
  return [(hex >> 16) & 255, (hex >> 8) & 255, hex & 255];
}

function lerp(a, b, t) {
  return a + (b - a) * t;
}

function clamp(v, lo, hi) {
  return v < lo ? lo : v > hi ? hi : v;
}

function smoothstep(edge0, edge1, x) {
  const t = clamp((x - edge0) / (edge1 - edge0), 0, 1);
  return t * t * (3 - 2 * t);
}

function hsvToRgb(h, s, v) {
  h = ((h % 1) + 1) % 1;
  const i = Math.floor(h * 6);
  const f = h * 6 - i;
  const p = v * (1 - s);
  const q = v * (1 - f * s);
  const t = v * (1 - (1 - f) * s);
  let r, g, b;
  switch (i % 6) {
    case 0: r = v; g = t; b = p; break;
    case 1: r = q; g = v; b = p; break;
    case 2: r = p; g = v; b = t; break;
    case 3: r = p; g = q; b = v; break;
    case 4: r = t; g = p; b = v; break;
    default: r = v; g = p; b = q; break;
  }
  return [r * 255, g * 255, b * 255];
}

function blendPixel(buf, idx, r, g, b, a) {
  if (a <= 0.002) return;
  const sa = clamp(a, 0, 1);
  const da = buf[idx + 3] / 255;
  const outA = sa + da * (1 - sa);
  if (outA <= 0.0001) return;
  buf[idx] = clamp(Math.round((r * sa + buf[idx] * da * (1 - sa)) / outA), 0, 255);
  buf[idx + 1] = clamp(Math.round((g * sa + buf[idx + 1] * da * (1 - sa)) / outA), 0, 255);
  buf[idx + 2] = clamp(Math.round((b * sa + buf[idx + 2] * da * (1 - sa)) / outA), 0, 255);
  buf[idx + 3] = clamp(Math.round(outA * 255), 0, 255);
}

// ============================================================
// 50 Custom FullGram Animated Avatar Frames
// ============================================================

const CUSTOM_FRAMES = [
  // FullGram Signature (10)
  { id: "fg_chrome_wings", title: "FG Chrome Wings", category: "FullGram", accent: 0xE2E8F0, c1: 0xF8FAFC, c2: 0x94A3B8, c3: 0x38BDF8, style: "wings" },
  { id: "fg_crimson_wings", title: "FG Crimson Wings", category: "FullGram", accent: 0xFF2E4C, c1: 0xFF1744, c2: 0xFF6B6B, c3: 0x7F0019, style: "wings" },
  { id: "fg_solar_flare", title: "FG Solar Orange", category: "FullGram", accent: 0xFF8C00, c1: 0xFF5500, c2: 0xFFB300, c3: 0xFFF176, style: "corona" },
  { id: "fg_mascot_sparkle", title: "FG Mascot Sparkle", category: "FullGram", accent: 0xF472B6, c1: 0xFF85B3, c2: 0xFFD166, c3: 0xFFFFFF, style: "sparkles" },
  { id: "fg_obsidian_blade", title: "FG Obsidian Edge", category: "FullGram", accent: 0x94A3B8, c1: 0x1E293B, c2: 0xE2E8F0, c3: 0x64748B, style: "blades" },
  { id: "fg_neon_core", title: "FG Neon Core", category: "FullGram", accent: 0x00F5D4, c1: 0x00F5D4, c2: 0xFF2A85, c3: 0x7C4DFF, style: "dual_arc" },
  { id: "fg_stealth_hud", title: "FG Stealth HUD", category: "FullGram", accent: 0x00E5FF, c1: 0x00E5FF, c2: 0x0EA5E9, c3: 0xE0F2FE, style: "hud" },
  { id: "fg_royal_crown", title: "FG Royal Gold", category: "FullGram", accent: 0xFFD700, c1: 0xFFD700, c2: 0xFFA000, c3: 0xFFF8DC, style: "crown" },
  { id: "fg_void_prism", title: "FG Void Prism", category: "FullGram", accent: 0xA855F7, c1: 0x7C3AED, c2: 0x06B6D4, c3: 0xF0ABFC, style: "prism" },
  { id: "fg_arctic_chrome", title: "FG Arctic Chrome", category: "FullGram", accent: 0x67E8F9, c1: 0xE0F2FE, c2: 0x38BDF8, c3: 0x0284C7, style: "crystal" },

  // Кибер & Неон (10)
  { id: "fg_cyber_hex", title: "Cyber Hex Grid", category: "Кибер", accent: 0x00E5FF, c1: 0x00E5FF, c2: 0x6366F1, c3: 0x22D3EE, style: "hex" },
  { id: "fg_synthwave_ring", title: "Synthwave Sunset", category: "Неон", accent: 0xFF2A85, c1: 0xFF2A85, c2: 0xFF9E00, c3: 0x7B2CBF, style: "wave" },
  { id: "fg_matrix_code", title: "Matrix Digital", category: "Кибер", accent: 0x00FF66, c1: 0x00FF66, c2: 0x059669, c3: 0xA7F3D0, style: "ticks" },
  { id: "fg_laser_scan", title: "Laser Scanner", category: "Кибер", accent: 0xFF0055, c1: 0xFF0055, c2: 0xFF77AA, c3: 0xFFFFFF, style: "radar" },
  { id: "fg_plasma_arc", title: "Plasma Arc", category: "Неон", accent: 0xC084FC, c1: 0x9333EA, c2: 0x38BDF8, c3: 0xF5D0FE, style: "lightning" },
  { id: "fg_holo_ring", title: "Hologram Prism", category: "Неон", accent: 0x38BDF8, c1: 0x00F5D4, c2: 0xFF2A85, c3: 0xFFD60A, style: "rainbow" },
  { id: "fg_glitch_pulse", title: "Glitch Pulse", category: "Кибер", accent: 0xFF2A85, c1: 0x00FFFF, c2: 0xFF0055, c3: 0xFFFFFF, style: "glitch" },
  { id: "fg_turbo_rpm", title: "Turbo RPM", category: "Кибер", accent: 0xF97316, c1: 0xEF4444, c2: 0xF59E0B, c3: 0x22C55E, style: "hud" },
  { id: "fg_circuit_flow", title: "Circuit Flow", category: "Кибер", accent: 0x10B981, c1: 0x10B981, c2: 0x06B6D4, c3: 0x6EE7B7, style: "hex" },
  { id: "fg_vapor_wave", title: "Vaporwave 1984", category: "Неон", accent: 0xF472B6, c1: 0xFF71CE, c2: 0x01CDFE, c3: 0xB967FF, style: "dual_arc" },

  // Стихия & Магия (10)
  { id: "fg_inferno_ring", title: "Inferno Flame", category: "Стихия", accent: 0xFF4500, c1: 0xFF2400, c2: 0xFF8C00, c3: 0xFFE066, style: "corona" },
  { id: "fg_frost_crystal", title: "Frost Crystals", category: "Стихия", accent: 0x60A5FA, c1: 0xBAE6FD, c2: 0x38BDF8, c3: 0x1D4ED8, style: "crystal" },
  { id: "fg_thunder_bolt", title: "Thunder Storm", category: "Стихия", accent: 0xFACC15, c1: 0xFACC15, c2: 0x38BDF8, c3: 0xFFFFFF, style: "lightning" },
  { id: "fg_toxic_venom", title: "Toxic Venom", category: "Стихия", accent: 0x84CC16, c1: 0xA3E635, c2: 0x16A34A, c3: 0xECFCCB, style: "wave" },
  { id: "fg_blood_moon", title: "Blood Moon", category: "Стихия", accent: 0xDC2626, c1: 0x991B1B, c2: 0xEF4444, c3: 0xFCA5A5, style: "eclipse" },
  { id: "fg_emerald_aura", title: "Emerald Aura", category: "Стихия", accent: 0x34D399, c1: 0x059669, c2: 0x34D399, c3: 0xD1FAE5, style: "corona" },
  { id: "fg_ocean_tide", title: "Ocean Tide", category: "Стихия", accent: 0x0EA5E9, c1: 0x0284C7, c2: 0x22D3EE, c3: 0xBAE6FD, style: "wave" },
  { id: "fg_magma_crack", title: "Magma Core", category: "Стихия", accent: 0xEA580C, c1: 0x7C2D12, c2: 0xF97316, c3: 0xFDE047, style: "blades" },
  { id: "fg_wind_vortex", title: "Wind Vortex", category: "Стихия", accent: 0xA5F3FC, c1: 0xCBD5E1, c2: 0x67E8F9, c3: 0xFFFFFF, style: "spiral" },
  { id: "fg_arcane_runes", title: "Arcane Runes", category: "Стихия", accent: 0x8B5CF6, c1: 0x7C3AED, c2: 0xF472B6, c3: 0xDDD6FE, style: "ticks" },

  // Космос (8)
  { id: "fg_nebula_swirl", title: "Nebula Swirl", category: "Космос", accent: 0x818CF8, c1: 0x6366F1, c2: 0xEC4899, c3: 0x38BDF8, style: "spiral" },
  { id: "fg_supernova", title: "Supernova Burst", category: "Космос", accent: 0xFBBF24, c1: 0xF59E0B, c2: 0xEF4444, c3: 0xFEF3C7, style: "starburst" },
  { id: "fg_saturn_orbit", title: "Orbital Moons", category: "Космос", accent: 0x38BDF8, c1: 0x38BDF8, c2: 0xA78BFA, c3: 0xFFFFFF, style: "orbits" },
  { id: "fg_starlight_halo", title: "Starlight Halo", category: "Космос", accent: 0xE0E7FF, c1: 0x818CF8, c2: 0xE0E7FF, c3: 0xFFFFFF, style: "sparkles" },
  { id: "fg_aurora_borealis", title: "Aurora Borealis", category: "Космос", accent: 0x2DD4BF, c1: 0x2DD4BF, c2: 0x818CF8, c3: 0x34D399, style: "wave" },
  { id: "fg_black_hole", title: "Event Horizon", category: "Космос", accent: 0xF97316, c1: 0x1E1B4B, c2: 0xF97316, c3: 0xFDE68A, style: "eclipse" },
  { id: "fg_comet_trail", title: "Comet Trail", category: "Космос", accent: 0x67E8F9, c1: 0x06B6D4, c2: 0xE0F2FE, c3: 0xFFFFFF, style: "radar" },
  { id: "fg_zodiac_gold", title: "Celestial Astrolabe", category: "Космос", accent: 0xF59E0B, c1: 0xD97706, c2: 0xFCD34D, c3: 0xFEF9C3, style: "prism" },

  // Милые, Аниме & Природа (12)
  { id: "fg_sakura_petals", title: "Sakura Petals", category: "Аниме", accent: 0xFF85B3, c1: 0xF472B6, c2: 0xFBCFE8, c3: 0xFFFFFF, style: "petals" },
  { id: "fg_neko_neon", title: "Neko Neon Ears", category: "Милые", accent: 0xF472B6, c1: 0xFF2A85, c2: 0xF9A8D4, c3: 0x00F5D4, style: "cat_ears" },
  { id: "fg_pastel_hearts", title: "Pastel Hearts", category: "Милые", accent: 0xFB7185, c1: 0xFB7185, c2: 0xFBCFE8, c3: 0xFDE047, style: "orbits" },
  { id: "fg_angel_halo", title: "Angelic Halo", category: "Милые", accent: 0xFDE68A, c1: 0xFEF08A, c2: 0xFFFFFF, c3: 0x93C5FD, style: "halo" },
  { id: "fg_devil_horns", title: "Crimson Horns", category: "Аниме", accent: 0xEF4444, c1: 0xDC2626, c2: 0x991B1B, c3: 0xF97316, style: "horns" },
  { id: "fg_butterfly_glow", title: "Neon Butterflies", category: "Природа", accent: 0xC084FC, c1: 0xA855F7, c2: 0x38BDF8, c3: 0xF5D0FE, style: "petals" },
  { id: "fg_lotus_bloom", title: "Lotus Bloom", category: "Природа", accent: 0xEC4899, c1: 0xEC4899, c2: 0x34D399, c3: 0xFCE7F3, style: "starburst" },
  { id: "fg_rainbow_prism", title: "Rainbow Prism", category: "Неон", accent: 0xFF6B9D, c1: 0xFF0055, c2: 0x00F5D4, c3: 0xFFD60A, style: "rainbow" },
  { id: "fg_candy_swirl", title: "Candy Swirl", category: "Милые", accent: 0xF472B6, c1: 0xF472B6, c2: 0x67E8F9, c3: 0xFDE047, style: "spiral" },
  { id: "fg_emerald_vine", title: "Emerald Vine", category: "Природа", accent: 0x22C55E, c1: 0x16A34A, c2: 0x86EFAC, c3: 0xFDE047, style: "petals" },
  { id: "fg_fireflies", title: "Night Fireflies", category: "Природа", accent: 0xFACC15, c1: 0x0F766E, c2: 0xFDE047, c3: 0xFEF9C3, style: "sparkles" },
  { id: "fg_diamond_lux", title: "Diamond Luxury", category: "FullGram", accent: 0xE0F2FE, c1: 0xE0F2FE, c2: 0x93C5FD, c3: 0xFFFFFF, style: "crown" },
];

function renderFrameAPNG(spec) {
  const S = 224;
  const cx = S / 2;
  const cy = S / 2;
  const numFrames = 12;
  const rgb1 = hexToRGB(spec.c1);
  const rgb2 = hexToRGB(spec.c2);
  const rgb3 = hexToRGB(spec.c3);

  // Strict ring bounds for 224x224 canvas: inner clear circle >= 86px so center of avatar
  // stays 100% unobstructed, outer edge <= 110px with sculpted bevels & crisp visibility.
  const R_INNER = 87.5;
  const R_MID = 98.5;
  const R_OUTER = 110.2;

  const frames = [];

  for (let f = 0; f < numFrames; f++) {
    const t = f / numFrames; // 0..1
    const phase = t * Math.PI * 2;
    const buf = new Uint8Array(S * S * 4);

    for (let y = 0; y < S; y++) {
      const dy = y - cy;
      for (let x = 0; x < S; x++) {
        const dx = x - cx;
        const r = Math.hypot(dx, dy);
        if (r < R_INNER - 4 || r > R_OUTER + 3) continue;

        const ang = Math.atan2(dy, dx); // -PI..PI
        const idx = (y * S + x) * 4;

        // Hard inner safety fade: never touch avatar face
        const innerMask = smoothstep(R_INNER - 2.0, R_INNER + 1.5, r);
        const outerMask = 1.0 - smoothstep(R_OUTER - 1.5, R_OUTER + 2.5, r);
        // Sculpted metallic inner & outer micro-bevels give every frame 3D depth
        const innerBevel = Math.exp(-Math.pow((r - (R_INNER + 3.0)) / 1.8, 2));
        const outerBevel = Math.exp(-Math.pow((r - (R_OUTER - 3.0)) / 1.9, 2));

        let alpha = 0;
        let mixT = 0.5 + 0.5 * Math.sin(ang * 2 + phase);
        let hi = 0;

        switch (spec.style) {
          case "wings": {
            const sideCos = Math.abs(Math.cos(ang));
            const feather = Math.pow(sideCos, 1.45) * (0.65 + 0.35 * Math.cos(ang * 14 - phase));
            const band = Math.exp(-Math.pow((r - (R_INNER + 7.5)) / 4.8, 2)) * 0.85;
            const wingArc = Math.exp(-Math.pow((r - (R_MID + 7.2 * feather)) / 3.4, 2)) * Math.pow(sideCos, 1.1);
            const tipSpark = Math.pow(sideCos, 6) * Math.exp(-Math.pow((r - (R_OUTER - 4.0)) / 2.5, 2));
            alpha = Math.min(1, band + wingArc * 0.95 + innerBevel * 0.6);
            mixT = clamp(0.25 + 0.5 * Math.sin(ang * 2 - phase) + 0.25 * feather, 0, 1);
            hi = Math.min(1, innerBevel * 0.5 + tipSpark * 0.95);
            break;
          }
          case "dual_arc": {
            const a1 = Math.sin(ang * 2 + phase);
            const a2 = Math.sin(ang * 2 - phase + 1.57);
            const r1 = Math.exp(-Math.pow((r - (R_MID - 3.2)) / 3.2, 2)) * smoothstep(-0.45, 0.55, a1);
            const r2 = Math.exp(-Math.pow((r - (R_MID + 4.0)) / 3.2, 2)) * smoothstep(-0.45, 0.55, a2);
            const base = Math.exp(-Math.pow((r - R_MID) / 5.5, 2)) * 0.38;
            alpha = Math.min(1, base + innerBevel * 0.55 + r1 + r2);
            mixT = r2 / (r1 + r2 + 0.001);
            hi = Math.max(r1, r2) * 0.45 + innerBevel * 0.3;
            break;
          }
          case "corona": {
            const flame = 4.5 * Math.sin(ang * 10 + phase * 2) + 2.8 * Math.cos(ang * 17 - phase * 3);
            const plume = Math.exp(-Math.pow((r - (R_MID + flame * 0.65)) / 5.0, 2));
            const core = Math.exp(-Math.pow((r - (R_INNER + 4.2)) / 2.8, 2)) * 0.95;
            alpha = Math.min(1, core + plume * (0.78 + 0.22 * Math.sin(ang * 6 + phase)));
            mixT = clamp((r - R_INNER) / (R_OUTER - R_INNER), 0, 1);
            hi = core * 0.8 + Math.max(0, Math.sin(ang * 10 + phase * 2)) * 0.35;
            break;
          }
          case "sparkles": {
            const base = Math.exp(-Math.pow((r - R_MID) / 4.2, 2)) * 0.72 + innerBevel * 0.45;
            let starGlow = 0;
            for (let k = 0; k < 6; k++) {
              const sa = (k * Math.PI) / 3 + phase * (k % 2 === 0 ? 0.5 : -0.5);
              const sr = R_MID + (k % 2 === 0 ? 4.0 : -3.2);
              const d = Math.hypot(dx - Math.cos(sa) * sr, dy - Math.sin(sa) * sr);
              const twinkle = 0.6 + 0.4 * Math.sin(phase * 2 + k * 1.3);
              const starCross = Math.exp(-Math.pow(d / 4.8, 2)) * twinkle;
              starGlow = Math.max(starGlow, starCross);
            }
            alpha = Math.min(1, base + starGlow);
            mixT = 0.5 + 0.5 * Math.sin(ang * 3 + phase);
            hi = Math.min(1, starGlow * 1.15 + innerBevel * 0.35);
            break;
          }
          case "blades": {
            const period = Math.PI / 3;
            const seg = ((ang + phase * 0.5) % period + period) % period;
            const blade = smoothstep(0.03, 0.22, seg) * (1 - smoothstep(0.68, 0.95, seg));
            const edge = Math.exp(-Math.pow((r - (R_MID + 2.8 * (blade - 0.3))) / 4.2, 2));
            const core = innerBevel * 0.9;
            alpha = Math.min(1, core + edge * (0.45 + 0.55 * blade));
            mixT = blade;
            hi = (Math.pow(Math.max(0, Math.sin(ang * 6 - phase)), 6) * 0.8 + innerBevel * 0.45);
            break;
          }
          case "hud": {
            const tick = Math.sin(ang * 24 + phase) > 0.15 ? 1.0 : 0.25;
            const ring1 = Math.exp(-Math.pow((r - (R_INNER + 4.0)) / 2.2, 2)) * 0.98;
            const ring2 = Math.exp(-Math.pow((r - (R_OUTER - 4.0)) / 2.4, 2)) * tick * 0.92;
            const segArc = Math.exp(-Math.pow((r - R_MID) / 3.8, 2)) * smoothstep(0.05, 0.75, Math.sin(ang * 3 - phase));
            const crosshair = (Math.exp(-Math.pow(Math.abs(Math.sin(ang * 2)) * 28, 2)) * 0.85) * smoothstep(R_INNER + 2, R_OUTER - 2, r);
            alpha = Math.min(1, ring1 + ring2 + segArc * 0.9 + crosshair);
            mixT = ring2 > ring1 ? 0.8 : 0.2;
            hi = segArc * 0.65 + crosshair * 0.7;
            break;
          }
          case "crown": {
            const base = Math.exp(-Math.pow((r - (R_INNER + 6.5)) / 4.2, 2)) * 0.94;
            const spikes = Math.pow(Math.max(0, Math.cos((ang + Math.PI / 2) * 5)), 1.7);
            const tipY = R_MID + 8.5 * spikes;
            const crest = Math.exp(-Math.pow((r - tipY) / 3.2, 2)) * smoothstep(0.1, 0.7, spikes);
            // Shimmering royal ruby/diamond studs at every crown peak
            let gem = 0;
            for (let k = 0; k < 5; k++) {
              const ga = -Math.PI / 2 + (k * Math.PI * 2) / 5;
              const gx = Math.cos(ga) * (R_MID + 6.0);
              const gy = Math.sin(ga) * (R_MID + 6.0);
              const d = Math.hypot(dx - gx, dy - gy);
              gem = Math.max(gem, Math.exp(-Math.pow(d / 3.6, 2)) * (0.75 + 0.25 * Math.sin(phase + k)));
            }
            alpha = Math.min(1, base + crest * 0.95 + gem);
            mixT = clamp(0.4 + 0.4 * Math.sin(ang * 5 + phase) + 0.2 * crest, 0, 1);
            hi = gem + innerBevel * 0.55;
            break;
          }
          case "prism": {
            const facet = Math.abs(Math.sin(ang * 6 + phase));
            const rTarget = R_MID + 4.0 * (facet - 0.5);
            const band = Math.exp(-Math.pow((r - rTarget) / 4.8, 2));
            alpha = Math.min(1, band * (0.72 + 0.28 * facet) + innerBevel * 0.55);
            mixT = facet;
            hi = Math.pow(facet, 5) * 0.78 + innerBevel * 0.3;
            break;
          }
          case "crystal": {
            const spike = Math.pow(Math.abs(Math.cos(ang * 8 + phase * 0.5)), 1.9);
            const rTarget = R_MID - 2.0 + 8.0 * spike;
            const band = Math.exp(-Math.pow((r - rTarget) / 3.8, 2));
            alpha = Math.min(1, band * 0.94 + innerBevel * 0.85);
            mixT = spike;
            hi = Math.pow(spike, 3.5) * 0.88 + innerBevel * 0.4;
            break;
          }
          case "hex": {
            const seg = Math.sin(ang * 12 + phase) * Math.cos(ang * 6 - phase);
            const r1 = Math.exp(-Math.pow((r - (R_MID - 2.8)) / 2.8, 2));
            const r2 = Math.exp(-Math.pow((r - (R_MID + 4.4)) / 3.0, 2)) * smoothstep(-0.15, 0.45, seg);
            alpha = Math.min(1, r1 * 0.88 + r2 * 0.98 + innerBevel * 0.4);
            mixT = 0.5 + 0.5 * seg;
            hi = Math.max(0, seg) * 0.65;
            break;
          }
          case "wave": {
            const w = Math.sin(ang * 5 + phase * 2) * 4.5;
            const d1 = Math.exp(-Math.pow((r - (R_MID + w)) / 4.2, 2));
            const d2 = Math.exp(-Math.pow((r - (R_MID - w)) / 3.6, 2)) * 0.82;
            alpha = Math.min(1, d1 + d2 + innerBevel * 0.45);
            mixT = d1 / (d1 + d2 + 0.001);
            hi = Math.min(d1, d2) * 0.9;
            break;
          }
          case "ticks": {
            const dash = Math.sin(ang * 18 + phase * 2);
            const ring = Math.exp(-Math.pow((r - R_MID) / 4.6, 2)) * smoothstep(-0.25, 0.35, dash);
            alpha = Math.min(1, ring * 0.96 + innerBevel * 0.82);
            mixT = 0.5 + 0.5 * Math.sin(ang * 3 - phase);
            hi = Math.pow(Math.max(0, dash), 3.5) * 0.68;
            break;
          }
          case "radar": {
            const rel = ((ang - phase) % (Math.PI * 2) + Math.PI * 2) % (Math.PI * 2);
            const trail = Math.exp(-rel * 1.25);
            const band = Math.exp(-Math.pow((r - R_MID) / 4.8, 2));
            alpha = Math.min(1, band * 0.34 + innerBevel * 0.45 + band * trail * 0.96);
            mixT = trail;
            hi = Math.pow(trail, 4) * 0.98;
            break;
          }
          case "lightning": {
            const bolt = Math.sin(ang * 13 + phase * 3) * Math.sin(ang * 7 - phase * 2);
            const d = r - (R_MID + bolt * 5.6);
            const core = Math.exp(-Math.pow(d / 2.4, 2));
            const glow = Math.exp(-Math.pow(d / 6.8, 2)) * 0.62;
            alpha = Math.min(1, core + glow + innerBevel * 0.38);
            mixT = 0.5 + 0.5 * bolt;
            hi = core * 0.9;
            break;
          }
          case "rainbow": {
            const band = Math.exp(-Math.pow((r - R_MID) / 5.4, 2));
            const hue = (ang / (Math.PI * 2) + t + 1) % 1;
            const [rr, gg, bb] = hsvToRgb(hue, 0.88, 1.0);
            const spec = innerBevel * 0.5 + outerBevel * 0.4;
            const a = Math.min(1, band * 0.95 + spec * 0.45) * innerMask * outerMask;
            blendPixel(buf, idx, lerp(rr, 255, spec * 0.35), lerp(gg, 255, spec * 0.35), lerp(bb, 255, spec * 0.35), a);
            continue;
          }
          case "glitch": {
            const slice = Math.sin(y * 0.22 + phase * 2) > 0.5 ? 3.2 : 0;
            const band = Math.exp(-Math.pow((r - (R_MID + slice)) / 4.2, 2));
            const a = Math.min(1, band + innerBevel * 0.5) * innerMask * outerMask;
            const split = Math.sin(ang * 8 + phase * 3);
            const rr = split > 0 ? rgb2[0] : rgb1[0];
            const gg = split > 0 ? rgb2[1] : rgb1[1];
            const bb = split > 0 ? rgb2[2] : rgb1[2];
            blendPixel(buf, idx, rr, gg, bb, a);
            continue;
          }
          case "eclipse": {
            const glow = Math.exp(-Math.pow((r - R_MID) / 5.2, 2));
            const flare = 0.48 + 0.52 * Math.pow(0.5 + 0.5 * Math.cos(ang - phase), 1.8);
            alpha = Math.min(1, glow * flare + innerBevel * 0.55);
            mixT = flare;
            hi = Math.pow(0.5 + 0.5 * Math.cos(ang - phase), 6) * 0.95;
            break;
          }
          case "spiral": {
            const sp = Math.sin(ang * 4 + (r - R_INNER) * 0.32 - phase * 2);
            const band = Math.exp(-Math.pow((r - R_MID) / 5.4, 2));
            alpha = Math.min(1, band * (0.5 + 0.5 * smoothstep(-0.3, 0.7, sp)) + innerBevel * 0.4);
            mixT = 0.5 + 0.5 * sp;
            hi = Math.pow(Math.max(0, sp), 4.5) * 0.72;
            break;
          }
          case "starburst": {
            const rays = Math.pow(Math.abs(Math.sin(ang * 7 + phase)), 2.5);
            const band = Math.exp(-Math.pow((r - (R_MID + rays * 5.8 - 1.8)) / 3.8, 2));
            alpha = Math.min(1, band * (0.7 + 0.3 * rays) + innerBevel * 0.45);
            mixT = rays;
            hi = Math.pow(rays, 2.5) * 0.85;
            break;
          }
          case "orbits": {
            const ring = Math.exp(-Math.pow((r - R_MID) / 2.8, 2)) * 0.78 + innerBevel * 0.4;
            let orb = 0;
            for (let k = 0; k < 4; k++) {
              const oa = phase + (k * Math.PI) / 2;
              const ox = Math.cos(oa) * (R_MID + 2.0);
              const oy = Math.sin(oa) * (R_MID + 2.0);
              const dist = Math.hypot(dx - ox, dy - oy);
              orb = Math.max(orb, Math.exp(-Math.pow(dist / 6.2, 2)));
            }
            alpha = Math.min(1, ring + orb);
            mixT = orb;
            hi = Math.pow(orb, 2) * 0.92;
            break;
          }
          case "petals": {
            const pet = Math.pow(Math.abs(Math.sin(ang * 5 + phase * 0.5)), 1.35);
            const rTarget = R_MID - 2.0 + pet * 6.5;
            const band = Math.exp(-Math.pow((r - rTarget) / 4.2, 2));
            alpha = Math.min(1, band * (0.68 + 0.32 * pet) + innerBevel * 0.5);
            mixT = pet;
            hi = Math.pow(pet, 4) * 0.65;
            break;
          }
          case "cat_ears": {
            const base = Math.exp(-Math.pow((r - (R_INNER + 7.5)) / 4.4, 2)) * 0.92;
            const earL = Math.exp(-Math.pow((ang + 2.24) / 0.21, 2)) * smoothstep(R_INNER + 1, R_OUTER - 1, r);
            const earR = Math.exp(-Math.pow((ang + 0.90) / 0.21, 2)) * smoothstep(R_INNER + 1, R_OUTER - 1, r);
            const innerTriL = Math.exp(-Math.pow((ang + 2.24) / 0.09, 2)) * Math.exp(-Math.pow((r - (R_OUTER - 8)) / 6.0, 2));
            const innerTriR = Math.exp(-Math.pow((ang + 0.90) / 0.09, 2)) * Math.exp(-Math.pow((r - (R_OUTER - 8)) / 6.0, 2));
            const ears = Math.max(earL, earR) * (0.88 + 0.12 * Math.sin(phase));
            alpha = Math.min(1, base + ears);
            mixT = ears > 0.3 ? 0.85 : (0.5 + 0.5 * Math.sin(ang * 2 + phase));
            hi = Math.max(innerTriL, innerTriR) * 0.9 + ears * 0.35;
            break;
          }
          case "halo": {
            const base = Math.exp(-Math.pow((r - R_MID) / 4.2, 2)) * (0.76 + 0.24 * Math.sin(ang * 2 - phase));
            const topGlow = Math.exp(-Math.pow((ang + Math.PI / 2) / 0.82, 2)) *
              Math.exp(-Math.pow((r - (R_MID + 3.8)) / 4.5, 2));
            alpha = Math.min(1, base + innerBevel * 0.55 + topGlow * 0.95);
            mixT = topGlow;
            hi = Math.min(1, topGlow * 0.95 + innerBevel * 0.4);
            break;
          }
          case "horns": {
            const base = Math.exp(-Math.pow((r - (R_INNER + 7.5)) / 4.4, 2)) * 0.9;
            const hornTilt = (r - R_INNER) * 0.008;
            const leftHorn = Math.exp(-Math.pow((ang + 2.18 - hornTilt) / 0.17, 2)) * smoothstep(R_INNER, R_OUTER, r);
            const rightHorn = Math.exp(-Math.pow((ang + 0.96 + hornTilt) / 0.17, 2)) * smoothstep(R_INNER, R_OUTER, r);
            const horns = Math.max(leftHorn, rightHorn) * (0.88 + 0.12 * Math.cos(phase));
            alpha = Math.min(1, base + horns);
            mixT = 0.5 + 0.5 * Math.sin(ang * 3 + phase);
            hi = horns * 0.72 + innerBevel * 0.3;
            break;
          }
          default: {
            alpha = Math.min(1, Math.exp(-Math.pow((r - R_MID) / 4.6, 2)) + innerBevel * 0.5);
          }
        }

        const finalAlpha = clamp(alpha * 1.15, 0, 1) * innerMask * outerMask;
        if (finalAlpha <= 0.008) continue;

        let cr = lerp(rgb1[0], rgb2[0], mixT);
        let cg = lerp(rgb1[1], rgb2[1], mixT);
        let cb = lerp(rgb1[2], rgb2[2], mixT);
        if (hi > 0) {
          cr = lerp(cr, rgb3[0], clamp(hi, 0, 1));
          cg = lerp(cg, rgb3[1], clamp(hi, 0, 1));
          cb = lerp(cb, rgb3[2], clamp(hi, 0, 1));
        }
        // Subtle outer contrast rim so bright frames remain legible on light themes
        const edgeShade = outerBevel * 0.24;
        if (edgeShade > 0.01) {
          cr *= (1 - edgeShade);
          cg *= (1 - edgeShade);
          cb *= (1 - edgeShade);
        }
        blendPixel(buf, idx, cr, cg, cb, finalAlpha);
      }
    }
    frames.push(buf);
  }

  return encodeAPNG(S, S, frames, 75, 1000);
}

// ============================================================
// 12 Custom FullGram App Icons (based on FullGramDefault & Mascot)
// ============================================================

const ALTICON_SIZES = [
  { suffix: "@2x.png", size: 120 },
  { suffix: "@3x.png", size: 180 },
  { suffix: "Ipad.png", size: 76 },
  { suffix: "Ipad@2x.png", size: 152 },
  { suffix: "LargeIpad@2x.png", size: 167 },
  { suffix: "Notification.png", size: 20 },
  { suffix: "Notification@2x.png", size: 40 },
  { suffix: "Notification@3x.png", size: 60 },
];

const CUSTOM_APP_ICONS = [
  { name: "FullGramCyan", title: "Cyan Neon", base: "default", gradA: 0x00F5D4, gradB: 0x0088FF, bgTint: 0x001A26 },
  { name: "FullGramPurple", title: "Violet Plasma", base: "default", gradA: 0xC084FC, gradB: 0x7C3AED, bgTint: 0x160728 },
  { name: "FullGramGold", title: "Royal Gold", base: "default", gradA: 0xFFF3B0, gradB: 0xD97706, bgTint: 0x1F1400 },
  { name: "FullGramEmerald", title: "Toxic Matrix", base: "default", gradA: 0x4ADE80, gradB: 0x059669, bgTint: 0x001F12 },
  { name: "FullGramSakura", title: "Sakura Pink", base: "default", gradA: 0xFBCFE8, gradB: 0xEC4899, bgTint: 0x240718 },
  { name: "FullGramArctic", title: "Arctic Ice", base: "default", gradA: 0xE0F2FE, gradB: 0x38BDF8, bgTint: 0x051828 },
  { name: "FullGramVapor", title: "Vaporwave", base: "default", gradA: 0xFF2A85, gradB: 0x00F5D4, bgTint: 0x190826 },
  { name: "FullGramMidnight", title: "Stealth Carbon", base: "default", gradA: 0x94A3B8, gradB: 0x334155, bgTint: 0x080A0F },
  { name: "FullGramSunset", title: "Sunset Glow", base: "default", gradA: 0xFF6B6B, gradB: 0xFBBF24, bgTint: 0x240B08 },
  { name: "FullGramHolo", title: "Holographic", base: "default", gradA: 0x00F5D4, gradB: 0xFF2A85, bgTint: 0x120B24, holo: true },
  { name: "FullGramMascotNeon", title: "Mascot Cyber", base: "mascot", gradA: 0x00E5FF, gradB: 0xFF2A85, bgTint: 0x0D1025 },
  { name: "FullGramMascotGold", title: "Mascot Royal", base: "mascot", gradA: 0xFFD700, gradB: 0xFF7A00, bgTint: 0x1E1308 },
];

function buildStyledDefaultIcon(baseImg, spec) {
  const { width, height, rgba } = baseImg;
  const out = new Uint8Array(width * height * 4);
  const cA = hexToRGB(spec.gradA);
  const cB = hexToRGB(spec.gradB);
  const bg = hexToRGB(spec.bgTint);

  for (let y = 0; y < height; y++) {
    const ny = y / (height - 1);
    for (let x = 0; x < width; x++) {
      const nx = x / (width - 1);
      const i = (y * width + x) * 4;
      const r = rgba[i] / 255;
      const g = rgba[i + 1] / 255;
      const b = rgba[i + 2] / 255;
      const lum = 0.299 * r + 0.587 * g + 0.114 * b;

      let tr, tg, tb;
      if (spec.holo) {
        const hue = (nx * 0.55 + ny * 0.45 + 0.55) % 1;
        [tr, tg, tb] = hsvToRgb(hue, 0.78, 1.0);
      } else {
        const gt = clamp(nx * 0.35 + ny * 0.65, 0, 1);
        tr = lerp(cA[0], cB[0], gt);
        tg = lerp(cA[1], cB[1], gt);
        tb = lerp(cA[2], cB[2], gt);
      }

      // Preserve crisp metallic highlights while tinting midtones & bottom glow
      const glow = Math.pow(lum, 0.85);
      const specHi = Math.pow(clamp((lum - 0.72) / 0.28, 0, 1), 1.6);
      const outR = lerp(bg[0] * (0.4 + 0.6 * ny), tr, glow) + specHi * 75;
      const outG = lerp(bg[1] * (0.4 + 0.6 * ny), tg, glow) + specHi * 75;
      const outB = lerp(bg[2] * (0.4 + 0.6 * ny), tb, glow) + specHi * 75;

      out[i] = clamp(Math.round(outR), 0, 255);
      out[i + 1] = clamp(Math.round(outG), 0, 255);
      out[i + 2] = clamp(Math.round(outB), 0, 255);
      out[i + 3] = 255;
    }
  }
  return { width, height, rgba: out };
}

function buildStyledMascotIcon(baseImg, spec) {
  const { width, height, rgba } = baseImg;
  const out = new Uint8Array(width * height * 4);
  const cA = hexToRGB(spec.gradA);
  const cB = hexToRGB(spec.gradB);
  const bg = hexToRGB(spec.bgTint);
  const cx = width / 2;
  const cy = height / 2;

  for (let y = 0; y < height; y++) {
    const ny = y / (height - 1);
    for (let x = 0; x < width; x++) {
      const nx = x / (width - 1);
      const i = (y * width + x) * 4;
      const d = Math.hypot((x - cx) / cx, (y - cy) / cy);
      const halo = Math.exp(-Math.pow(d * 1.15, 2));
      const gt = clamp(nx * 0.5 + ny * 0.5, 0, 1);
      const bgR = lerp(bg[0], lerp(cA[0], cB[0], gt), halo * 0.55);
      const bgG = lerp(bg[1], lerp(cA[1], cB[1], gt), halo * 0.55);
      const bgB = lerp(bg[2], lerp(cA[2], cB[2], gt), halo * 0.55);

      const sa = rgba[i + 3] / 255;
      out[i] = clamp(Math.round(rgba[i] * sa + bgR * (1 - sa)), 0, 255);
      out[i + 1] = clamp(Math.round(rgba[i + 1] * sa + bgG * (1 - sa)), 0, 255);
      out[i + 2] = clamp(Math.round(rgba[i + 2] * sa + bgB * (1 - sa)), 0, 255);
      out[i + 3] = 255;
    }
  }
  return { width, height, rgba: out };
}

// ============================================================
// Main
// ============================================================

const t0 = Date.now();

// 1. Generate 50 custom animated APNG frames
const framesDir = path.join(ROOT, "assets", "frames");
fs.mkdirSync(framesDir, { recursive: true });
let totalFrameBytes = 0;
for (const spec of CUSTOM_FRAMES) {
  const apng = renderFrameAPNG(spec);
  const outPath = path.join(framesDir, `${spec.id}.png`);
  fs.writeFileSync(outPath, apng);
  totalFrameBytes += apng.length;
}
console.log(
  `Generated ${CUSTOM_FRAMES.length} custom animated APNG frames in assets/frames/ (${(totalFrameBytes / 1024 / 1024).toFixed(2)} MB total)`
);

if (process.argv.includes("--frames-only")) {
  console.log("Frames-only mode: skipped app icon generation.");
  process.exit(0);
}

// 2. Generate 12 custom app icons
const defaultSrc = decodePNG(path.join(ROOT, "Telegram", "Telegram-iOS", "FullGramDefault.alticon", "FullGramDefault@3x.png"));
const mascotSrc = decodePNG(path.join(ROOT, "Telegram", "Telegram-iOS", "FullGramMascot.alticon", "FullGramMascot@3x.png"));
const resourcesDir = path.join(ROOT, "Telegram", "Telegram-iOS", "Resources");

for (const spec of CUSTOM_APP_ICONS) {
  const master = spec.base === "mascot"
    ? buildStyledMascotIcon(mascotSrc, spec)
    : buildStyledDefaultIcon(defaultSrc, spec);

  const altDir = path.join(ROOT, "Telegram", "Telegram-iOS", `${spec.name}.alticon`);
  fs.mkdirSync(altDir, { recursive: true });

  for (const sz of ALTICON_SIZES) {
    const img = sz.size === master.width ? master : resizeRGBA(master, sz.size, sz.size);
    const png = encodePNG(img.width, img.height, img.rgba);
    fs.writeFileSync(path.join(altDir, `${spec.name}${sz.suffix}`), png);
  }

  const preview = resizeRGBA(master, 120, 120);
  fs.writeFileSync(
    path.join(resourcesDir, `FullGramIcon_${spec.name}.png`),
    encodePNG(preview.width, preview.height, preview.rgba)
  );
}

console.log(
  `Generated ${CUSTOM_APP_ICONS.length} custom FullGram app icons (.alticon + Resources preview PNGs) in ${((Date.now() - t0) / 1000).toFixed(2)}s`
);
