/**
 * 游戏盒共用存档 —— 对应 kids-games 的 core/progress.js。
 *
 * 原实现的语义保持不变:
 *  - 星星 / 正确率 / 连击取 max, 用时取 min;
 *  - 最少步数取 min, 最短用时取 min;
 *  - 最高分取 max;
 *  - 通关后解锁下一关;
 *  - 设置只有两项: 静音 / 读题(默认都开)。
 *
 * 差异: 浏览器 localStorage 换成 @ohos.data.preferences (数据同样不出设备),
 * 所有读写都 try/catch 静默降级 —— 存档坏了游戏照样能玩。
 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0001;
const TAG: string = 'GameBox';
const STORE_NAME: string = 'kg_progress';

/** 每关一条记录 (口算) */
export class MathRecord {
  stars: number = 0;
  bestAccuracy: number = 0;
  bestTime: number = -1; // -1 = 没记录过
  maxCombo: number = 0;
  plays: number = 0;
}

export class MathDiffData {
  unlockedLevel: number = 1;
  /** key 是关号字符串 ("1"/"2"/"3"), 便于直接 JSON 序列化 */
  levels: Record<string, MathRecord> = {};
}

/** 翻翻乐 / 舒尔特 / 打地鼠的纪录都用这一条 */
export class BestRecord {
  steps: number = -1;
  time: number = -1;
  score: number = -1;
}

/** 结算回执: 是否破了纪录, 供 UI 标「新纪录!」 */
export class RecordResult {
  newRecord: boolean = false;
  newStepsRecord: boolean = false;
  newTimeRecord: boolean = false;
}

class Settings {
  muted: boolean = false;
  speakRead: boolean = true;
}

/** 内部用: 把 preferences 里读出来的 JSON 字符串还原成对象, 失败给 null */
function parseOrNull<T>(raw: string): T | null {
  if (raw.length === 0) {
    return null;
  }
  try {
    return JSON.parse(raw) as T;
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'progress json broken, fallback to empty');
    return null;
  }
}

export class ProgressStore {
  private prefs: preferences.Preferences | null = null;
  private ready: boolean = false;

  /** 老接口保留: 内部按需懒加载 preferences */
  init(context: common.UIAbilityContext): void {
    if (this.ready) {
      return;
    }
    try {
      const opt: preferences.Options = { name: STORE_NAME };
      this.prefs = preferences.getPreferencesSync(context, opt);
      this.ready = true;
    } catch (e) {
      const err: Error = e as Error;
      hilog.error(DOMAIN, TAG, 'open progress store failed: %{public}s', err.message);
      this.prefs = null;
    }
  }

  private readJson(key: string): string {
    if (this.prefs === null) {
      return '';
    }
    try {
      const v: preferences.ValueType = this.prefs.getSync(key, '');
      return typeof v === 'string' ? v as string : '';
    } catch (e) {
      return '';
    }
  }

  private writeJson(key: string, value: string): void {
    if (this.prefs === null) {
      return;
    }
    try {
      this.prefs.putSync(key, value);
      this.prefs.flush();
    } catch (e) {
      const err: Error = e as Error;
      hilog.error(DOMAIN, TAG, 'save progress failed: %{public}s', err.message);
    }
  }

  // ===================== 口算: 星星 / 解锁 =====================

  /** 某档某关的记录, 没打过返回 null */
  getMathLevel(diff: string, levelId: number): MathRecord | null {
    const all: Record<string, MathDiffData> | null =
      parseOrNull<Record<string, MathDiffData>>(this.readJson('math'));
    if (all === null) {
      return null;
    }
    const d: MathDiffData = all[diff];
    if (d === undefined || d === null) {
      return null;
    }
    const levels: Record<string, MathRecord> = d.levels;
    if (levels === undefined || levels === null) {
      return null;
    }
    const rec: MathRecord = levels[String(levelId)];
    return rec === undefined ? null : rec;
  }

  /** 第 1 关恒解锁, 其余看 unlockedLevel */
  isMathUnlocked(diff: string, levelId: number): boolean {
    if (levelId <= 1) {
      return true;
    }
    const all: Record<string, MathDiffData> | null =
      parseOrNull<Record<string, MathDiffData>>(this.readJson('math'));
    if (all === null) {
      return false;
    }
    const d: MathDiffData = all[diff];
    if (d === undefined || d === null) {
      return false;
    }
    return levelId <= d.unlockedLevel;
  }

  /** 某档累计星星 (大厅/难度卡显示 ⭐ 5/9) */
  mathStars(diff: string, levelIds: number[]): number {
    let sum: number = 0;
    for (let i: number = 0; i < levelIds.length; i++) {
      const rec: MathRecord | null = this.getMathLevel(diff, levelIds[i]);
      if (rec !== null) {
        sum += rec.stars;
      }
    }
    return sum;
  }

  /**
   * 过关后调用: 星星/正确率/连击取 max, 用时取 min, 并解锁下一关。
   * @param time 没计时的关传统 -1
   */
  recordMathWin(diff: string, levelId: number, stars: number, accuracy: number,
    time: number, maxCombo: number, nextLevelId: number): void {
    const all: Record<string, MathDiffData> | null =
      parseOrNull<Record<string, MathDiffData>>(this.readJson('math'));
    const data: Record<string, MathDiffData> = all === null ? {} : all;
    let d: MathDiffData = data[diff];
    if (d === undefined) {
      d = new MathDiffData();
    }
    const key: string = String(levelId);
    const prev: MathRecord = d.levels[key] === undefined ? new MathRecord() : d.levels[key];
    const rec: MathRecord = new MathRecord();
    rec.stars = Math.max(prev.stars, stars);
    rec.bestAccuracy = Math.max(prev.bestAccuracy, accuracy);
    if (time >= 0) {
      rec.bestTime = prev.bestTime < 0 ? time : Math.min(prev.bestTime, time);
    } else {
      rec.bestTime = prev.bestTime;
    }
    rec.maxCombo = Math.max(prev.maxCombo, maxCombo);
    rec.plays = prev.plays + 1;
    d.levels[key] = rec;
    if (nextLevelId > 0) {
      d.unlockedLevel = Math.max(d.unlockedLevel, nextLevelId);
    }
    data[diff] = d;
    this.writeJson('math', JSON.stringify(data));
  }

  // ===================== 翻翻乐: 最少步数 / 最短用时 =====================

  getMemoryBest(themeId: string, tierKey: string): BestRecord | null {
    const all: Record<string, Record<string, BestRecord>> | null =
      parseOrNull<Record<string, Record<string, BestRecord>>>(this.readJson('memory'));
    if (all === null) {
      return null;
    }
    const m: Record<string, BestRecord> = all[themeId];
    if (m === undefined) {
      return null;
    }
    const rec: BestRecord = m[tierKey];
    return rec === undefined ? null : rec;
  }

  recordMemoryResult(themeId: string, tierKey: string, steps: number, time: number): RecordResult {
    const all: Record<string, Record<string, BestRecord>> | null =
      parseOrNull<Record<string, Record<string, BestRecord>>>(this.readJson('memory'));
    const data: Record<string, Record<string, BestRecord>> = all === null ? {} : all;
    let m: Record<string, BestRecord> = data[themeId];
    if (m === undefined) {
      m = {};
    }
    const prev: BestRecord = m[tierKey] === undefined ? new BestRecord() : m[tierKey];
    const next: BestRecord = new BestRecord();
    next.steps = prev.steps;
    next.time = prev.time;
    const out: RecordResult = new RecordResult();
    if (steps >= 0 && (prev.steps < 0 || steps < prev.steps)) {
      next.steps = steps;
      out.newStepsRecord = true;
    }
    if (time >= 0 && (prev.time < 0 || time < prev.time)) {
      next.time = time;
      out.newTimeRecord = true;
    }
    out.newRecord = out.newStepsRecord || out.newTimeRecord;
    m[tierKey] = next;
    data[themeId] = m;
    this.writeJson('memory', JSON.stringify(data));
    return out;
  }

  // ===================== 舒尔特: 最快用时 =====================

  getSchulteBest(tierKey: string): BestRecord | null {
    const all: Record<string, BestRecord> | null =
      parseOrNull<Record<string, BestRecord>>(this.readJson('schulte'));
    if (all === null) {
      return null;
    }
    const rec: BestRecord = all[tierKey];
    return rec === undefined ? null : rec;
  }

  recordSchulte(tierKey: string, time: number): RecordResult {
    const all: Record<string, BestRecord> | null =
      parseOrNull<Record<string, BestRecord>>(this.readJson('schulte'));
    const data: Record<string, BestRecord> = all === null ? {} : all;
    const prev: BestRecord = data[tierKey] === undefined ? new BestRecord() : data[tierKey];
    const out: RecordResult = new RecordResult();
    if (time >= 0 && (prev.time < 0 || time < prev.time)) {
      prev.time = time;
      out.newRecord = true;
    }
    data[tierKey] = prev;
    this.writeJson('schulte', JSON.stringify(data));
    return out;
  }

  // ===================== 打地鼠: 最高分 =====================

  getMoleBest(diffKey: string): BestRecord | null {
    const all: Record<string, BestRecord> | null =
      parseOrNull<Record<string, BestRecord>>(this.readJson('mole'));
    if (all === null) {
      return null;
    }
    const rec: BestRecord = all[diffKey];
    return rec === undefined ? null : rec;
  }

  recordMole(diffKey: string, score: number): RecordResult {
    const all: Record<string, BestRecord> | null =
      parseOrNull<Record<string, BestRecord>>(this.readJson('mole'));
    const data: Record<string, BestRecord> = all === null ? {} : all;
    const prev: BestRecord = data[diffKey] === undefined ? new BestRecord() : data[diffKey];
    const out: RecordResult = new RecordResult();
    if (score >= 0 && (prev.score < 0 || score > prev.score)) {
      prev.score = score;
      out.newRecord = true;
    }
    data[diffKey] = prev;
    this.writeJson('mole', JSON.stringify(data));
    return out;
  }

  // ===================== 设置 =====================

  getSettings(): Settings {
    const s: Settings | null = parseOrNull<Settings>(this.readJson('settings'));
    const out: Settings = new Settings();
    if (s !== null) {
      out.muted = s.muted === true;
      out.speakRead = s.speakRead !== false;
    }
    return out;
  }

  setMuted(m: boolean): void {
    const s: Settings = this.getSettings();
    s.muted = m;
    this.writeJson('settings', JSON.stringify(s));
  }

  setSpeakRead(b: boolean): void {
    const s: Settings = this.getSettings();
    s.speakRead = b;
    this.writeJson('settings', JSON.stringify(s));
  }
}

/** 全局单例: 各游戏页共用, 避免重复 open preferences */
export const store: ProgressStore = new ProgressStore();
