/**
 * 国旗绘制 —— 移植自 kids-games/games/memory/flags.js。
 *
 * 原实现每面旗是一段内联 SVG 字符串; 这里改成「用 Canvas 画」的图元描述,
 * 页面按卡片大小自动缩放, 于是模型层不依赖任何绘制框架。
 *
 * 为什么不用 emoji 国旗: 很多字体不含国旗字形, 会退化成 "CN" 两个字母。
 */

/** 一种图元: 矩形 / 圆 / 五角星 */
class Shape {
  kind: string = 'rect'; // 'rect' | 'circle' | 'star'
  x: number = 0;
  y: number = 0;
  w: number = 20;
  h: number = 20;
  cx: number = 0;
  cy: number = 0;
  r: number = 0;
  color: string = '#fff';
  /** 五角星的旋转角 (度) */
  deg: number = 0;
}

export class FlagSpec {
  code: string = '';
  /** 原始 viewBox 宽高 (通常 30×20, 瑞士方旗 20×20) */
  vw: number = 30;
  vh: number = 20;
  shapes: Shape[] = [];

  constructor(code: string, vw: number, vh: number) {
    this.code = code;
    this.vw = vw;
    this.vh = vh;
  }

  rect(x: number, y: number, w: number, h: number, color: string): FlagSpec {
    const s: Shape = new Shape();
    s.kind = 'rect';
    s.x = x;
    s.y = y;
    s.w = w;
    s.h = h;
    s.color = color;
    this.shapes.push(s);
    return this;
  }

  circle(cx: number, cy: number, r: number, color: string): FlagSpec {
    const s: Shape = new Shape();
    s.kind = 'circle';
    s.cx = cx;
    s.cy = cy;
    s.r = r;
    s.color = color;
    this.shapes.push(s);
    return this;
  }

  /** 五角星: cx/cy 为中心, r 为外接半径, deg 为旋转角 */
  star(cx: number, cy: number, r: number, deg: number, color: string): FlagSpec {
    const s: Shape = new Shape();
    s.kind = 'star';
    s.cx = cx;
    s.cy = cy;
    s.r = r;
    s.deg = deg;
    s.color = color;
    this.shapes.push(s);
    return this;
  }

  /** 小星: 让一只星尖指向大星中心 (5,5), 与原 smallStar 同算法 */
  starToward(cx: number, cy: number, toX: number, toY: number): FlagSpec {
    const deg: number = (Math.atan2(toY - cy, toX - cx) * 180) / Math.PI + 90;
    return this.star(cx, cy, 1, deg, '#ffde00');
  }

  /** 竖条 (等宽) */
  vstripes(cols: string[]): FlagSpec {
    const w: number = 30 / cols.length;
    for (let i: number = 0; i < cols.length; i++) {
      this.rect(i * w, 0, w, 20, cols[i]);
    }
    return this;
  }

  /** 横条 (等高) */
  hstripes(cols: string[]): FlagSpec {
    const h: number = 20 / cols.length;
    for (let i: number = 0; i < cols.length; i++) {
      this.rect(0, i * h, 30, h, cols[i]);
    }
    return this;
  }
}

/** 中国国旗: 红底 1 大 4 小黄星 */
function cnFlag(): FlagSpec {
  const f: FlagSpec = new FlagSpec('CN', 30, 20);
  f.rect(0, 0, 30, 20, '#de2910');
  f.star(5, 5, 3, 0, '#ffde00');
  f.starToward(10, 2, 5, 5);
  f.starToward(12, 4, 5, 5);
  f.starToward(12, 7, 5, 5);
  f.starToward(10, 9, 5, 5);
  return f;
}

function jpFlag(): FlagSpec {
  const f: FlagSpec = new FlagSpec('JP', 30, 20);
  f.rect(0, 0, 30, 20, '#fff');
  f.circle(15, 10, 6, '#bc002d');
  return f;
}

function seFlag(): FlagSpec {
  // 瑞典: 蓝底偏左黄十字
  const f: FlagSpec = new FlagSpec('SE', 30, 20);
  f.rect(0, 0, 30, 20, '#006AA7');
  f.rect(9, 0, 3, 20, '#FECC00');
  f.rect(0, 8.5, 30, 3, '#FECC00');
  return f;
}

function chFlag(): FlagSpec {
  // 瑞士: 红底白十字, 方旗 20×20
  const f: FlagSpec = new FlagSpec('CH', 20, 20);
  f.rect(0, 0, 20, 20, '#D52B1E');
  f.rect(8, 3.5, 4, 13, '#fff');
  f.rect(3.5, 8, 13, 4, '#fff');
  return f;
}

function buildFlags(): Map<string, FlagSpec> {
  const m: Map<string, FlagSpec> = new Map<string, FlagSpec>();
  m.set('CN', cnFlag());
  m.set('JP', jpFlag());
  m.set('FR', new FlagSpec('FR', 30, 20).vstripes(['#0055A4', '#ffffff', '#EF4135']));
  m.set('IT', new FlagSpec('IT', 30, 20).vstripes(['#009246', '#ffffff', '#CE2B37']));
  m.set('BE', new FlagSpec('BE', 30, 20).vstripes(['#000000', '#FDDA24', '#EF3340']));
  m.set('IE', new FlagSpec('IE', 30, 20).vstripes(['#169B62', '#ffffff', '#FF883E']));
  m.set('RO', new FlagSpec('RO', 30, 20).vstripes(['#002B7F', '#FCD116', '#CE1126']));
  m.set('DE', new FlagSpec('DE', 30, 20).hstripes(['#000000', '#DD0000', '#FFCE00']));
  m.set('RU', new FlagSpec('RU', 30, 20).hstripes(['#ffffff', '#0039A6', '#D52B1E']));
  m.set('NL', new FlagSpec('NL', 30, 20).hstripes(['#AE1C28', '#ffffff', '#21468B']));
  m.set('AT', new FlagSpec('AT', 30, 20).hstripes(['#ED2939', '#ffffff', '#ED2939']));
  m.set('PL', new FlagSpec('PL', 30, 20).hstripes(['#ffffff', '#DC143C']));
  m.set('UA', new FlagSpec('UA', 30, 20).hstripes(['#0057B7', '#FFDD00']));
  m.set('SE', seFlag());
  m.set('CH', chFlag());
  return m;
}

const FLAGS: Map<string, FlagSpec> = buildFlags();

export function flagOf(code: string): FlagSpec | null {
  const f: FlagSpec | undefined = FLAGS.get(code);
  return f === undefined ? null : f;
}

/**
 * 把一面旗画进 (x, y, w, h) 的方框里, 保持原比例居中。
 */
export function paintFlag(ctx: CanvasRenderingContext2D, code: string,
  x: number, y: number, w: number, h: number): void {
  const spec: FlagSpec | null = flagOf(code);
  if (spec === null) {
    return;
  }
  const scale: number = Math.min(w / spec.vw, h / spec.vh);
  const ox: number = x + (w - spec.vw * scale) / 2;
  const oy: number = y + (h - spec.vh * scale) / 2;
  for (let i: number = 0; i < spec.shapes.length; i++) {
    const s: Shape = spec.shapes[i];
    ctx.fillStyle = s.color;
    if (s.kind === 'rect') {
      ctx.fillRect(ox + s.x * scale, oy + s.y * scale, s.w * scale, s.h * scale);
    } else if (s.kind === 'circle') {
      ctx.beginPath();
      ctx.arc(ox + s.cx * scale, oy + s.cy * scale, s.r * scale, 0, Math.PI * 2);
      ctx.fill();
    } else {
      // 五角星: 10 个顶点 (外/内半径交替)
      ctx.beginPath();
      for (let k: number = 0; k < 10; k++) {
        const rr: number = k % 2 === 0 ? s.r : s.r * 0.382;
        const a: number = ((-90 + s.deg) + k * 36) * Math.PI / 180;
        const px: number = ox + (s.cx + rr * Math.cos(a)) * scale;
        const py: number = oy + (s.cy + rr * Math.sin(a)) * scale;
        if (k === 0) {
          ctx.moveTo(px, py);
        } else {
          ctx.lineTo(px, py);
        }
      }
      ctx.closePath();
      ctx.fill();
    }
  }
}
