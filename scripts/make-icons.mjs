// Genera los íconos PNG de la PWA (public/icon-192.png, icon-512.png, apple-touch-icon.png)
// sin dependencias: dibuja la "P" con figuras y codifica el PNG con zlib.
// Uso: node scripts/make-icons.mjs
import { writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { deflateSync } from 'node:zlib';
import { root } from './db-connection.mjs';

const ACCENT = [0x1d, 0x4e, 0x89];
const WHITE = [0xff, 0xff, 0xff];

// Geometría en un lienzo de 512×512.
function insideP(x, y) {
  const stem = x >= 168 && x <= 240 && y >= 112 && y <= 400;
  const cx = 292;
  const cy = 210;
  const outer =
    (x >= 168 && x <= cx && y >= 112 && y <= 308) ||
    (x >= cx && (x - cx) ** 2 + (y - cy) ** 2 <= 98 ** 2);
  const inner =
    (x >= 240 && x <= cx && y >= 164 && y <= 256) ||
    (x >= cx && (x - cx) ** 2 + (y - cy) ** 2 <= 46 ** 2);
  return stem || (outer && !inner);
}

function insideRounded(x, y, r) {
  if (r === 0) return true;
  const cx = Math.min(Math.max(x, r), 512 - r);
  const cy = Math.min(Math.max(y, r), 512 - r);
  return (x - cx) ** 2 + (y - cy) ** 2 <= r * r;
}

function render(size, radius) {
  const ss = 4; // supermuestreo para bordes suaves
  const px = Buffer.alloc(size * size * 4);
  for (let j = 0; j < size; j++) {
    for (let i = 0; i < size; i++) {
      let bg = 0;
      let fg = 0;
      for (let a = 0; a < ss; a++) {
        for (let b = 0; b < ss; b++) {
          const x = ((i + (a + 0.5) / ss) / size) * 512;
          const y = ((j + (b + 0.5) / ss) / size) * 512;
          if (insideRounded(x, y, radius)) {
            bg++;
            if (insideP(x, y)) fg++;
          }
        }
      }
      const n = ss * ss;
      const o = (j * size + i) * 4;
      const t = bg ? fg / bg : 0;
      for (let c = 0; c < 3; c++) px[o + c] = Math.round(ACCENT[c] * (1 - t) + WHITE[c] * t);
      px[o + 3] = Math.round((bg / n) * 255);
    }
  }
  return png(size, px);
}

function crc32(buf) {
  let c = ~0;
  for (const byte of buf) {
    c ^= byte;
    for (let k = 0; k < 8; k++) c = (c >>> 1) ^ (0xedb88320 & -(c & 1));
  }
  return ~c >>> 0;
}

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body));
  return Buffer.concat([len, body, crc]);
}

function png(size, rgba) {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(size, 0);
  ihdr.writeUInt32BE(size, 4);
  ihdr[8] = 8; // bits
  ihdr[9] = 6; // RGBA
  const raw = Buffer.alloc(size * (size * 4 + 1));
  for (let y = 0; y < size; y++)
    rgba.copy(raw, y * (size * 4 + 1) + 1, y * size * 4, (y + 1) * size * 4);
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(raw)),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

// 192 con esquinas redondeadas; 512 y Apple a sangre completa (el sistema recorta).
const out = [
  ['icon-192.png', 192, 112],
  ['icon-512.png', 512, 0],
  ['apple-touch-icon.png', 180, 0],
];
for (const [name, size, radius] of out) {
  writeFileSync(join(root, 'public', name), render(size, radius));
  console.log(`public/${name}`);
}
