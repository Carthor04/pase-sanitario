// Genera los íconos PNG de la PWA (public/icon-192.png, icon-512.png, apple-touch-icon.png)
// sin dependencias: dibuja el hexágono de Tellus con polígonos y codifica el PNG con zlib.
// Uso: node scripts/make-icons.mjs
import { writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { deflateSync } from 'node:zlib';
import { root } from './db-connection.mjs';

const ACCENT = [0x1d, 0x4e, 0x89];
const WHITE = [0xff, 0xff, 0xff];

// Hexágono de Tellus en su viewBox de 636×766 (igual que BrandMark.tsx y icon.svg).
const MARK = [
  [
    [1, 191],
    [319, 0],
    [636, 191],
    [636, 340],
    [382, 190],
    [382, 571],
    [510, 486],
    [510, 302],
    [636, 376],
    [636, 564],
    [319, 766],
    [254, 726],
    [254, 190],
    [1, 340],
  ],
  [
    [1, 376],
    [127, 302],
    [127, 486],
    [224, 547],
    [224, 705],
    [0, 564],
  ],
];
// Colocado al centro del lienzo de 512×512, con 300 px de alto.
const SCALE = 300 / 766;
const OFFSET_X = (512 - 636 * SCALE) / 2;
const OFFSET_Y = (512 - 766 * SCALE) / 2;

function insidePolygon(x, y, poly) {
  let inside = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const [xi, yi] = poly[i];
    const [xj, yj] = poly[j];
    if (yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}

function insideMark(x, y) {
  const mx = (x - OFFSET_X) / SCALE;
  const my = (y - OFFSET_Y) / SCALE;
  return MARK.some((poly) => insidePolygon(mx, my, poly));
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
            if (insideMark(x, y)) fg++;
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
