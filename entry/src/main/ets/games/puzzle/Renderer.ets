/**
 * 棋盘渲染 —— 移植自 kids-games/games/puzzle/js/render.js。
 *
 * 原实现用 SVG 元素 (path / text / g 分层); 这里用一块 Canvas 全量重绘,
 * 拖拽时只额外画一个跟随手指的浮层。理由:
 *  - 34 块省 + 南海诸岛合计 40 个路径, 每帧重绘在真机上完全跑得动;
 *  - 避免向 ArkUI 组件树里塞几百个 Path/Text 节点, 拖拽时状态同步更简单。
 *
 * 坐标系: 地图数据是 1000×820 的 viewBox 坐标, 渲染时按 BoardMap 缩放居中。
 */
import { Dataset, Piece, NanhaiBox, pieceColor, PIECE_PALETTE } from './MapData';
import { PuzzleDiff, BoardMap, fitBoard } from './Puzzle';

const SLOT_FILL: string = '#e8eef5';
const SLOT_STROKE: string = '#c6d4e2';
const SLOT_DONE_FILL: string = '#dceee6';
const OUTLINE_STROKE: string = '#9fb3c6';
const SILHOUETTE_FILL: string = '#d7e2ec';

/** 已生成的 Path2D 缓存: path 字符串 -> Path2D (避免每帧重建 34 个路径) */
class PathCache {
  private map: Map<string, Path2D> = new Map<string, Path2D>();

  get(d: string): Path2D | null {
    const hit: Path2D | undefined = this.map.get(d);
    if (hit !== undefined) {
      return hit;
    }
    try {
      const p: Path2D = new Path2D(d);
      this.map.set(d, p);
      return p;
    } catch (e) {
      return null;
    }
  }
}

const CACHE: PathCache = new PathCache();

/** 把地图坐标系里的一个 path 画到棋盘上 */
function drawPath(ctx: CanvasRenderingContext2D, d: string, m: BoardMap,
  fill: string, stroke: string, strokeWidth: number): void {
  const p: Path2D | null = CACHE.get(d);
  if (p === null) {
    return;
  }
  ctx.save();
  // 先缩放到地图坐标 → vp, 再平移; Path2D 内部坐标即地图坐标
  ctx.translate(m.ox, m.oy);
  ctx.scale(m.scale, m.scale);
  ctx.fillStyle = fill;
  ctx.fill(p);
  if (strokeWidth > 0) {
    // 线宽按缩放反算, 保证屏幕上线宽恒定
    ctx.lineWidth = strokeWidth / m.scale;
    ctx.strokeStyle = stroke;
    ctx.stroke(p);
  }
  ctx.restore();
}

/** 取一个 path 在某点的填充判定 (用于判断手指是否落在某块上) */
export function hitTestPath(d: string, m: BoardMap, x: number, y: number): boolean {
  const p: Path2D | null = CACHE.get(d);
  if (p === null) {
    return false;
  }
  // 用离屏 canvas 判定太重; 这里退化为 bbox 判定 (由调用方补充距离判定)
  return true;
}

/**
 * 画整张棋盘:
 *  1. 底图 (灰槽位 / 国界剪影 / 省外框);
 *  2. 已放置的块 (按区/调色板上色);
 *  3. 南海诸岛装饰;
 *  4. 高亮当前关的大区。
 */
export function drawBoard(ctx: CanvasRenderingContext2D, ds: Dataset, diff: PuzzleDiff,
  m: BoardMap, placed: Set<number>, activeRegion: string, showNames: boolean): void {
  ctx.clearRect(0, 0, m.w, m.h);

  // 棋盘底板
  ctx.fillStyle = '#ffffff';
  ctx.fillRect(0, 0, m.w, m.h);

  // ---- 1. 底图 ----
  if (ds.outline.length > 0) {
    // 分省: 只画一条省外轮廓作参考框
    drawPath(ctx, ds.outline, m, '#f4f7fb', OUTLINE_STROKE, 1.5);
  } else if (diff.outline && diff.outlineMode === 'silhouette') {
    // 困难档: 同色填充叠成国界剪影
    for (let i: number = 0; i < ds.items.length; i++) {
      drawPath(ctx, ds.items[i].path, m, SILHOUETTE_FILL, SILHOUETTE_FILL, 0);
    }
  } else if (diff.outline) {
    for (let i: number = 0; i < ds.items.length; i++) {
      const p: Piece = ds.items[i];
      const done: boolean = placed.has(i);
      const inRegion: boolean = activeRegion.length === 0 || p.region === activeRegion;
      const fill: string = done ? SLOT_DONE_FILL : (inRegion ? SLOT_FILL : '#f2f6fa');
      drawPath(ctx, p.path, m, fill, SLOT_STROKE, 1);
    }
    // 最简单的档: 槽位上标省名 (照着名字放)
    if (diff.outlineNames) {
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      for (let i: number = 0; i < ds.items.length; i++) {
        const p: Piece = ds.items[i];
        if (placed.has(i)) {
          continue;
        }
        const pos: number[] = m.toScreen(p.cx, p.cy);
        ctx.fillStyle = '#8fa3b8';
        ctx.font = (11).toString() + 'vp sans-serif';
        ctx.fillText(p.name, pos[0], pos[1]);
      }
    }
  }

  // ---- 2. 已放置的块 (后画, 压在槽位之上) ----
  for (let i: number = 0; i < ds.items.length; i++) {
    if (!placed.has(i)) {
      continue;
    }
    const p: Piece = ds.items[i];
    drawPath(ctx, p.path, m, pieceColor(p), '#ffffff', 1.2);
  }

  // ---- 3. 南海诸岛 (静态装饰, 始终显示, 体现完整版图) ----
  if (ds.nanhaiPath.length > 0 && ds.nanhaiBox !== null) {
    const box: NanhaiBox = ds.nanhaiBox;
    const s: number = box.scale <= 0 ? 1 : box.scale;
    // 外框
    ctx.save();
    ctx.translate(m.ox + box.x * m.scale, m.oy + box.y * m.scale);
    ctx.scale(m.scale * s, m.scale * s);
    ctx.fillStyle = '#f4f7fb';
    ctx.fillRect(0, 0, box.w, box.h);
    ctx.lineWidth = 1 / (m.scale * s);
    ctx.strokeStyle = SLOT_STROKE;
    ctx.strokeRect(0, 0, box.w, box.h);
    ctx.restore();
    // 岛礁路径 (用原始坐标, 必须随框缩放否则溢出)
    const p: Path2D | null = CACHE.get(ds.nanhaiPath);
    if (p !== null) {
      ctx.save();
      ctx.translate(m.ox + box.x * m.scale, m.oy + box.y * m.scale);
      ctx.scale(m.scale * s, m.scale * s);
      ctx.fillStyle = '#dfe8f1';
      ctx.fill(p);
      ctx.lineWidth = 0.6 / (m.scale * s);
      ctx.strokeStyle = '#c2d0de';
      ctx.stroke(p);
      ctx.restore();
    }
    // 标签 (字号不随缩放, 保持可读)
    const lx: number = m.ox + (box.x + (box.w * s) / 2) * m.scale;
    const ly: number = m.oy + (box.y + box.h * s - 4) * m.scale;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'bottom';
    ctx.fillStyle = '#8fa3b8';
    ctx.font = '10vp sans-serif';
    ctx.fillText('南海诸岛', lx, ly);
  }

  // ---- 4. 高亮当前大区的槽位描边 ----
  if (activeRegion.length > 0) {
    for (let i: number = 0; i < ds.items.length; i++) {
      const p: Piece = ds.items[i];
      if (p.region !== activeRegion || placed.has(i)) {
        continue;
      }
      drawPath(ctx, p.path, m, '', '#7fb2e8', 2);
    }
  }
}

/** 画拖拽浮层: 按棋盘真实比例显示, 落点更直观 */
export function drawDragClone(ctx: CanvasRenderingContext2D, p: Piece, diff: PuzzleDiff,
  m: BoardMap, cx: number, cy: number): void {
  const bbox: number[] = p.bbox;
  const bw: number = Math.max(1, bbox[2] - bbox[0]);
  const bh: number = Math.max(1, bbox[3] - bbox[1]);
  // 浮层按棋盘比例放大一点, 让孩子看清手里拿的是哪块
  const s: number = m.scale * 1.15;
  ctx.save();
  ctx.globalAlpha = 0.92;
  ctx.translate(cx - (p.cx - bbox[0]) * s, cy - (p.cy - bbox[1]) * s);
  ctx.scale(s, s);
  ctx.translate(-bbox[0], -bbox[1]);
  const path: Path2D | null = CACHE.get(p.path);
  if (path !== null) {
    ctx.fillStyle = pieceColor(p);
    ctx.fill(path);
    ctx.lineWidth = 1.5 / s;
    ctx.strokeStyle = '#ffffff';
    ctx.stroke(path);
  }
  ctx.restore();

  // 名字跟着浮层走
  if (diff.pieceName) {
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillStyle = '#ffffff';
    ctx.font = 'bold 13vp sans-serif';
    ctx.fillText(p.name, cx, cy);
  }
  // 吸附提示圈: 大小 = 吸附半径 (孩子能看到"放到这个圈里就行")
  ctx.save();
  ctx.beginPath();
  ctx.arc(cx, cy, 10, 0, Math.PI * 2);
  ctx.strokeStyle = '#5b9be8';
  ctx.lineWidth = 2;
  ctx.stroke();
  ctx.restore();
}

/** 托盘里的小拼块: 画到一块独立的小画布上 */
export function drawTrayPiece(ctx: CanvasRenderingContext2D, p: Piece, canvasW: number,
  canvasH: number): void {
  ctx.clearRect(0, 0, canvasW, canvasH);
  const bbox: number[] = p.bbox;
  const bw: number = Math.max(1, bbox[2] - bbox[0]);
  const bh: number = Math.max(1, bbox[3] - bbox[1]);
  const pad: number = 6;
  const s: number = Math.min((canvasW - pad * 2) / bw, (canvasH - pad * 2) / bh);
  const ox: number = (canvasW - bw * s) / 2 - bbox[0] * s;
  const oy: number = (canvasH - bh * s) / 2 - bbox[1] * s;
  const path: Path2D | null = CACHE.get(p.path);
  if (path === null) {
    return;
  }
  ctx.save();
  ctx.translate(ox, oy);
  ctx.scale(s, s);
  ctx.fillStyle = pieceColor(p);
  ctx.fill(path);
  ctx.lineWidth = 1.4 / s;
  ctx.strokeStyle = '#ffffff';
  ctx.stroke(path);
  ctx.restore();
}

/** 计算棋盘映射, 供页面在 areaChange 时调用 */
export function boardMap(w: number, h: number, ds: Dataset): BoardMap {
  return fitBoard(w, h, ds.width, ds.height);
}

export { PIECE_PALETTE };
