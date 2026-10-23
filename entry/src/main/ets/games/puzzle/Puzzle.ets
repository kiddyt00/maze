/**
 * 拼图核心 —— 移植自 kids-games/games/puzzle/js/{game,render,difficulty}.js。
 *
 * 玩法: 把右侧托盘里的拼块拖到棋盘上的正确位置。
 * 判定不看"形状是否重合", 而是看「落点离该块重心的距离是否小于吸附半径」,
 * 这样孩子的手指不需要像素级精确 —— 这是原实现最关键的手感设计, 这里原样保留。
 *
 * 渲染改用 Canvas Path2D: 地图路径只有 M/L/Z 三种命令, 可以直接
 *   new Path2D(d) + Translate(sx, sy) + Scale(rx, ry)
 * 映射到棋盘任意矩形 (等价于 SVG 的 viewBox + preserveAspectRatio=meet)。
 */

import { Dataset, Piece, REGION_ORDER } from './MapData';

/** 难度配置 */
export class PuzzleDiff {
  key: string = '';
  emoji: string = '';
  label: string = '';
  age: string = '';
  desc: string = '';
  outline: boolean = true;
  /** 'slots' = 每块灰色槽位; 'silhouette' = 只剩国界剪影 */
  outlineMode: string = 'slots';
  /** 槽位上标省名 (最简单档照着名字放) */
  outlineNames: boolean = false;
  pieceName: boolean = false;
  piecePinyin: boolean = false;
  speakOnPlace: boolean = true;
  speakOnPick: boolean = false;
  /** 吸附半径 (地图坐标) */
  snap: number = 30;
  /** 按七大区分关推进 */
  byRegion: boolean = false;
  timer: boolean = false;

  constructor(key: string, emoji: string, label: string) {
    this.key = key;
    this.emoji = emoji;
    this.label = label;
  }
}

/** 全国三档 */
export function buildNationalDiffs(): PuzzleDiff[] {
  const easy: PuzzleDiff = new PuzzleDiff('easy', '🐣', '简单');
  easy.age = '3-6 岁 · 学龄前';
  easy.desc = '按七大区一关一关来，省份带拼音、点一点会读名字，吸附范围大';
  easy.outline = true;
  easy.outlineMode = 'slots';
  easy.outlineNames = true;
  easy.pieceName = true;
  easy.piecePinyin = true;
  easy.speakOnPlace = true;
  easy.speakOnPick = true;
  easy.snap = 58;
  easy.byRegion = true;
  easy.timer = false;

  const medium: PuzzleDiff = new PuzzleDiff('medium', '🦊', '中等');
  medium.age = '6-10 岁 · 小学';
  medium.desc = '一次拼全 34 个省，底图只有空白轮廓，看名字找位置';
  medium.outline = true;
  medium.outlineMode = 'slots';
  medium.outlineNames = false;
  medium.pieceName = true;
  medium.piecePinyin = false;
  medium.speakOnPlace = true;
  medium.speakOnPick = false;
  medium.snap = 32;
  medium.byRegion = false;
  medium.timer = false;

  const hard: PuzzleDiff = new PuzzleDiff('hard', '🐉', '困难');
  hard.age = '高手挑战';
  hard.desc = '只有国界外框、不显示名字、要放得准，还会计时和记错误';
  hard.outline = true;
  hard.outlineMode = 'silhouette';
  hard.outlineNames = false;
  hard.pieceName = false;
  hard.piecePinyin = false;
  hard.speakOnPlace = true;
  hard.speakOnPick = false;
  hard.snap = 18;
  hard.byRegion = false;
  hard.timer = true;

  return [easy, medium, hard];
}

/** 分省拼图: 单档固定配置 */
export function buildProvinceDiff(): PuzzleDiff {
  const d: PuzzleDiff = new PuzzleDiff('province', '🗺️', '分省');
  d.age = '看省份';
  d.desc = '把每个地级市拼回省内';
  d.outline = true;
  d.outlineMode = 'province';
  d.outlineNames = false;
  d.pieceName = true;
  d.piecePinyin = false;
  d.speakOnPlace = true;
  d.speakOnPick = true;
  d.snap = 28; // 兜底, 实际用 dataset.snap
  d.byRegion = false;
  d.timer = false;
  return d;
}

/** 棋盘坐标 → 屏幕坐标的映射 (与原 screenToBoard 互逆) */
export class BoardMap {
  /** 缩放比 (地图坐标 → vp) */
  scale: number = 1;
  /** 地图左上角在棋盘里的偏移 (vp) */
  ox: number = 0;
  oy: number = 0;
  /** 棋盘尺寸 (vp) */
  w: number = 0;
  h: number = 0;

  /** 地图坐标 → 棋盘内 vp */
  toScreen(x: number, y: number): number[] {
    return [this.ox + x * this.scale, this.oy + y * this.scale];
  }

  /** 棋盘内 vp → 地图坐标 */
  toBoard(x: number, y: number): number[] {
    return [(x - this.ox) / this.scale, (y - this.oy) / this.scale];
  }
}

/** 按容器尺寸算 meet 缩放 (等价 preserveAspectRatio=meet) */
export function fitBoard(w: number, h: number, mw: number, mh: number): BoardMap {
  const m: BoardMap = new BoardMap();
  m.w = w;
  m.h = h;
  if (w <= 0 || h <= 0) {
    return m;
  }
  const s: number = Math.min(w / mw, h / mh);
  m.scale = s;
  m.ox = (w - mw * s) / 2;
  m.oy = (h - mh * s) / 2;
  return m;
}

export class PuzzleStats {
  diff: PuzzleDiff = new PuzzleDiff('', '', '');
  elapsed: number = 0;
  errors: number = 0;
  total: number = 0;
  /** 分省时的省名 */
  name: string = '';
  byRegionCapable: boolean = true;
}

export interface PuzzleHandler {
  /** 每放对一块 */
  onPlaced?: (pieceIndex: number, remaining: number) => void;
  /** 放错一次 (拖到棋盘上但没吸附) */
  onError?: (errors: number) => void;
  /** 换关 (大区分关时): 关序号 / 大区名 / 本关块索引 */
  onLevel?: (levelIndex: number, regionName: string, batch: number[]) => void;
  onTick?: (elapsedSec: number) => void;
  onWin?: (stats: PuzzleStats) => void;
}

export class PuzzleGame {
  diff: PuzzleDiff;
  dataset: Dataset;
  private cb: PuzzleHandler;
  /** 实际生效的吸附半径 */
  snap: number = 30;
  placed: Set<number> = new Set<number>();
  errors: number = 0;
  elapsed: number = 0;
  private timerId: number = -1;
  byRegion: boolean = false;
  regions: string[] = [];
  regionIndex: number = 0;
  /** 当前这一关要拼的块索引 */
  batch: number[] = [];

  constructor(diff: PuzzleDiff, dataset: Dataset, cb: PuzzleHandler) {
    this.diff = diff;
    this.dataset = dataset;
    this.cb = cb;
    this.snap = dataset.snap > 0 && dataset.byRegionCapable === false ? dataset.snap : diff.snap;
    this.byRegion = diff.byRegion && dataset.byRegionCapable;
    if (this.byRegion) {
      for (let i: number = 0; i < REGION_ORDER.length; i++) {
        const r: string = REGION_ORDER[i];
        if (this.hasRegion(r)) {
          this.regions.push(r);
        }
      }
    }
  }

  private hasRegion(r: string): boolean {
    for (let i: number = 0; i < this.dataset.items.length; i++) {
      if (this.dataset.items[i].region === r) {
        return true;
      }
    }
    return false;
  }

  start(): void {
    if (this.diff.timer) {
      this.startTimer();
    }
    this.loadLevel();
  }

  destroy(): void {
    this.stopTimer();
  }

  /** 当前关需要拼的块索引 */
  currentBatch(): number[] {
    if (this.byRegion) {
      const r: string = this.regions[this.regionIndex];
      const out: number[] = [];
      for (let i: number = 0; i < this.dataset.items.length; i++) {
        if (this.dataset.items[i].region === r) {
          out.push(i);
        }
      }
      return out;
    }
    const all: number[] = [];
    for (let i: number = 0; i < this.dataset.items.length; i++) {
      all.push(i);
    }
    return all;
  }

  /** 只在托盘里出现、还没放对的块 */
  remainingBatch(): number[] {
    const out: number[] = [];
    const batch: number[] = this.currentBatch();
    for (let i: number = 0; i < batch.length; i++) {
      if (!this.placed.has(batch[i])) {
        out.push(batch[i]);
      }
    }
    return out;
  }

  loadLevel(): void {
    this.batch = this.currentBatch();
    if (this.cb.onLevel !== undefined) {
      const name: string = this.byRegion ? this.regions[this.regionIndex] : this.dataset.name;
      this.cb.onLevel(this.regionIndex, name, this.batch);
    }
  }

  /**
   * 尝试把某块放到 (bx, by) 处 (地图坐标)。
   * @returns 'hit' 吸附成功 / 'miss' 放错 / 'ignored' 不算失误
   */
  drop(pieceIndex: number, bx: number, by: number, overBoard: boolean): string {
    const p: Piece = this.dataset.items[pieceIndex];
    if (p === undefined || this.placed.has(pieceIndex)) {
      return 'ignored';
    }
    const dx: number = bx - p.cx;
    const dy: number = by - p.cy;
    const dist: number = Math.sqrt(dx * dx + dy * dy);
    if (dist <= this.snap) {
      this.placed.add(pieceIndex);
      p.placed = true;
      if (this.cb.onPlaced !== undefined) {
        this.cb.onPlaced(pieceIndex, this.remainingBatch().length);
      }
      this.checkProgress();
      return 'hit';
    }
    // 只有真的拖到棋盘上才算一次失误, 托盘里随手放下不罚
    if (overBoard) {
      this.errors++;
      if (this.cb.onError !== undefined) {
        this.cb.onError(this.errors);
      }
      return 'miss';
    }
    return 'ignored';
  }

  private checkProgress(): void {
    const rest: number[] = this.remainingBatch();
    if (rest.length > 0) {
      return;
    }
    if (this.byRegion && this.regionIndex < this.regions.length - 1) {
      this.regionIndex++;
      this.loadLevel();
      return;
    }
    this.win();
  }

  private win(): void {
    this.stopTimer();
    const s: PuzzleStats = new PuzzleStats();
    s.diff = this.diff;
    s.elapsed = this.elapsed;
    s.errors = this.errors;
    s.total = this.dataset.items.length;
    s.name = this.dataset.name;
    s.byRegionCapable = this.dataset.byRegionCapable;
    if (this.cb.onWin !== undefined) {
      this.cb.onWin(s);
    }
  }

  private startTimer(): void {
    this.stopTimer();
    this.timerId = setInterval((): void => {
      this.elapsed++;
      if (this.cb.onTick !== undefined) {
        this.cb.onTick(this.elapsed);
      }
    }, 1000);
  }

  private stopTimer(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }
}
