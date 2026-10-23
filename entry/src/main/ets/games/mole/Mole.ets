/**
 * 打地鼠口算 —— 移植自 kids-games/games/mole。
 *
 * 玩法: 上方一个算式, 6 或 9 个地洞里冒出头戴数字的地鼠,
 * 拍中举着正确答案的那只就得分, 限时 60 秒累计分, 连击越高越威风。
 *
 * 题目直接复用 games/math/Problems.ets 的生成器 (与原实现一致),
 * 这里只负责"把正解+干扰项分配到地洞"与限时计分。
 */
import { GenConfig, Problem, genProblem } from '../math/Problems';

/** 一个地洞里的地鼠 */
export class MoleSlot {
  /** 洞里是哪只数字地鼠; -1 表示这个洞空着 */
  value: number = -1;
  isAnswer: boolean = false;
  /** 是否冒头 */
  up: boolean = false;
  /** 刚被拍中 */
  bonk: boolean = false;
  /** 刚拍错 */
  miss: boolean = false;
}

export class MoleDiff {
  key: string = '';
  emoji: string = '';
  label: string = '';
  desc: string = '';
  holes: number = 6;
  /** 地鼠换洞的间隔 ms */
  popMs: number = 1500;
  /** 一局时长 (秒) */
  duration: number = 60;
  /** 是否读题 (只在最易档开) */
  speak: boolean = false;
  gen: GenConfig = new GenConfig();

  constructor(key: string, emoji: string, label: string, desc: string,
    holes: number, popMs: number, duration: number, speak: boolean) {
    this.key = key;
    this.emoji = emoji;
    this.label = label;
    this.desc = desc;
    this.holes = holes;
    this.popMs = popMs;
    this.duration = duration;
    this.speak = speak;
  }
}

function genCfg(ops: string[], max: number, allowCarry: boolean): GenConfig {
  const g: GenConfig = new GenConfig();
  g.ops = ops;
  g.max = max;
  g.allowCarry = allowCarry;
  g.choices = 4;
  return g;
}

/** 4 档难度, 节奏由 popMs 控制 (越小越快) */
export function buildDiffs(): MoleDiff[] {
  const m1: MoleDiff = new MoleDiff('m1', '🐣', '启蒙', '10 以内加减 · 慢', 6, 1500, 60, true);
  m1.gen = genCfg(['+', '-'], 10, false);

  const m2: MoleDiff = new MoleDiff('m2', '🦊', '进阶', '100 以内加减 · 中', 6, 1200, 60, false);
  m2.gen = genCfg(['+', '-'], 100, true);

  const m3: MoleDiff = new MoleDiff('m3', '🐯', '熟练', '表内乘除 · 快', 6, 1000, 60, false);
  m3.gen = genCfg(['×', '÷'], 81, true);
  m3.gen.mulMax = 9;
  m3.gen.divMax = 9;

  const m4: MoleDiff = new MoleDiff('m4', '🐉', '挑战', '四则混合 · 极快', 9, 850, 60, false);
  m4.gen = genCfg(['+', '-', '×', '÷'], 99, true);
  m4.gen.mulMax = 9;
  m4.gen.divMax = 9;

  return [m1, m2, m3, m4];
}

/** 打乱 [0..holes-1] 取前 k 个不同洞号 */
function pickHoles(holes: number, k: number): number[] {
  const a: number[] = [];
  for (let i: number = 0; i < holes; i++) {
    a.push(i);
  }
  for (let i: number = a.length - 1; i > 0; i--) {
    const j: number = Math.floor(Math.random() * (i + 1));
    const t: number = a[i];
    a[i] = a[j];
    a[j] = t;
  }
  return a.slice(0, k);
}

export class MoleStats {
  diffKey: string = '';
  score: number = 0;
  maxCombo: number = 0;
}

export interface MoleHandler {
  /** 新一题: 算式文本 + 当前每个洞该显示什么 */
  onRound?: (text: string, slots: MoleSlot[]) => void;
  onScore?: (score: number, combo: number) => void;
  onTick?: (timeLeft: number) => void;
  onHit?: (hole: number) => void;
  onMiss?: (hole: number) => void;
  onEnd?: (stats: MoleStats) => void;
}

export class MoleGame {
  private cfg: MoleDiff;
  private cb: MoleHandler;
  private score: number = 0;
  private combo: number = 0;
  private maxCombo: number = 0;
  private timeLeft: number = 60;
  private finished: boolean = false;
  private countdownId: number = -1;
  private reshuffleId: number = -1;
  /** 当前题: 正确答案 + 每题四个候选数字 */
  private answer: number = 0;
  private problemText: string = '';
  private curValues: number[] = [];
  /** 洞号 -> 当前地鼠 */
  holeMoles: MoleSlot[] = [];

  constructor(cfg: MoleDiff, cb: MoleHandler) {
    this.cfg = cfg;
    this.cb = cb;
    this.timeLeft = cfg.duration;
    for (let i: number = 0; i < cfg.holes; i++) {
      this.holeMoles.push(new MoleSlot());
    }
  }

  start(): void {
    this.score = 0;
    this.combo = 0;
    this.maxCombo = 0;
    this.timeLeft = this.cfg.duration;
    this.finished = false;
    this.newRound();
    if (this.cb.onTick !== undefined) {
      this.cb.onTick(this.timeLeft);
    }
    this.countdownId = setInterval((): void => {
      this.tick();
    }, 1000);
    this.reshuffleId = setInterval((): void => {
      if (!this.finished) {
        this.placeAtRandomHoles();
      }
    }, this.cfg.popMs);
  }

  destroy(): void {
    this.stop();
  }

  isFinished(): boolean {
    return this.finished;
  }

  private stop(): void {
    if (this.countdownId >= 0) {
      clearInterval(this.countdownId);
      this.countdownId = -1;
    }
    if (this.reshuffleId >= 0) {
      clearInterval(this.reshuffleId);
      this.reshuffleId = -1;
    }
  }

  private tick(): void {
    this.timeLeft--;
    if (this.cb.onTick !== undefined) {
      this.cb.onTick(Math.max(0, this.timeLeft));
    }
    if (this.timeLeft <= 0) {
      this.end();
    }
  }

  private newRound(): void {
    const p: Problem = genProblem(this.cfg.gen);
    this.answer = p.answer;
    this.problemText = p.text;
    this.curValues = p.choices.slice();
    this.placeAtRandomHoles();
    if (this.cfg.speak && this.cb.onRound !== undefined) {
      // 读题交给页面 (它持有 Voice), 这里只把算式发出去
      this.cb.onRound(p.text, this.snapshot());
    }
  }

  /** 把当前 4 个数字随机分配到不同洞 */
  private placeAtRandomHoles(): void {
    const holes: number[] = pickHoles(this.cfg.holes, this.curValues.length);
    for (let i: number = 0; i < this.holeMoles.length; i++) {
      this.holeMoles[i].up = false;
      this.holeMoles[i].bonk = false;
      this.holeMoles[i].miss = false;
      this.holeMoles[i].value = -1;
      this.holeMoles[i].isAnswer = false;
    }
    for (let i: number = 0; i < this.curValues.length; i++) {
      const hole: number = holes[i];
      const v: number = this.curValues[i];
      this.holeMoles[hole].value = v;
      this.holeMoles[hole].isAnswer = v === this.answer;
      this.holeMoles[hole].up = true;
    }
    if (this.cb.onRound !== undefined) {
      this.cb.onRound(this.problemText, this.snapshot());
    }
  }

  private snapshot(): MoleSlot[] {
    const out: MoleSlot[] = [];
    for (let i: number = 0; i < this.holeMoles.length; i++) {
      const s: MoleSlot = new MoleSlot();
      const src: MoleSlot = this.holeMoles[i];
      s.value = src.value;
      s.isAnswer = src.isAnswer;
      s.up = src.up;
      s.bonk = src.bonk;
      s.miss = src.miss;
      out.push(s);
    }
    return out;
  }

  /** 拍了某个洞; 点空了洞不算 */
  tapHole(hole: number): void {
    if (this.finished || hole < 0 || hole >= this.holeMoles.length) {
      return;
    }
    const m: MoleSlot = this.holeMoles[hole];
    if (!m.up) {
      return;
    }
    if (m.isAnswer) {
      this.score++;
      this.combo++;
      this.maxCombo = Math.max(this.maxCombo, this.combo);
      if (this.cb.onScore !== undefined) {
        this.cb.onScore(this.score, this.combo);
      }
      if (this.cb.onHit !== undefined) {
        this.cb.onHit(hole);
      }
      this.newRound();
    } else {
      this.combo = 0;
      if (this.cb.onScore !== undefined) {
        this.cb.onScore(this.score, this.combo);
      }
      if (this.cb.onMiss !== undefined) {
        this.cb.onMiss(hole);
      }
    }
  }

  private end(): void {
    this.finished = true;
    this.stop();
    for (let i: number = 0; i < this.holeMoles.length; i++) {
      this.holeMoles[i].up = false;
    }
    if (this.cb.onEnd !== undefined) {
      const s: MoleStats = new MoleStats();
      s.diffKey = this.cfg.key;
      s.score = this.score;
      s.maxCombo = this.maxCombo;
      this.cb.onEnd(s);
    }
  }
}
