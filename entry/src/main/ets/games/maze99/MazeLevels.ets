/**
 * 奇妙迷宫 · 关卡与规则 —— 移植自 kids-games 系列仓库 kids-maze-game。
 *
 * 原实现 (js/maze-core.js + js/mazes-data.js + js/levels.js):
 *  - 每格 cell 是 4 位掩码 N=1 E=2 S=4 W=8, 置位表示该方向有墙;
 *  - 99 关迷宫由 scripts/bake-mazes.js 预计算并烘焙进 mazes-data.js,
 *    运行时不生成 (种子 + 生成算法改动才重新烘焙);
 *  - 移动是"撞墙则不动 + 抖一下", 不消耗步数, 也没有失败状态。
 *
 * 这里只搬运行时需要的部分: 掩码定义、移动判定、关卡数据读取。
 * 生成算法 (mulberry32 / 递归回溯 / 错误分叉嵌套控制) 不在运行时, 因此不移植。
 */
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { resourceManager } from '@kit.LocalizationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0001;
const TAG: string = 'KidsMaze99';

/** 四方向墙位 (与原 WALL 常量一致) */
export const WALL_N: number = 1;
export const WALL_E: number = 2;
export const WALL_S: number = 4;
export const WALL_W: number = 8;

/** 一格坐标 */
export class Cell {
  r: number = 0;
  c: number = 0;

  constructor(r: number, c: number) {
    this.r = r;
    this.c = c;
  }

  equals(o: Cell): boolean {
    return this.r === o.r && this.c === o.c;
  }
}

/** 主题配色 (原 css 里 theme 变量; colors 为 null 时按主题名查表) */
export class MazeTheme {
  bg: string = '#e8f5d8';
  ink: string = '#2a3b1f';
  wall: string = '#6b8f4e';
  path: string = '#fff8e7';
  accent: string = '#f0a83a';
}

/** 一关 */
export class MazeLevel {
  id: string = '';
  title: string = '';
  size: number = 10;
  theme: string = 'forest';
  playerEmoji: string = '🐰';
  goalEmoji: string = '🏠';
  /** size×size 的墙位掩码 */
  cells: number[][] = [];
  start: Cell = new Cell(0, 0);
  goal: Cell = new Cell(0, 0);
  /** 主题色, 有些关自带 (原 colors 字段), 否则按 theme 查表 */
  colors: MazeTheme | null = null;

  cellWalls(r: number, c: number): number {
    if (r < 0 || c < 0 || r >= this.size || c >= this.size) {
      return 15; // 越界当四面都是墙
    }
    return this.cells[r][c];
  }
}

/** 移动结果 */
export class MoveResult {
  /** 有没有挪动 */
  moved: boolean = false;
  /** 是不是撞墙了 (UI 抖一下) */
  bumped: boolean = false;
  pos: Cell = new Cell(0, 0);
}

/**
 * 朝 dir 走一步。撞墙返回 bumped = true 且位置不变 (与原 tryMove 一致)。
 * dir 取值 'N' / 'E' / 'S' / 'W'。
 */
export function tryMove(level: MazeLevel, pos: Cell, dir: string): MoveResult {
  const res: MoveResult = new MoveResult();
  res.pos = new Cell(pos.r, pos.c);
  const walls: number = level.cellWalls(pos.r, pos.c);
  let bit: number = 0;
  let dr: number = 0;
  let dc: number = 0;
  if (dir === 'N') {
    bit = WALL_N;
    dr = -1;
  } else if (dir === 'E') {
    bit = WALL_E;
    dc = 1;
  } else if (dir === 'S') {
    bit = WALL_S;
    dr = 1;
  } else if (dir === 'W') {
    bit = WALL_W;
    dc = -1;
  } else {
    res.bumped = true;
    return res;
  }
  if ((walls & bit) !== 0) {
    res.bumped = true;
    return res;
  }
  const nr: number = pos.r + dr;
  const nc: number = pos.c + dc;
  if (nr < 0 || nc < 0 || nr >= level.size || nc >= level.size) {
    res.bumped = true;
    return res;
  }
  res.pos = new Cell(nr, nc);
  res.moved = true;
  return res;
}

export function isAtGoal(level: MazeLevel, pos: Cell): boolean {
  return pos.r === level.goal.r && pos.c === level.goal.c;
}

// ---------- 主题色表 (移植自原 css/style.css 的 body[data-theme]) ----------

function themeOf(name: string): MazeTheme {
  const t: MazeTheme = new MazeTheme();
  if (name === 'ocean') {
    t.bg = '#d9f1f7';
    t.ink = '#1a3a4a';
    t.wall = '#3aa0b8';
    t.path = '#eefcff';
    t.accent = '#ff8fab';
  } else if (name === 'space') {
    t.bg = '#1b2340';
    t.ink = '#f2e9ff';
    t.wall = '#6b5b95';
    t.path = '#2a3358';
    t.accent = '#ffd36a';
  } else if (name === 'candy') {
    t.bg = '#ffe4f1';
    t.ink = '#6b2048';
    t.wall = '#e8789a';
    t.path = '#fff5fa';
    t.accent = '#ffb347';
  } else if (name === 'dino') {
    t.bg = '#e5f2c9';
    t.ink = '#2f4a1c';
    t.wall = '#7a9e3e';
    t.path = '#f4fadb';
    t.accent = '#c4a035';
  } else if (name === 'farm') {
    t.bg = '#f3e6c8';
    t.ink = '#4a3420';
    t.wall = '#a67c52';
    t.path = '#fff8e8';
    t.accent = '#7cb342';
  } else if (name === 'pirate') {
    t.bg = '#d8ecf5';
    t.ink = '#1e3a4c';
    t.wall = '#3d6f8c';
    t.path = '#eef7fb';
    t.accent = '#e0a100';
  } else if (name === 'snow') {
    t.bg = '#e8f2ff';
    t.ink = '#243b55';
    t.wall = '#7aa0c4';
    t.path = '#f7fbff';
    t.accent = '#5ec4d4';
  } else if (name === 'volcano') {
    t.bg = '#2b1a18';
    t.ink = '#ffe7d6';
    t.wall = '#a04830';
    t.path = '#3a2420';
    t.accent = '#ff7a3d';
  } else if (name === 'garden') {
    t.bg = '#eef8e4';
    t.ink = '#35522a';
    t.wall = '#7cbc6a';
    t.path = '#f7fff0';
    t.accent = '#f0a0c0';
  } else if (name === 'train') {
    t.bg = '#e7eef8';
    t.ink = '#243048';
    t.wall = '#5a7aa8';
    t.path = '#f4f7fc';
    t.accent = '#e25b4c';
  } else if (name === 'castle') {
    t.bg = '#efe6f5';
    t.ink = '#3a2a55';
    t.wall = '#8a6fb0';
    t.path = '#faf6ff';
    t.accent = '#d4a017';
  } else if (name === 'desert') {
    t.bg = '#f6e3c0';
    t.ink = '#5a3a18';
    t.wall = '#c49a5a';
    t.path = '#fff6e4';
    t.accent = '#2f9e7a';
  } else if (name === 'rainbow') {
    t.bg = '#fff0e8';
    t.ink = '#4a2a50';
    t.wall = '#e07a9a';
    t.path = '#fffaf5';
    t.accent = '#5ec4e0';
  } else if (name === 'moon') {
    t.bg = '#1a1f3a';
    t.ink = '#e8e4ff';
    t.wall = '#5a6088';
    t.path = '#262b4a';
    t.accent = '#f0d878';
  } else {
    // forest 及未知主题
    t.bg = '#e8f5d8';
    t.ink = '#2a3b1f';
    t.wall = '#6b8f4e';
    t.path = '#fff8e7';
    t.accent = '#f0a83a';
  }
  return t;
}

// ---------- JSON 反序列化 ----------

interface ColorsJson {
  bg: string;
  ink: string;
  wall: string;
  path: string;
  accent: string;
}

interface LevelJson {
  id: string;
  title: string;
  size: number;
  theme: string;
  playerEmoji: string;
  goalEmoji: string;
  colors: ColorsJson | null;
  cells: number[][];
  start: CellJson;
  goal: CellJson;
}

interface CellJson {
  r: number;
  c: number;
}

export function toLevel(j: LevelJson): MazeLevel {
  const l: MazeLevel = new MazeLevel();
  l.id = j.id;
  l.title = j.title;
  l.size = j.size;
  l.theme = j.theme;
  l.playerEmoji = j.playerEmoji;
  l.goalEmoji = j.goalEmoji;
  l.cells = j.cells;
  l.start = new Cell(j.start.r, j.start.c);
  l.goal = new Cell(j.goal.r, j.goal.c);
  if (j.colors !== null && j.colors !== undefined) {
    const t: MazeTheme = new MazeTheme();
    t.bg = j.colors.bg;
    t.ink = j.colors.ink;
    t.wall = j.colors.wall;
    t.path = j.colors.path;
    t.accent = j.colors.accent;
    l.colors = t;
  }
  return l;
}

/** 取某关的主题色: 自有 colors 优先, 否则按 theme 查表 */
export function themeFor(level: MazeLevel): MazeTheme {
  return level.colors === null ? themeOf(level.theme) : level.colors;
}

/** 99 关数据加载器 */
export class MazeLoader {
  private rm: resourceManager.ResourceManager | null = null;
  private cached: MazeLevel[] | null = null;

  init(context: common.UIAbilityContext): void {
    if (this.rm === null) {
      this.rm = context.resourceManager;
    }
  }

  levels(): MazeLevel[] {
    if (this.cached !== null) {
      return this.cached;
    }
    if (this.rm === null) {
      return [];
    }
    try {
      const bytes: Uint8Array = this.rm.getRawFileContentSync('maze/levels.json');
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
      const arr: LevelJson[] = JSON.parse(decoder.decodeToString(bytes)) as LevelJson[];
      const out: MazeLevel[] = [];
      for (let i: number = 0; i < arr.length; i++) {
        out.push(toLevel(arr[i]));
      }
      this.cached = out;
      return out;
    } catch (e) {
      const err: Error = e as Error;
      hilog.error(DOMAIN, TAG, 'load maze levels failed: %{public}s', err.message);
      return [];
    }
  }
}
