/**
 * 舒尔特方格 —— 移植自 kids-games/games/schulte。
 *
 * 玩法: 按 1、2、3… 的顺序把打乱的数字网格点一遍, 计时冲最快纪录。
 * 纯逻辑部分 (造网格 / 状态机) 与 UI 分离, 页面只把回调映射成 @State。
 */

/** 生成长度 n*n、值为 1..n*n 的 Fisher-Yates 打乱数组 */
export function buildGrid(n: number): number[] {
  const a: number[] = [];
  for (let i: number = 1; i <= n * n; i++) {
    a.push(i);
  }
  for (let i: number = a.length - 1; i > 0; i--) {
    const j: number = Math.floor(Math.random() * (i + 1));
    const t: number = a[i];
    a[i] = a[j];
    a[j] = t;
  }
  return a;
}

/** 难度档: 3×3 ~ 6×6 */
export class SchulteTier {
  key: string = '';
  size: number = 3;
  emoji: string = '';
  label: string = '';
  desc: string = '';

  constructor(key: string, size: number, emoji: string, label: string, desc: string) {
    this.key = key;
    this.size = size;
    this.emoji = emoji;
    this.label = label;
    this.desc = desc;
  }
}

export function buildTiers(): SchulteTier[] {
  return [
    new SchulteTier('s3', 3, '🐣', '3×3', '1–9，刚上手'),
    new SchulteTier('s4', 4, '🦊', '4×4', '1–16，进阶'),
    new SchulteTier('s5', 5, '🐯', '5×5', '1–25，经典'),
    new SchulteTier('s6', 6, '🐉', '6×6', '1–36，挑战')
  ];
}

export class SchulteStats {
  tierKey: string = '';
  size: number = 3;
  elapsed: number = 0;
  errors: number = 0;
}

/** 格子状态 (页面渲染用) */
export class CellState {
  val: number = 0;
  found: boolean = false;
  /** 刚点错时短暂置 true */
  wrong: boolean = false;

  constructor(val: number) {
    this.val = val;
  }
}

export interface SchulteHandler {
  onGrid?: (cells: CellState[]) => void;
  onNext?: (next: number) => void;
  onErrors?: (errors: number) => void;
  onTick?: (elapsedSec: number) => void;
  onTapRight?: (val: number, index: number) => void;
  onTapWrong?: (val: number, index: number) => void;
  onWin?: (stats: SchulteStats) => void;
}

export class SchulteGame {
  private tier: SchulteTier;
  private cb: SchulteHandler;
  private total: number = 0;
  private next: number = 1;
  private errors: number = 0;
  private elapsed: number = 0;
  private timerId: number = -1;
  private finished: boolean = false;

  constructor(tier: SchulteTier, cb: SchulteHandler) {
    this.tier = tier;
    this.cb = cb;
    this.total = tier.size * tier.size;
  }

  start(): void {
    const grid: number[] = buildGrid(this.tier.size);
    const cells: CellState[] = [];
    for (let i: number = 0; i < grid.length; i++) {
      cells.push(new CellState(grid[i]));
    }
    this.next = 1;
    this.errors = 0;
    this.elapsed = 0;
    this.finished = false;
    if (this.cb.onGrid !== undefined) {
      this.cb.onGrid(cells);
    }
    this.emitNext();
    this.emitErrors();
    this.startTimer();
  }

  destroy(): void {
    this.stopTimer();
  }

  isFinished(): boolean {
    return this.finished;
  }

  current(): number {
    return this.next;
  }

  nextValue(): number {
    return this.next;
  }

  /** 点了一个格子; 返回 true 表示点对了 */
  tap(val: number, index: number): boolean {
    if (this.finished) {
      return false;
    }
    if (val === this.next) {
      this.next++;
      if (this.cb.onTapRight !== undefined) {
        this.cb.onTapRight(val, index);
      }
      if (this.next > this.total) {
        this.win();
        return true;
      }
      this.emitNext();
      return true;
    }
    this.errors++;
    this.emitErrors();
    if (this.cb.onTapWrong !== undefined) {
      this.cb.onTapWrong(val, index);
    }
    return false;
  }

  /** 点错抖动结束后由页面清除标记 */
  private emitNext(): void {
    if (this.cb.onNext !== undefined) {
      this.cb.onNext(this.next);
    }
  }

  private emitErrors(): void {
    if (this.cb.onErrors !== undefined) {
      this.cb.onErrors(this.errors);
    }
  }

  private startTimer(): void {
    this.stopTimer();
    this.timerId = setInterval((): void => {
      if (this.finished) {
        return;
      }
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

  private win(): void {
    this.finished = true;
    this.stopTimer();
    const s: SchulteStats = new SchulteStats();
    s.tierKey = this.tier.key;
    s.size = this.tier.size;
    s.elapsed = this.elapsed;
    s.errors = this.errors;
    if (this.cb.onWin !== undefined) {
      this.cb.onWin(s);
    }
  }
}
