/**
 * 口算题目生成器 —— 移植自 kids-games/games/math/problems.js。
 *
 * 与原实现逐条对齐的边界:
 *  - 减法不出负数;
 *  - 除法只出整除题 (先定除数与商, 再乘出被除数);
 *  - 不进位/不退位档逐位约束, 保证孩子不用进位就能算;
 *  - 干扰项贴近正解且含常见错算 (加错算减 / 乘错算邻项 / 商 ±1 / 误填除数);
 *  - 一关内按算式文本去重, 题空间太小时兜底允许重复, 不死循环。
 *
 * 纯逻辑, 不碰 UI, 可以在 UI 之外单独复用来出题 (打地鼠就复用了 genProblem)。
 */

/** 题目生成器参数 (对应原 config 对象) */
export class GenConfig {
  ops: string[] = ['+'];
  max: number = 10;
  min: number = 0;
  /** 允许进位/退位; false 时逐位约束 */
  allowCarry: boolean = false;
  /** 2 = 两项; 3 = 三步运算 (挑战档) */
  terms: number = 2;
  /** 三步时是否带括号 */
  parens: boolean = false;
  divExact: boolean = true;
  divMax: number = 9;
  mulMax: number = 9;
  /** 选择题选项个数 */
  choices: number = 4;
}

/** 一道题 */
export class Problem {
  text: string = '';
  answer: number = 0;
  choices: number[] = [];
  /** '+', '-', '×', '÷', 'mixed' */
  op: string = '';
  /** 两项运算的操作数; 三步题与括号题没有 */
  operands: number[] = [];

  clone(): Problem {
    const p: Problem = new Problem();
    p.text = this.text;
    p.answer = this.answer;
    p.choices = this.choices.slice();
    p.op = this.op;
    p.operands = this.operands.slice();
    return p;
  }
}

function randInt(lo: number, hi: number): number {
  const h: number = hi < lo ? lo : hi;
  return lo + Math.floor(Math.random() * (h - lo + 1));
}

function pick(arr: string[]): string {
  return arr[Math.floor(Math.random() * arr.length)];
}

export function shuffleNum(arr: number[]): number[] {
  const a: number[] = arr.slice();
  for (let i: number = a.length - 1; i > 0; i--) {
    const j: number = Math.floor(Math.random() * (i + 1));
    const t: number = a[i];
    a[i] = a[j];
    a[j] = t;
  }
  return a;
}

/** 不进位加数: 逐位约束, 使 a+b 各位都不进位 */
function noCarryAddend(a: number, maxB: number): number {
  const onesRoom: number = Math.min(9 - (a % 10), maxB);
  const ones: number = randInt(0, Math.max(0, onesRoom));
  const tensRoomCarry: number = 9 - (Math.floor(a / 10) % 10);
  const tensRoomMax: number = Math.floor((maxB - ones) / 10);
  const tens: number = randInt(0, Math.max(0, Math.min(tensRoomCarry, tensRoomMax)));
  return tens * 10 + ones;
}

class RawProblem {
  op: string = '+';
  a: number = 0;
  b: number = 0;
  answer: number = 0;
  text: string = '';
  /** 三步/括号题没有单值操作数 */
  hasOperands: boolean = true;
}

function genAdd(cfg: GenConfig): RawProblem {
  const max: number = cfg.max;
  let a: number = 0;
  let b: number = 0;
  let guard: number = 0;
  do {
    a = randInt(cfg.min, max);
    const maxB: number = max - a;
    b = cfg.allowCarry ? randInt(0, maxB) : noCarryAddend(a, maxB);
    guard++;
  } while (a + b === 0 && guard < 20); // 避免 0+0 这种无聊题
  const r: RawProblem = new RawProblem();
  r.op = '+';
  r.a = a;
  r.b = b;
  r.answer = a + b;
  r.text = a + ' + ' + b;
  return r;
}

function genSub(cfg: GenConfig): RawProblem {
  const max: number = cfg.max;
  let a: number = 0;
  let b: number = 0;
  let guard: number = 0;
  do {
    a = randInt(cfg.min, max); // 被减数
    if (cfg.allowCarry) {
      b = randInt(0, a); // a >= b 保证非负
    } else {
      // 不退位: b 的每一位 <= a 对应位
      const ones: number = randInt(0, a % 10);
      const tens: number = randInt(0, Math.floor(a / 10) % 10);
      const hund: number = randInt(0, Math.floor(a / 100) % 10);
      b = hund * 100 + tens * 10 + ones;
    }
    guard++;
  } while ((a === 0 || (b === 0 && Math.random() < 0.5)) && guard < 20);
  const r: RawProblem = new RawProblem();
  r.op = '-';
  r.a = a;
  r.b = b;
  r.answer = a - b;
  r.text = a + ' - ' + b;
  return r;
}

function genMul(cfg: GenConfig): RawProblem {
  const mulMax: number = cfg.mulMax > 0 ? cfg.mulMax : 9;
  const max: number = cfg.max > 0 ? cfg.max : 81;
  let a: number = 1;
  let b: number = 1;
  let guard: number = 0;
  do {
    if (mulMax <= 9) {
      a = randInt(1, mulMax);
      b = randInt(1, mulMax);
    } else {
      // 两位数 × 一位数, 积 <= max
      const one: number = randInt(2, 9);
      const hiMax: number = Math.min(99, Math.floor(max / one));
      const two: number = randInt(10, Math.max(10, hiMax));
      if (Math.random() < 0.5) {
        a = one;
        b = two;
      } else {
        a = two;
        b = one;
      }
    }
    guard++;
  } while (a === 1 && b === 1 && guard < 20); // 避免 1×1 退化
  const r: RawProblem = new RawProblem();
  r.op = '×';
  r.a = a;
  r.b = b;
  r.answer = a * b;
  r.text = a + ' × ' + b;
  return r;
}

function genDiv(cfg: GenConfig): RawProblem {
  const divMax: number = cfg.divMax > 0 ? cfg.divMax : 9;
  const max: number = cfg.max > 0 ? cfg.max : 81;
  const divisor: number = randInt(2, divMax); // 除数 >= 2, 避免 ÷1
  const maxQuot: number = Math.max(1, Math.min(9, Math.floor(max / divisor)));
  const quotient: number = randInt(1, maxQuot);
  const dividend: number = divisor * quotient; // 先定商和除数 → 天然整除
  const r: RawProblem = new RawProblem();
  r.op = '÷';
  r.a = dividend;
  r.b = divisor;
  r.answer = quotient;
  r.text = dividend + ' ÷ ' + divisor;
  return r;
}

/** 三项 (仅 +/-): 从左到右逐步保证非负、不超 max; parens 时算 a op (b op2 c) */
function genThreeTerm(cfg: GenConfig): RawProblem {
  const max: number = cfg.max;
  const ops: string[] = ['+', '-'];
  const r: RawProblem = new RawProblem();
  r.op = 'mixed';
  r.hasOperands = false;
  if (cfg.parens) {
    const op2: string = pick(ops);
    let b: number = 0;
    let c: number = 0;
    let inner: number = 0;
    if (op2 === '+') {
      b = randInt(1, max);
      c = randInt(0, max - b);
      inner = b + c;
    } else {
      b = randInt(1, max);
      c = randInt(0, b);
      inner = b - c;
    }
    const op1: string = pick(ops);
    let a: number = 0;
    let answer: number = 0;
    if (op1 === '+') {
      a = randInt(0, max - inner);
      answer = a + inner;
    } else {
      a = randInt(inner, max); // a >= inner 保证非负
      answer = a - inner;
    }
    r.answer = answer;
    r.text = a + ' ' + op1 + ' (' + b + ' ' + op2 + ' ' + c + ')';
    return r;
  }
  const a: number = randInt(1, max);
  const op1: string = pick(ops);
  let b: number = 0;
  let r1: number = 0;
  if (op1 === '+') {
    b = randInt(0, max - a);
    r1 = a + b;
  } else {
    b = randInt(0, a);
    r1 = a - b;
  }
  const op2: string = pick(ops);
  let c: number = 0;
  let answer: number = 0;
  if (op2 === '+') {
    c = randInt(0, max - r1);
    answer = r1 + c;
  } else {
    c = randInt(0, r1);
    answer = r1 - c;
  }
  r.answer = answer;
  r.text = a + ' ' + op1 + ' ' + b + ' ' + op2 + ' ' + c;
  return r;
}

/** 干扰项候选池: 贴近正解 + 常见错算 */
function distractorPool(answer: number, op: string, a: number, b: number): number[] {
  const pool: number[] = [answer + 1, answer - 1, answer + 2, answer - 2, answer + 10, answer - 10];
  if (a >= 0) {
    if (op === '+') {
      pool.push(a - b);
    } else if (op === '-') {
      pool.push(a + b);
    } else if (op === '×') {
      pool.push(answer + a, answer - a, answer + b, answer - b);
    } else if (op === '÷') {
      pool.push(b, a - b, answer + 2);
    }
  }
  return pool;
}

/**
 * 生成 choices: 含正解、互不重复、全为非负整数, 长度 = cfg.choices (默认 4)。
 * 兜底用逐渐远离正解的邻值补满 (k 增长, answer+k 必正且唯一, 保证收敛)。
 */
export function makeChoices(answer: number, op: string, a: number, b: number, count: number): number[] {
  const n: number = count > 0 ? count : 4;
  const out: number[] = [];
  const used: Set<number> = new Set<number>();
  used.add(answer);
  const pool: number[] = shuffleNum(distractorPool(answer, op, a, b));
  for (let i: number = 0; i < pool.length; i++) {
    if (out.length >= n - 1) {
      break;
    }
    const c: number = pool[i];
    if (Number.isInteger(c) && c >= 0 && !used.has(c)) {
      used.add(c);
      out.push(c);
    }
  }
  let k: number = 1;
  while (out.length < n - 1) {
    const cands: number[] = [answer + k, answer - k];
    for (let i: number = 0; i < cands.length; i++) {
      if (out.length >= n - 1) {
        break;
      }
      const cand: number = cands[i];
      if (cand >= 0 && !used.has(cand)) {
        used.add(cand);
        out.push(cand);
      }
    }
    k++;
    if (k > 1000) {
      break; // 理论上到不了, 防御死循环
    }
  }
  const all: number[] = [answer];
  return shuffleNum(all.concat(out));
}

/** 生成一道题 */
export function genProblem(cfg: GenConfig): Problem {
  let raw: RawProblem;
  if (cfg.terms === 3) {
    raw = genThreeTerm(cfg);
  } else {
    const op: string = pick(cfg.ops);
    if (op === '+') {
      raw = genAdd(cfg);
    } else if (op === '-') {
      raw = genSub(cfg);
    } else if (op === '×') {
      raw = genMul(cfg);
    } else {
      raw = genDiv(cfg);
    }
  }
  const p: Problem = new Problem();
  p.text = raw.text;
  p.answer = raw.answer;
  p.op = raw.op;
  p.operands = raw.hasOperands ? [raw.a, raw.b] : [];
  const a: number = raw.hasOperands ? raw.a : -1;
  const b: number = raw.hasOperands ? raw.b : -1;
  p.choices = makeChoices(raw.answer, raw.op, a, b, cfg.choices);
  return p;
}

/**
 * 一关 count 道题, 用 text 做 key 去重; 题空间太小时兜底允许重复, 避免死循环。
 * @param fixed 错题重练: 直接用给定题集, 仅重生成 choices
 */
export function genLevelProblems(cfg: GenConfig, count: number, fixed: Problem[]): Problem[] {
  if (fixed.length > 0) {
    const out: Problem[] = [];
    for (let i: number = 0; i < fixed.length; i++) {
      const item: Problem = fixed[i];
      const a: number = item.operands.length > 0 ? item.operands[0] : -1;
      const b: number = item.operands.length > 1 ? item.operands[1] : -1;
      const p: Problem = new Problem();
      p.text = item.text;
      p.answer = item.answer;
      p.op = item.op;
      p.operands = item.operands.slice();
      p.choices = makeChoices(item.answer, item.op, a, b, cfg.choices);
      out.push(p);
    }
    return out;
  }
  const seen: Set<string> = new Set<string>();
  const out: Problem[] = [];
  let attempts: number = 0;
  const maxAttempts: number = count * 20;
  while (out.length < count && attempts < maxAttempts) {
    attempts++;
    const p: Problem = genProblem(cfg);
    if (seen.has(p.text)) {
      continue;
    }
    seen.add(p.text);
    out.push(p);
  }
  while (out.length < count) {
    out.push(genProblem(cfg)); // 兜底凑满
  }
  return out;
}
