/**
 * 打地鼠 (星芽版) —— 移植自 kids-learning-games/src/scenes/WhackAMoleScene.ts。
 *
 * 与原实现对齐的规则 (数值全部来自原 MOLE_DETAILS / rollMoleKind / whack):
 *  - 9 个洞, 地鼠按间隔随机冒头, 同时最多 2 只 (最后 22 秒放宽到 3 只);
 *  - 五种地鼠: 普通(+1) / 金鼠(+3) / 头盔鼠(敲两下) / 时钟鼠(+1 且加 3 秒) / 炸弹(惩罚);
 *  - 连击倍率 1 + floor(combo / 4); 敲空、敲炸弹、地鼠溜走都会断连击;
 *  - 一局 45 秒, 时钟鼠最多把时间抬到 60 秒;
 *  - 三档难度只改地鼠停留时长与冒头频率, 不改时长与分值。
 *
 * 原实现是 Phaser 场景 (tween / camera shake / 粒子), 这里用 ArkTS 状态 + 定时器
 * 重做同样的手感: 地鼠用"升起进度"插值, 命中用缩放反馈, 连击用文字徽标。
 */
import { genRandom } from './Random';

/** 五种地鼠 */
export const KIND_NORMAL: string = 'normal';
export const KIND_GOLD: string = 'gold';
export const KIND_HELMET: string = 'helmet';
export const KIND_BOMB: string = 'bomb';
export const KIND_CLOCK: string = 'clock';

export class MoleKindInfo {
  kind: string = KIND_NORMAL;
  label: string = '地鼠';
  emoji: string = '🐹';
  /** 底色 (原 color 值转十六进制) */
  color: string = '#A96D3E';
  /** 敲中得分 */
  value: number = 1;
  /** 需要敲几下 */
  health: number = 1;
  /** 停留秒数 */
  duration: number = 1.55;

  constructor(kind: string, label: string, emoji: string, color: string,
    value: number, health: number, duration: number) {
    this.kind = kind;
    this.label = label;
    this.emoji = emoji;
    this.color = color;
    this.value = value;
    this.health = health;
    this.duration = duration;
  }
}

/** 原 MOLE_DETAILS 表 */
export function kindInfo(kind: string): MoleKindInfo {
  if (kind === KIND_GOLD) {
    return new MoleKindInfo(KIND_GOLD, '金鼠', '🐹', '#F5C84B', 3, 1, 1.1);
  }
  if (kind === KIND_HELMET) {
    return new MoleKindInfo(KIND_HELMET, '头盔鼠', '🐹', '#8D9AA6', 2, 2, 1.8);
  }
  if (kind === KIND_BOMB) {
    return new MoleKindInfo(KIND_BOMB, '炸弹', '💣', '#3F4650', 0, 1, 1.45);
  }
  if (kind === KIND_CLOCK) {
    return new MoleKindInfo(KIND_CLOCK, '时钟鼠', '🐹', '#65B7DE', 1, 1, 1.35);
  }
  return new MoleKindInfo(KIND_NORMAL, '地鼠', '🐹', '#A96D3E', 1, 1, 1.55);
}

/** 按原 rollMoleKind 的概率抽一只 */
export function rollMoleKind(r: number): string {
  if (r < 0.08) {
    return KIND_BOMB;
  }
  if (r < 0.19) {
    return KIND_GOLD;
  }
  if (r < 0.30) {
    return KIND_HELMET;
  }
  if (r < 0.38) {
    return KIND_CLOCK;
  }
  return KIND_NORMAL;
}

/** 地鼠状态 */
export const ST_IDLE: string = 'idle';
export const ST_RISING: string = 'rising';
export const ST_UP: string = 'up';
export const ST_HIDING: string = 'hiding';

/** 一个洞 */
export class MoleSlot {
  index: number = 0;
  state: string = ST_IDLE;
  stateTime: number = 0;
  /** 这只地鼠停留多久 (已按难度与随机抖动算好) */
  activeDuration: number = 0;
  kind: string = '';
  health: number = 0;
  /** 升起进度 0..1, UI 直接用来做位移/透明度 */
  rise: number = 0;
  /** 命中后的缩放反馈 0..1 (1 表示刚被敲) */
  hitFlash: number = 0;
}

export class MoleStats {
  score: number = 0;
  maxCombo: number = 0;
  hits: number = 0;
  attempts: number = 0;
  difficulty: string = 'normal';
}

export interface MoleHandler {
  onSlots?: (slots: MoleSlot[]) => void;
  onHud?: (score: number, timeLeft: number, combo: number, lives: number, accuracy: number) => void;
  onFeedback?: (text: string, good: boolean) => void;
  onEnd?: (stats: MoleStats) => void;
}

/**
 * 一局游戏。所有状态变更都通过 tick(dt) 推进, 页面每 50ms 调一次。
 * 这样不依赖任何动画框架, 也方便单测。
 */
export class MoleRound {
  private cb: MoleHandler;
  private difficulty: string = 'normal';
  private roundDuration: number = 45;
  slots: MoleSlot[] = [];
  private score: number = 0;
  private combo: number = 0;
  private maxCombo: number = 0;
  private timeLeft: number = 45;
  private spawnTimer: number = 0.6;
  private attempts: number = 0;
  private hits: number = 0;
  private lives: number = 3;
  private ended: boolean = false;

  constructor(cb: MoleHandler) {
    this.cb = cb;
    for (let i: number = 0; i < 9; i++) {
      const s: MoleSlot = new MoleSlot();
      s.index = i;
      this.slots.push(s);
    }
  }

  start(difficulty: string): void {
    this.difficulty = difficulty;
    this.score = 0;
    this.combo = 0;
    this.maxCombo = 0;
    this.timeLeft = this.roundDuration;
    this.spawnTimer = 0.6;
    this.attempts = 0;
    this.hits = 0;
    this.lives = 3;
    this.ended = false;
    for (let i: number = 0; i < this.slots.length; i++) {
      this.resetSlot(this.slots[i]);
    }
    this.emitSlots();
    this.emitHud();
  }

  isEnded(): boolean {
    return this.ended;
  }

  timeRemaining(): number {
    return this.timeLeft;
  }

  /** 页面每帧调用; dt 单位是秒 */
  tick(dt: number): void {
    if (this.ended) {
      return;
    }
    this.timeLeft = Math.max(0, this.timeLeft - dt);
    this.spawnTimer -= dt;
    for (let i: number = 0; i < this.slots.length; i++) {
      this.updateSlot(this.slots[i], dt);
    }
    if (this.spawnTimer <= 0) {
      this.spawnMole();
    }
    this.emitHud();
    if (this.timeLeft <= 0) {
      this.finish();
    }
  }

  private updateSlot(slot: MoleSlot, dt: number): void {
    if (slot.hitFlash > 0) {
      slot.hitFlash = Math.max(0, slot.hitFlash - dt * 5);
    }
    if (slot.state === ST_IDLE) {
      return;
    }
    slot.stateTime += dt;
    if (slot.state === ST_RISING) {
      const progress: number = clamp(slot.stateTime / 0.16, 0, 1);
      slot.rise = progress;
      if (progress >= 1) {
        slot.state = ST_UP;
        slot.stateTime = 0;
      }
      return;
    }
    if (slot.state === ST_UP) {
      slot.rise = 1;
      if (slot.stateTime >= slot.activeDuration) {
        // 地鼠自己溜走: 不是炸弹才断连击 (与原实现一致)
        if (slot.kind !== KIND_BOMB) {
          this.combo = 0;
        }
        slot.state = ST_HIDING;
        slot.stateTime = 0;
      }
      return;
    }
    // hiding
    const progress: number = clamp(slot.stateTime / 0.18, 0, 1);
    slot.rise = 1 - progress;
    if (progress >= 1) {
      this.resetSlot(slot);
    }
  }

  private resetSlot(slot: MoleSlot): void {
    slot.state = ST_IDLE;
    slot.stateTime = 0;
    slot.kind = '';
    slot.health = 0;
    slot.rise = 0;
    slot.hitFlash = 0;
  }

  private spawnMole(): void {
    if (this.ended) {
      return;
    }
    let active: number = 0;
    for (let i: number = 0; i < this.slots.length; i++) {
      if (this.slots[i].state !== ST_IDLE) {
        active++;
      }
    }
    // 最后 22 秒允许 3 只同上
    const maxActive: number = this.timeLeft < 22 ? 3 : 2;
    if (active < maxActive) {
      const free: MoleSlot[] = [];
      for (let i: number = 0; i < this.slots.length; i++) {
        if (this.slots[i].state === ST_IDLE) {
          free.push(this.slots[i]);
        }
      }
      if (free.length > 0) {
        const slot: MoleSlot = free[Math.floor(genRandom() * free.length)];
        const kind: string = rollMoleKind(genRandom());
        const info: MoleKindInfo = kindInfo(kind);
        slot.kind = kind;
        slot.health = info.health;
        slot.activeDuration = info.duration * (0.86 + genRandom() * 0.26);
        slot.state = ST_RISING;
        slot.stateTime = 0;
        slot.rise = 0;
      }
    }
    // 节奏: 越到后面越快; 难度只改倍率
    let pace: number = 0.86;
    if (this.timeLeft < this.roundDuration * 0.4) {
      pace = 0.48;
    } else if (this.timeLeft < this.roundDuration * 0.72) {
      pace = 0.66;
    }
    const mul: number = this.difficulty === 'easy' ? 1.24 : (this.difficulty === 'hard' ? 0.7 : 1);
    this.spawnTimer = (pace + genRandom() * 0.26) * mul;
    if (this.spawnTimer < pace * mul) {
      this.spawnTimer = pace * mul;
    }
  }

  /**
   * 敲某个洞。返回提示文案由 cb.onFeedback 发出。
   * 与原 whack() 完全对应。
   */
  whack(index: number): void {
    if (this.ended || index < 0 || index >= this.slots.length) {
      return;
    }
    this.attempts++;
    const slot: MoleSlot = this.slots[index];
    // 地鼠没冒头: 断连击, 不罚分
    if (slot.state !== ST_RISING && slot.state !== ST_UP || slot.kind.length === 0) {
      this.combo = 0;
      this.feedback('慢一点，等地鼠冒头再敲。', false);
      this.emitHud();
      return;
    }
    if (slot.kind === KIND_BOMB) {
      this.combo = 0;
      this.lives = Math.max(0, this.lives - 1);
      this.feedback('小心炸弹，没关系，继续敲！', false);
      this.hideSlot(slot, true);
      this.emitHud();
      return;
    }
    slot.health--;
    this.hits++;
    slot.hitFlash = 1;
    if (slot.health > 0) {
      this.feedback('头盔裂开啦，再敲一下！', true);
      this.emitHud();
      return;
    }
    const info: MoleKindInfo = kindInfo(slot.kind);
    this.combo++;
    this.maxCombo = Math.max(this.maxCombo, this.combo);
    const multiplier: number = 1 + Math.floor(this.combo / 4);
    const gained: number = info.value * multiplier;
    this.score += gained;
    if (slot.kind === KIND_CLOCK) {
      this.timeLeft = Math.min(60, this.timeLeft + 3);
      this.feedback('+3 秒，继续加油！', true);
    } else if (slot.kind === KIND_GOLD) {
      this.feedback('金鼠！+' + gained + ' 星芽', true);
    } else if (this.combo >= 3) {
      this.feedback(this.combo + ' 连击！+' + gained, true);
    } else {
      this.feedback('命中！+' + gained, true);
    }
    this.hideSlot(slot, false);
    this.emitHud();
  }

  /** 敲在空地上 (原 createPlayArea 的 missAttempt) */
  missAttempt(): void {
    if (this.ended) {
      return;
    }
    this.attempts++;
    this.combo = 0;
    this.feedback('看准洞口再敲！', false);
    this.emitHud();
  }

  private hideSlot(slot: MoleSlot, fast: boolean): void {
    slot.state = ST_HIDING;
    slot.stateTime = fast ? 0.08 : 0;
  }

  private finish(): void {
    this.ended = true;
    if (this.cb.onEnd !== undefined) {
      const s: MoleStats = new MoleStats();
      s.score = this.score;
      s.maxCombo = this.maxCombo;
      s.hits = this.hits;
      s.attempts = this.attempts;
      s.difficulty = this.difficulty;
      this.cb.onEnd(s);
    }
  }

  private accuracy(): number {
    if (this.attempts === 0) {
      return 100;
    }
    return Math.round((this.hits * 100) / this.attempts);
  }

  private feedback(text: string, good: boolean): void {
    if (this.cb.onFeedback !== undefined) {
      this.cb.onFeedback(text, good);
    }
  }

  private emitSlots(): void {
    if (this.cb.onSlots !== undefined) {
      // 传副本, 避免 UI 直接改到内部状态
      const copy: MoleSlot[] = [];
      for (let i: number = 0; i < this.slots.length; i++) {
        const src: MoleSlot = this.slots[i];
        const d: MoleSlot = new MoleSlot();
        d.index = src.index;
        d.state = src.state;
        d.stateTime = src.stateTime;
        d.activeDuration = src.activeDuration;
        d.kind = src.kind;
        d.health = src.health;
        d.rise = src.rise;
        d.hitFlash = src.hitFlash;
        copy.push(d);
      }
      this.cb.onSlots(copy);
    }
  }

  private emitHud(): void {
    this.emitSlots();
    if (this.cb.onHud !== undefined) {
      this.cb.onHud(this.score, this.timeLeft, this.combo, this.lives, this.accuracy());
    }
  }
}

function clamp(v: number, lo: number, hi: number): number {
  if (v < lo) {
    return lo;
  }
  return v > hi ? hi : v;
}
