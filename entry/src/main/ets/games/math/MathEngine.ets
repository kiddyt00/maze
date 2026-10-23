/**
 * 口算单关状态机 —— 移植自 kids-games/games/math/game.js。
 *
 * 状态机只输出"发生了什么"(通过 Handler 回调), 不直接改 UI:
 *  出题 → 答 → 即时反馈 → 前进 → 过关。
 * 这样页面只负责把回调映射成 @State, 逻辑本身可以单测。
 *
 * 与原实现一致的关键行为:
 *  - lenient 档答错「原题再来」, 不前进、不计错;
 *  - 非 lenient 档答错记入错题表, 结算后可「错题重练」;
 *  - 锁定窗口: 答对 750ms / 答错 1200ms 后自动前进, 期间挡掉连点;
 *  - 过关后 finished = true, 遗留点击直接丢弃 (防越界)。
 */
import { GenConfig, Problem, genLevelProblems } from './Problems';

export class MathLevelCfg {
  id: number = 1;
  name: string = '';
  count: number = 10;
  mode: string = 'choice';
  timer: string = '';
  combo: boolean = false;
  pictograph: boolean = false;
  lenient: boolean = false;
  starTime: number = 10;
  gen: GenConfig = new GenConfig();
}

/** 结算数据 (对应原 stats 对象) */
export class MathStats {
  diffKey: string = '';
  levelId: number = 1;
  levelName: string = '';
  total: number = 0;
  correct: number = 0;
  accuracy: number = 0;
  elapsed: number = 0;
  maxCombo: number = 0;
  timer: string = '';
  starTime: number = 10;
  stars: number = 1;
  wrongList: Problem[] = [];
  isRetry: boolean = false;
  levelCfg: MathLevelCfg = new MathLevelCfg();
}

/** 页面要实现的回调; 全部可选, 不实现的当作空操作 */
export interface MathHandler {
  /** 新的一题开始: 清空反馈、重画选项/图示、读题 */
  onProblem?: (p: Problem, index: number, count: number) => void;
  /** 答对了: given 是玩家点的选项 (键盘输入时为 null) */
  onRight?: (p: Problem, given: number, combo: number) => void;
  /** 答错了: correct 提示用, lenient 档不会走到结算错题表 */
  onWrong?: (p: Problem, given: number, lenient: boolean) => void;
  /** 连击数变化 (0 表示断了) */
  onCombo?: (combo: number) => void;
  /** 进度 */
  onProgress?: (done: number, total: number) => void;
  /** 每秒一次 */
  onTick?: (elapsedSec: number) => void;
  /** 过关 */
  onWin?: (stats: MathStats) => void;
}

export class MathGame {
  private diffKey: string = '';
  private cfg: MathLevelCfg = new MathLevelCfg();
  private handler: MathHandler = {};
  private problems: Problem[] = [];
  private index: number = 0;
  private correct: number = 0;
  private combo: number = 0;
  private maxCombo: number = 0;
  private wrongList: Problem[] = [];
  private elapsed: number = 0;
  private timerId: number = -1;
  private locked: boolean = false;
  private finished: boolean = false;
  private isRetry: boolean = false;
  /** 数字键盘的输入缓冲, 页面读它来显示 */
  buffer: string = '';

  /**
   * @param fixed 错题重练题集, 空数组表示正常闯关
   */
  constructor(diffKey: string, cfg: MathLevelCfg, handler: MathHandler, fixed: Problem[]) {
    this.diffKey = diffKey;
    this.cfg = cfg;
    this.handler = handler;
    this.isRetry = fixed.length > 0;
    const count: number = this.isRetry ? fixed.length : cfg.count;
    this.problems = genLevelProblems(cfg.gen, count, fixed);
  }

  start(): void {
    if (this.cfg.timer.length > 0) {
      this.startTimer();
    }
    this.renderProblem();
    this.emitProgress();
  }

  /** 页面销毁时务必调用, 清掉计时器 */
  destroy(): void {
    this.stopTimer();
  }

  current(): Problem | null {
    if (this.index < 0 || this.index >= this.problems.length) {
      return null;
    }
    return this.problems[this.index];
  }

  isFinished(): boolean {
    return this.finished;
  }

  isLocked(): boolean {
    return this.locked;
  }

  elapsedSec(): number {
    return this.elapsed;
  }

  wrongProblems(): Problem[] {
    return this.wrongList;
  }

  // ---------- 计时 ----------
  private startTimer(): void {
    this.stopTimer();
    this.timerId = setInterval((): void => {
      this.elapsed++;
      if (this.handler.onTick !== undefined) {
        this.handler.onTick(this.elapsed);
      }
    }, 1000);
  }

  private stopTimer(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  // ---------- 数字键盘 ----------
  /** 返回新的缓冲内容, 页面拿去显示 */
  pressKey(k: string): string {
    if (this.locked || this.finished) {
      return this.buffer;
    }
    if (k === 'del') {
      this.buffer = this.buffer.length === 0 ? '' : this.buffer.substring(0, this.buffer.length - 1);
    } else if (k === 'enter') {
      if (this.buffer.length > 0) {
        const given: number = parseInt(this.buffer, 10);
        this.submit(given);
      }
      return this.buffer;
    } else if (k.length === 1 && k >= '0' && k <= '9') {
      if (this.buffer.length < 4) {
        this.buffer += k;
      }
    }
    return this.buffer;
  }

  // ---------- 答题入口 ----------
  /** 选择题点选项 / 键盘回车都走这里 */
  submit(given: number): void {
    if (this.locked || this.finished) {
      return;
    }
    const p: Problem | null = this.current();
    if (p === null) {
      return; // 越界保护 (过关瞬间的遗留点击)
    }
    const right: boolean = given === p.answer;
    if (right) {
      this.correct++;
      this.combo++;
      this.maxCombo = Math.max(this.maxCombo, this.combo);
      if (this.handler.onRight !== undefined) {
        this.handler.onRight(p, given, this.combo);
      }
    } else {
      this.combo = 0;
      if (this.handler.onWrong !== undefined) {
        this.handler.onWrong(p, given, this.cfg.lenient);
      }
      if (!this.cfg.lenient) {
        this.wrongList.push(p.clone());
      }
    }
    this.emitCombo();

    if (!right && this.cfg.lenient) {
      // 宽容档: 原题再来, 不前进、不计错
      this.locked = true;
      setTimeout((): void => {
        this.locked = false;
        this.renderProblem();
      }, 1100);
      return;
    }

    this.locked = true;
    setTimeout((): void => {
      this.locked = false;
      this.next();
    }, right ? 750 : 1200);
  }

  private next(): void {
    this.index++;
    if (this.index >= this.problems.length) {
      this.win();
      return;
    }
    this.renderProblem();
    this.emitProgress();
  }

  private renderProblem(): void {
    const p: Problem | null = this.current();
    if (p === null) {
      return;
    }
    this.buffer = '';
    if (this.handler.onProblem !== undefined) {
      this.handler.onProblem(p, this.index, this.problems.length);
    }
  }

  private emitCombo(): void {
    if (this.handler.onCombo !== undefined) {
      this.handler.onCombo(this.cfg.combo ? this.combo : 0);
    }
  }

  private emitProgress(): void {
    if (this.handler.onProgress !== undefined) {
      this.handler.onProgress(this.index, this.problems.length);
    }
  }

  private win(): void {
    this.finished = true;
    this.stopTimer();
    const accuracy: number = this.problems.length > 0 ? this.correct / this.problems.length : 0;
    const s: MathStats = new MathStats();
    s.diffKey = this.diffKey;
    s.levelId = this.cfg.id;
    s.levelName = this.cfg.name;
    s.levelCfg = this.cfg;
    s.total = this.problems.length;
    s.correct = this.correct;
    s.accuracy = accuracy;
    s.elapsed = this.elapsed;
    s.maxCombo = this.maxCombo;
    s.timer = this.cfg.timer;
    s.starTime = this.cfg.starTime;
    s.wrongList = this.wrongList.slice();
    s.isRetry = this.isRetry;
    if (this.handler.onWin !== undefined) {
      this.handler.onWin(s);
    }
  }
}
