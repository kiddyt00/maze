/**
 * 记忆配对引擎 —— 移植自 kids-games/games/memory/engine.js。
 *
 * 引擎只懂卡片/配对/翻面/计步计时, 不碰 UI; 页面通过 Handler 回调驱动渲染。
 * 发牌/洗牌/判定都是纯逻辑。
 *
 * 不变式 (与原实现一致):
 *  - 每对拆两张卡打同一个 pairKey (用抽取索引, 绝不用卡面文字当 key);
 *  - 点同一张牌两次无效;
 *  - 比对两张牌期间 locked = true, 回翻动画结束后由页面调 clearMismatch() 解锁;
 *  - 配对成功立即解锁 (无需回翻), 连击 +1; 失败连击清零;
 *  - 计时只在高档开启, 第一次翻牌才开始计时。
 */
import { Face, Pair, Theme } from './Themes';

export class MemTier {
  key: string = '';
  emoji: string = '';
  label: string = '';
  cols: number = 3;
  rows: number = 4;
  pairs: number = 6;
  timer: boolean = false;
  /** 翻牌时是否读出卡面 */
  speakOnFlip: boolean = true;
  /** 低龄档配对后留亮; 高档配对后消失腾位 */
  keepLit: boolean = true;
  /** 回翻延迟 (ms) */
  flipMs: number = 850;
  desc: string = '';

  constructor(key: string, emoji: string, label: string, cols: number, rows: number, pairs: number) {
    this.key = key;
    this.emoji = emoji;
    this.label = label;
    this.cols = cols;
    this.rows = rows;
    this.pairs = pairs;
  }
}

/** 一张牌 */
export class MemCard {
  uid: string = '';
  pairKey: string = '';
  face: Face = new Face();
  say: string = '';
  matched: boolean = false;
}

export class MemStats {
  themeId: string = '';
  themeName: string = '';
  tierKey: string = '';
  cols: number = 0;
  rows: number = 0;
  pairs: number = 0;
  steps: number = 0;
  maxCombo: number = 0;
  elapsed: number = 0;
  timer: boolean = false;
}

export class MemSnapshot {
  steps: number = 0;
  combo: number = 0;
  matchedCount: number = 0;
  totalPairs: number = 0;
}

/** 洗牌, 只用 Math.random (与原 shuffle 一致) */
export function shuffleGeneric<T>(arr: T[]): T[] {
  const a: T[] = arr.slice();
  for (let i: number = a.length - 1; i > 0; i--) {
    const j: number = Math.floor(Math.random() * (i + 1));
    const t: T = a[i];
    a[i] = a[j];
    a[j] = t;
  }
  return a;
}

export function pickN<T>(arr: T[], n: number): T[] {
  return shuffleGeneric<T>(arr).slice(0, n);
}

/** 从 theme.pairs + tier 生成本局卡片数组 (已洗牌) */
export function buildDeck(theme: Theme, tier: MemTier): MemCard[] {
  const slots: number = tier.cols * tier.rows;
  const usePairs: number = Math.min(tier.pairs, Math.floor(slots / 2), theme.pairs.length);
  const picked: Pair[] = pickN<Pair>(theme.pairs, usePairs);
  const deck: MemCard[] = [];
  for (let i: number = 0; i < picked.length; i++) {
    const pair: Pair = picked[i];
    const pairKey: string = 'pk' + i;
    const faceA: Face = theme.match === 'identical' ? pair.card : pair.a;
    const faceB: Face = theme.match === 'identical' ? pair.card : pair.b;
    const say: string = pair.say;
    const ca: MemCard = new MemCard();
    ca.uid = pairKey + '-a';
    ca.pairKey = pairKey;
    ca.face = faceA;
    ca.say = say;
    deck.push(ca);
    const cb: MemCard = new MemCard();
    cb.uid = pairKey + '-b';
    cb.pairKey = pairKey;
    cb.face = faceB;
    cb.say = say;
    deck.push(cb);
  }
  return shuffleGeneric<MemCard>(deck);
}

export interface MemHandler {
  onBuild?: (cards: MemCard[]) => void;
  onFlip?: (card: MemCard, first: boolean) => void;
  onMatch?: (a: MemCard, b: MemCard, say: string, combo: number) => void;
  onMismatch?: (a: MemCard, b: MemCard) => void;
  onTick?: (elapsedSec: number) => void;
  onStats?: (snap: MemSnapshot) => void;
  onWin?: (stats: MemStats) => void;
}

export class MemoryGame {
  private theme: Theme;
  private tier: MemTier;
  private cb: MemHandler;
  cards: MemCard[] = [];
  private byUid: Map<string, MemCard> = new Map<string, MemCard>();
  private first: MemCard | null = null;
  private locked: boolean = false;
  private matchedCount: number = 0;
  private totalPairs: number = 0;
  private steps: number = 0;
  private combo: number = 0;
  private maxCombo: number = 0;
  private elapsed: number = 0;
  private timerId: number = -1;
  private started: boolean = false;

  constructor(theme: Theme, tier: MemTier, cb: MemHandler) {
    this.theme = theme;
    this.tier = tier;
    this.cb = cb;
  }

  build(): void {
    this.stopTimer();
    this.cards = buildDeck(this.theme, this.tier);
    this.byUid = new Map<string, MemCard>();
    for (let i: number = 0; i < this.cards.length; i++) {
      this.byUid.set(this.cards[i].uid, this.cards[i]);
    }
    this.totalPairs = this.cards.length / 2;
    this.first = null;
    this.locked = false;
    this.matchedCount = 0;
    this.steps = 0;
    this.combo = 0;
    this.maxCombo = 0;
    this.elapsed = 0;
    this.started = false;
    if (this.cb.onBuild !== undefined) {
      this.cb.onBuild(this.cards);
    }
  }

  /** 玩家翻一张牌 */
  flip(uid: string): void {
    if (this.locked) {
      return;
    }
    const c: MemCard | undefined = this.byUid.get(uid);
    if (c === undefined || c.matched) {
      return;
    }
    if (this.first !== null && this.first.uid === uid) {
      return; // 不能点同一张两次
    }
    if (!this.started) {
      this.started = true;
      if (this.tier.timer) {
        this.startTimer();
      }
    }
    if (this.first === null) {
      this.first = c;
      if (this.cb.onFlip !== undefined) {
        this.cb.onFlip(c, true);
      }
      return;
    }
    // 第二张
    if (this.cb.onFlip !== undefined) {
      this.cb.onFlip(c, false);
    }
    this.steps++;
    if (this.cb.onStats !== undefined) {
      this.cb.onStats(this.snapshot());
    }
    this.locked = true;
    const f: MemCard = this.first;
    if (f.pairKey === c.pairKey && f.uid !== c.uid) {
      this.resolveMatch(f, c);
    } else {
      this.resolveMismatch(f, c);
    }
  }

  private resolveMatch(a: MemCard, b: MemCard): void {
    a.matched = true;
    b.matched = true;
    this.matchedCount++;
    this.combo++;
    this.maxCombo = Math.max(this.maxCombo, this.combo);
    this.first = null;
    this.locked = false; // 成功即时解锁 (无需回翻)
    if (this.cb.onMatch !== undefined) {
      this.cb.onMatch(a, b, a.say, this.combo);
    }
    if (this.matchedCount === this.totalPairs) {
      this.win();
    }
  }

  private resolveMismatch(a: MemCard, b: MemCard): void {
    this.combo = 0;
    if (this.cb.onMismatch !== undefined) {
      this.cb.onMismatch(a, b);
    }
    // 回翻延时归页面, 动画结束后调 clearMismatch() 解锁
  }

  /** 页面在回翻动画结束后调用 */
  clearMismatch(): void {
    this.first = null;
    this.locked = false;
  }

  private win(): void {
    this.stopTimer();
    if (this.cb.onWin !== undefined) {
      this.cb.onWin(this.stats());
    }
  }

  stats(): MemStats {
    const s: MemStats = new MemStats();
    s.themeId = this.theme.id;
    s.themeName = this.theme.name;
    s.tierKey = this.tier.key;
    s.cols = this.tier.cols;
    s.rows = this.tier.rows;
    s.pairs = this.totalPairs;
    s.steps = this.steps;
    s.maxCombo = this.maxCombo;
    s.elapsed = this.elapsed;
    s.timer = this.tier.timer;
    return s;
  }

  snapshot(): MemSnapshot {
    const s: MemSnapshot = new MemSnapshot();
    s.steps = this.steps;
    s.combo = this.combo;
    s.matchedCount = this.matchedCount;
    s.totalPairs = this.totalPairs;
    return s;
  }

  isMatched(uid: string): boolean {
    const c: MemCard | undefined = this.byUid.get(uid);
    return c === undefined ? false : c.matched;
  }

  destroy(): void {
    this.stopTimer();
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

/** 三档难度 (与原 main.js 的 TIERS 一致) */
export function buildTiers(): MemTier[] {
  const easy: MemTier = new MemTier('easy', '🐣', '启蒙', 3, 4, 6);
  easy.timer = false;
  easy.speakOnFlip = true;
  easy.keepLit = true;
  easy.flipMs = 850;
  easy.desc = '3×4 · 6 对 · 留亮不计时';

  const medium: MemTier = new MemTier('medium', '🦊', '进阶', 4, 4, 8);
  medium.timer = false;
  medium.speakOnFlip = true;
  medium.keepLit = true;
  medium.flipMs = 800;
  medium.desc = '4×4 · 8 对 · 记步数';

  const hard: MemTier = new MemTier('hard', '🐉', '挑战', 5, 6, 15);
  hard.timer = true;
  hard.speakOnFlip = false;
  hard.keepLit = false;
  hard.flipMs = 550;
  hard.desc = '5×6 · 15 对 · 计时+消失腾位';

  return [easy, medium, hard];
}
