/**
 * 口算闯关的难度与关卡配置 —— 移植自 kids-games/games/math/levels.js。
 *
 * 4 档难度 × 每档 3 关, 难度靠这几件事递进:
 *  - 数域 (10 / 20 / 100 / 99 四则混合);
 *  - 答题方式 (4 选 1 → 数字键盘);
 *  - 图示 (启蒙档配 ○ 图示, 让不识数的孩子也能数);
 *  - 计时与连击;
 *  - 宽容度 (启蒙档答错只提示、不前进、不计错)。
 */
import { GenConfig } from './Problems';

/** 难度卡 (对应原 KG.MATH_DIFFICULTIES) */
export class MathDiff {
  key: string = '';
  emoji: string = '';
  label: string = '';
  age: string = '';
  desc: string = '';
  accent: string = '#5b9be8';
  levels: MathLevel[] = [];

  constructor(key: string, emoji: string, label: string, age: string, desc: string, accent: string) {
    this.key = key;
    this.emoji = emoji;
    this.label = label;
    this.age = age;
    this.desc = desc;
    this.accent = accent;
  }
}

/** 一关 */
export class MathLevel {
  id: number = 1;
  name: string = '';
  emoji: string = '📍';
  count: number = 10;
  /** 'choice' = 4 选 1; 'input' = 数字键盘 */
  mode: string = 'choice';
  /** '' = 不计时; 'soft' = 只记录; 'hard' = 影响速度星 */
  timer: string = '';
  combo: boolean = false;
  /** 配 ○ 图示 (启蒙加减) */
  pictograph: boolean = false;
  /** 最宽容: 答错只提示, 不前进不计错 */
  lenient: boolean = false;
  /** 三星的平均每题秒数阈值 (仅 hard 计时关) */
  starTime: number = 10;
  gen: GenConfig = new GenConfig();

  constructor(id: number, name: string, emoji: string, count: number, mode: string) {
    this.id = id;
    this.name = name;
    this.emoji = emoji;
    this.count = count;
    this.mode = mode;
  }
}

function genCfg(ops: string[], max: number, terms: number, choices: number): GenConfig {
  const g: GenConfig = new GenConfig();
  g.ops = ops;
  g.max = max;
  g.terms = terms;
  g.choices = choices;
  return g;
}

// ---------------- 启蒙: 10 以内加减, 4 选 1, 配图示, 点一点会读题 ----------------

function easyOne(): MathLevel {
  const l: MathLevel = new MathLevel(1, '森林', '🌳', 8, 'choice');
  l.timer = '';
  l.pictograph = true;
  l.lenient = true;
  l.gen = genCfg(['+'], 10, 2, 4);
  l.gen.allowCarry = false;
  return l;
}

function easyTwo(): MathLevel {
  const l: MathLevel = new MathLevel(2, '草原', '🌾', 8, 'choice');
  l.pictograph = true;
  l.lenient = true;
  l.gen = genCfg(['-'], 10, 2, 4);
  l.gen.allowCarry = false;
  return l;
}

function easyThree(): MathLevel {
  const l: MathLevel = new MathLevel(3, '小溪', '🏞️', 10, 'choice');
  l.pictograph = true;
  l.lenient = true;
  l.gen = genCfg(['+', '-'], 10, 2, 4);
  l.gen.allowCarry = false;
  return l;
}

// ---------------- 进阶: 20/100 含进退位, 先选一选再打数字, 有连击 ----------------

function mediumOne(): MathLevel {
  const l: MathLevel = new MathLevel(1, '村庄', '🏘️', 10, 'choice');
  l.combo = true;
  l.gen = genCfg(['+', '-'], 20, 2, 4);
  l.gen.allowCarry = true;
  return l;
}

function mediumTwo(): MathLevel {
  const l: MathLevel = new MathLevel(2, '山脚', '⛰️', 10, 'choice');
  l.combo = true;
  l.gen = genCfg(['+', '-'], 100, 2, 4);
  l.gen.allowCarry = true;
  return l;
}

function mediumThree(): MathLevel {
  const l: MathLevel = new MathLevel(3, '石桥', '🌉', 10, 'input');
  l.combo = true;
  l.gen = genCfg(['+', '-'], 100, 2, 4);
  l.gen.allowCarry = true;
  return l;
}

// ---------------- 熟练: 表内乘除、两位数加减, 键盘输入, 会计时 ----------------

function hardOne(): MathLevel {
  const l: MathLevel = new MathLevel(1, '山洞', '🕳️', 10, 'input');
  l.timer = 'soft';
  l.combo = true;
  l.gen = genCfg(['×'], 81, 2, 4);
  l.gen.mulMax = 9;
  return l;
}

function hardTwo(): MathLevel {
  const l: MathLevel = new MathLevel(2, '矿井', '⛏️', 10, 'input');
  l.timer = 'soft';
  l.combo = true;
  l.gen = genCfg(['÷'], 81, 2, 4);
  l.gen.divMax = 9;
  l.gen.divExact = true;
  return l;
}

function hardThree(): MathLevel {
  const l: MathLevel = new MathLevel(3, '峡谷', '🏜️', 12, 'input');
  l.timer = 'soft';
  l.combo = true;
  l.gen = genCfg(['+', '-', '×', '÷'], 99, 2, 4);
  l.gen.mulMax = 9;
  l.gen.divMax = 9;
  return l;
}

// ---------------- 挑战: 四则混合、两步、带括号, 计时 + 连击冲纪录 ----------------

function challengeOne(): MathLevel {
  const l: MathLevel = new MathLevel(1, '城墙', '🧱', 10, 'input');
  l.timer = 'hard';
  l.combo = true;
  l.starTime = 10;
  l.gen = genCfg(['×'], 99, 2, 4);
  l.gen.mulMax = 99; // 两位数 × 一位数
  return l;
}

function challengeTwo(): MathLevel {
  const l: MathLevel = new MathLevel(2, '城堡', '🏰', 12, 'input');
  l.timer = 'hard';
  l.combo = true;
  l.starTime = 9;
  l.gen = genCfg(['+', '-'], 100, 3, 4); // 两步
  l.gen.allowCarry = true;
  return l;
}

function challengeThree(): MathLevel {
  const l: MathLevel = new MathLevel(3, '王座', '👑', 12, 'input');
  l.timer = 'hard';
  l.combo = true;
  l.starTime = 9;
  l.gen = genCfg(['+', '-'], 100, 3, 4); // 带括号
  l.gen.allowCarry = true;
  l.gen.parens = true;
  return l;
}

/** 4 档难度, 顺序即由易到难 */
export function buildDiffs(): MathDiff[] {
  const easy: MathDiff = new MathDiff('easy', '🐣', '启蒙', '4-6 岁 · 学龄前',
    '10 以内加减，4 选 1，配○图示，点一点会读题', '#4cc1a1');
  easy.levels = [easyOne(), easyTwo(), easyThree()];

  const medium: MathDiff = new MathDiff('medium', '🦊', '进阶', '6-8 岁 · 低年级',
    '20/100 以内含进退位，先选一选再练打数字，有连击', '#5b9be8');
  medium.levels = [mediumOne(), mediumTwo(), mediumThree()];

  const hard: MathDiff = new MathDiff('hard', '🐯', '熟练', '8-10 岁',
    '表内乘除、两位数加减，数字键盘输入，会计时', '#f4b942');
  hard.levels = [hardOne(), hardTwo(), hardThree()];

  const challenge: MathDiff = new MathDiff('challenge', '🐉', '挑战', '10-12 岁',
    '四则混合、两步、带括号，计时 + 连击冲纪录', '#ec7d7d');
  challenge.levels = [challengeOne(), challengeTwo(), challengeThree()];

  return [easy, medium, hard, challenge];
}

/**
 * 星星评定: 按正确率给 1-3 星, hard 计时关叠加速度门槛。
 * 完成保底 1 星 (鼓励), 与原 starsFor 一致。
 */
export function starsFor(accuracy: number, total: number, elapsedSec: number,
  timer: string, starTime: number): number {
  let stars: number = 1;
  if (accuracy >= 0.9) {
    stars = 3;
  } else if (accuracy >= 0.7) {
    stars = 2;
  }
  if (stars === 3 && timer === 'hard' && total > 0) {
    const perQ: number = elapsedSec / total;
    const limit: number = starTime > 0 ? starTime : 10;
    if (perQ > limit) {
      stars = 2; // 全对但太慢 → 降到 2 星
    }
  }
  return Math.max(1, Math.min(3, stars));
}

/** 星级字符串 ⭐⭐⭐ / ⭐★☆ 这种, 缺的用空心 */
export function starText(stars: number, max: number = 3): string {
  let s: string = '';
  for (let i: number = 0; i < max; i++) {
    s += i < stars ? '⭐' : '☆';
  }
  return s;
}

/** 秒数格式化成 mm:ss, 与原 fmtTime 一致 */
export function fmtTime(sec: number): string {
  const m: number = Math.floor(sec / 60);
  const s: number = sec % 60;
  return (m < 10 ? '0' : '') + m + ':' + (s < 10 ? '0' : '') + s;
}
