/**
 * 子游戏: 口算闯关大冒险 —— 移植自 kids-games/games/math。
 *
 * 三层页面 (与原 index.html 的三个 screen 对应):
 *   L0 选难度 → L1 闯关地图 → L2 答题 (选择 / 键盘输入)
 * 结算卡在其中一层之上浮出。
 *
 * 修改点只有一处: 原版用浏览器 localStorage 存进度, 这里改走原生 preferences
 * (games/box/Store.ets), 其余难度、题目边界、宽松策略与提示语全部照搬。
 */
import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { store, MathRecord } from '../games/box/Store';
import { Voice } from '../games/box/Voice';
import { Confetti } from '../games/box/Confetti';
import { BigButton, CardGrid, CardInfo, GameTopBar, PageHeading, WinCard, WinInfo, BarButton } from '../games/box/Ui';
import { MathDiff, MathLevel, buildDiffs, fmtTime, starText, starsFor } from '../games/math/Levels';
import { MathGame, MathLevelCfg, MathStats, MathHandler } from '../games/math/MathEngine';
import { GenConfig, Problem } from '../games/math/Problems';

const DOMAIN: number = 0x0001;
const TAG: string = 'KidsMath';

const PRAISES: string[] = ['太棒了！', '答对啦！', '真厉害！', '好聪明！'];
const KEYPAD: string[] = ['1', '2', '3', '4', '5', '6', '7', '8', '9', 'del', '0', 'enter'];

/** ○ 图示里的一颗圆点 */
class Dot {
  crossed: boolean = false;

  constructor(crossed: boolean) {
    this.crossed = crossed;
  }
}

@Entry
@Component
struct MathGamePage {
  @State diffs: MathDiff[] = buildDiffs();
  /** 0 = 选难度, 1 = 闯关地图, 2 = 答题 */
  @State level: number = 0;
  @State diffIdx: number = 0;
  /** 地图/答题里当前关心的难度 (选难度页不关心) */
  @State curDiffIdx: number = 0;
  @State curLevelIdx: number = 0;

  // ---- 答题页状态 ----
  @State equation: string = '';
  @State answerText: string = '?';
  @State answerState: number = 0; // 0 普通 1 对 2 错
  @State feedback: string = '';
  @State feedbackRight: boolean = true;
  @State choices: number[] = [];
  @State isChoice: boolean = false;
  @State dots: Dot[] = [];
  @State opSign: string = '+';
  @State showPictograph: boolean = false;
  @State comboText: string = '';
  @State doneCount: number = 0;
  @State totalCount: number = 0;
  @State elapsedText: string = '00:00';
  @State showTimer: boolean = false;
  @State bufferText: string = '_';

  // ---- 结算 ----
  @State winVisible: boolean = false;
  @State winInfo: WinInfo = new WinInfo();

  // ---- 彩屑 ----
  @State confettiPulse: number = 0;
  @State sparklePulse: number = 0;
  @State sparkleX: number = 0;
  @State sparkleY: number = 0;
  @State sparkleCount: number = 12;

  @State muted: boolean = false;
  @State readOn: boolean = true;

  private game: MathGame | null = null;
  private voice: Voice = new Voice();
  private lastStats: MathStats | null = null;
  private lastFixed: Problem[] = [];

  aboutToAppear(): void {
    try {
      store.init(getContext(this) as common.UIAbilityContext);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'store init failed');
    }
    this.voice.load(store);
    this.muted = this.voice.isMuted();
    this.readOn = this.voice.isReadOn();
  }

  aboutToDisappear(): void {
    if (this.game !== null) {
      this.game.destroy();
      this.game = null;
    }
    this.voice.release();
  }

  // ===================== 选难度 / 地图 =====================

  private diffCards(): CardInfo[] {
    const out: CardInfo[] = [];
    for (let i: number = 0; i < this.diffs.length; i++) {
      const d: MathDiff = this.diffs[i];
      const got: number = store.mathStars(d.key, this.levelIds(d));
      const card: CardInfo = new CardInfo(d.key, d.emoji, d.label, d.age);
      card.desc = d.desc;
      card.accent = d.accent;
      card.badge = got > 0 ? '⭐ ' + got + '/' + (d.levels.length * 3) : '未开始';
      out.push(card);
    }
    return out;
  }

  private levelIds(d: MathDiff): number[] {
    const ids: number[] = [];
    for (let i: number = 0; i < d.levels.length; i++) {
      ids.push(d.levels[i].id);
    }
    return ids;
  }

  /** 闯关地图上的节点卡: 锁着的显示 🔒 且不可点 */
  private nodeCards(): CardInfo[] {
    const d: MathDiff = this.diffs[this.curDiffIdx];
    const out: CardInfo[] = [];
    for (let i: number = 0; i < d.levels.length; i++) {
      const lv: MathLevel = d.levels[i];
      const unlocked: boolean = store.isMathUnlocked(d.key, lv.id);
      const rec: MathRecord | null = store.getMathLevel(d.key, lv.id);
      const card: CardInfo = new CardInfo('lv' + lv.id, lv.emoji, '第' + lv.id + '关 · ' + lv.name,
        lv.count + ' 题 · ' + (lv.mode === 'choice' ? '选一选' : '打数字'));
      card.accent = d.accent;
      card.disabled = !unlocked;
      if (!unlocked) {
        card.badge = '🔒 先过上一关';
      } else if (rec === null) {
        card.badge = '☆☆☆';
      } else {
        card.badge = starText(rec.stars);
      }
      out.push(card);
    }
    return out;
  }

  private openDiff(idx: number): void {
    this.curDiffIdx = idx;
    this.level = 1;
  }

  private openLevel(idx: number): void {
    const d: MathDiff = this.diffs[this.curDiffIdx];
    this.curLevelIdx = idx;
    this.startLevel(d.levels[idx], []);
  }

  private startLevel(lv: MathLevel, fixed: Problem[]): void {
    if (this.game !== null) {
      this.game.destroy();
      this.game = null;
    }
    const d: MathDiff = this.diffs[this.curDiffIdx];
    this.lastFixed = fixed.slice();
    this.winVisible = false;
    this.feedback = '';
    this.answerState = 0;
    this.answerText = '?';
    this.comboText = '';
    this.isChoice = lv.mode === 'choice';
    this.showTimer = lv.timer.length > 0;
    this.showPictograph = lv.pictograph;
    this.elapsedText = '00:00';
    this.totalCount = fixed.length > 0 ? fixed.length : lv.count;
    this.doneCount = 0;
    this.level = 2;

    const cfg: MathLevelCfg = new MathLevelCfg();
    cfg.id = lv.id;
    cfg.name = lv.name;
    cfg.count = lv.count;
    cfg.mode = lv.mode;
    cfg.timer = lv.timer;
    cfg.combo = lv.combo;
    cfg.pictograph = lv.pictograph;
    cfg.lenient = lv.lenient;
    cfg.starTime = lv.starTime;
    cfg.gen = lv.gen;

    const self: MathGamePage = this;
    const h: MathHandler = {
      onProblem: (p: Problem, index: number, count: number): void => {
        self.onProblem(p, index, count);
      },
      onRight: (p: Problem, given: number, combo: number): void => {
        self.onRight(p, given, combo);
      },
      onWrong: (p: Problem, given: number, lenient: boolean): void => {
        self.onWrong(p, given, lenient);
      },
      onCombo: (combo: number): void => {
        self.comboText = combo >= 2 ? '🔥 连击 ×' + combo : '';
      },
      onProgress: (done: number, total: number): void => {
        self.doneCount = done;
        self.totalCount = total;
      },
      onTick: (sec: number): void => {
        self.elapsedText = fmtTime(sec);
      },
      onWin: (stats: MathStats): void => {
        self.onWin(stats);
      }
    };
    this.game = new MathGame(d.key, cfg, h, fixed);
    this.game.start();
  }

  // ===================== 答题反馈 (对应 game.js 的 _feedbackXxx) =====================

  private onProblem(p: Problem, index: number, count: number): void {
    const self: MathGamePage = this;
    self.equation = p.text;
    self.answerText = '?';
    self.answerState = 0;
    self.feedback = '';
    self.bufferText = '_';
    self.choices = this.isChoice ? p.choices : [];
    self.buildPictograph(p);
    if (this.readOn) {
      this.voice.speakMath(p.text);
    }
  }

  /** 启蒙档的 ○ 图示: 加法画两组, 减法画一组并划掉后 b 个 */
  private buildPictograph(p: Problem): void {
    const out: Dot[] = [];
    if (this.showPictograph && p.operands.length >= 2 && (p.op === '+' || p.op === '-')) {
      const a: number = p.operands[0];
      const b: number = p.operands[1];
      if (p.op === '+') {
        for (let i: number = 0; i < a; i++) {
          out.push(new Dot(false));
        }
        for (let i: number = 0; i < b; i++) {
          out.push(new Dot(false));
        }
        this.opSign = '+';
      } else {
        // 减法: 画 a 个, 划掉后 b 个 (前 a-b 个不划)
        for (let i: number = 0; i < a; i++) {
          out.push(new Dot(i >= a - b));
        }
        this.opSign = '-';
      }
    }
    this.dots = out;
  }

  private onRight(p: Problem, given: number, combo: number): void {
    this.answerText = String(p.answer);
    this.answerState = 1;
    const msg: string = PRAISES[Math.floor(Math.random() * PRAISES.length)];
    this.feedback = '✅ ' + msg;
    this.feedbackRight = true;
    this.voice.speak(msg);
    // 连击 ≥3 从算式处喷火花 (原 sparkle)
    if (combo >= 3) {
      this.sparkleCount = 12 + combo;
      this.sparkleX = 187;
      this.sparkleY = 150;
      this.sparklePulse++;
    }
  }

  private onWrong(p: Problem, given: number, lenient: boolean): void {
    this.answerText = String(p.answer);
    this.answerState = 2;
    this.feedback = lenient ? '🤔 再数一数～ 再试一次' : '🤔 再想想～ 正确答案是 ' + p.answer;
    this.feedbackRight = false;
    this.bufferText = '_';
    this.voice.speak(lenient ? '再数一数' : '再想想');
  }

  // ===================== 键盘 =====================

  private pressKey(k: string): void {
    if (this.game === null) {
      return;
    }
    const buf: string = this.game.pressKey(k);
    this.bufferText = buf.length === 0 ? '_' : buf;
    // 回车提交后引擎会自动走完反馈, 这里只同步显示
    if (k === 'enter') {
      this.bufferText = '_';
    }
  }

  // ===================== 结算 =====================

  private onWin(stats: MathStats): void {
    this.lastStats = stats;
    stats.stars = starsFor(stats.accuracy, stats.total, stats.elapsed, stats.timer, stats.starTime);
    const d: MathDiff = this.diffs[this.curDiffIdx];
    let nextId: number = -1;
    for (let i: number = 0; i < d.levels.length; i++) {
      if (d.levels[i].id === stats.levelId + 1) {
        nextId = d.levels[i].id;
      }
    }
    // 错题重练不写存档/不解锁, 避免刷分 (与原 main.js 一致)
    if (!stats.isRetry) {
      store.recordMathWin(stats.diffKey, stats.levelId, stats.stars, stats.accuracy,
        stats.timer.length > 0 ? stats.elapsed : -1, stats.maxCombo, nextId);
    }

    const info: WinInfo = new WinInfo();
    info.emoji = stats.stars >= 3 ? '🎉' : '🎊';
    info.title = stats.isRetry ? '错题重练完成！' : '过关啦！' + stats.levelName;
    info.metrics.push(starText(stats.stars));
    info.metrics.push('✅ 答对 ' + stats.correct + '/' + stats.total);
    info.metrics.push('🎯 正确率 ' + Math.round(stats.accuracy * 100) + '%');
    if (stats.maxCombo >= 2) {
      info.metrics.push('🔥 最高连击 ' + stats.maxCombo);
    }
    if (stats.timer.length > 0) {
      info.metrics.push('⏱️ 用时 ' + fmtTime(stats.elapsed));
    }
    info.showNext = nextId > 0 && !stats.isRetry;
    info.showRetryWrong = stats.wrongList.length > 0;
    this.winInfo = info;
    this.winVisible = true;
    this.confettiPulse++;
    this.voice.speak('过关啦，你真棒！');
  }

  private againLevel(): void {
    const d: MathDiff = this.diffs[this.curDiffIdx];
    this.startLevel(d.levels[this.curLevelIdx], []);
  }

  private retryWrong(): void {
    if (this.lastStats === null) {
      return;
    }
    const d: MathDiff = this.diffs[this.curDiffIdx];
    this.startLevel(d.levels[this.curLevelIdx], this.lastStats.wrongList);
  }

  private nextLevel(): void {
    const d: MathDiff = this.diffs[this.curDiffIdx];
    for (let i: number = 0; i < d.levels.length; i++) {
      if (d.levels[i].id === d.levels[this.curLevelIdx].id + 1) {
        this.curLevelIdx = i;
        this.startLevel(d.levels[i], []);
        return;
      }
    }
  }

  private backToMap(): void {
    if (this.game !== null) {
      this.game.destroy();
      this.game = null;
    }
    this.winVisible = false;
    this.level = 1;
  }

  private onBack(): void {
    if (this.level === 2) {
      this.backToMap();
      return;
    }
    if (this.level === 1) {
      this.level = 0;
      return;
    }
    if (this.game !== null) {
      this.game.destroy();
      this.game = null;
    }
    this.voice.release();
    router.back();
  }

  // ===================== 界面 =====================

  private topButtons(): BarButton[] {
    const self: MathGamePage = this;
    const btns: BarButton[] = [];
    if (this.level === 2) {
      btns.push(new BarButton('重玩', (): void => {
        self.againLevel();
      }));
      btns.push(new BarButton(this.readOn ? '📢' : '🔕', (): void => {
        self.readOn = self.voice.toggleRead(store);
      }));
    }
    btns.push(new BarButton(this.muted ? '🔇' : '🔊', (): void => {
      self.muted = self.voice.toggleMute(store);
    }));
    return btns;
  }

  private stats(): string[] {
    if (this.level !== 2) {
      return [];
    }
    const out: string[] = [];
    out.push('本关 ' + this.doneCount + '/' + this.totalCount);
    if (this.showTimer) {
      out.push('⏱️ ' + this.elapsedText);
    }
    return out;
  }

  private diffTitle(): string {
    const d: MathDiff = this.diffs[this.curDiffIdx];
    return d.emoji + ' ' + d.label + ' · 闯关地图';
  }

  @Builder
  dotRow() {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
      ForEach(this.dots, (d: Dot, i: number) => {
        Text('●')
          .fontSize(17)
          .fontColor(d.crossed ? '#c8d3de' : '#5b9be8')
          .decoration({ type: d.crossed ? TextDecorationType.LineThrough : TextDecorationType.None,
            color: '#ec7d7d' })
          .margin({ right: 4, bottom: 2 })
      }, (d: Dot, i: number) => 'dot' + i + (d.crossed ? 'x' : ''))
    }
    .width('100%')
    .padding({ left: 18, right: 18 })
  }

  @Builder
  equationView() {
    Column() {
      Row() {
        Text(this.equation)
          .fontSize(38)
          .fontWeight(FontWeight.Bold)
          .fontColor('#2b3a4a')
        Text(' = ')
          .fontSize(32)
          .fontColor('#8fa0b4')
        Text(this.answerText)
          .fontSize(38)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.answerState === 1 ? '#2f9e6f' : (this.answerState === 2 ? '#e06a6a' : '#8fa0b4'))
      }
      .alignItems(VerticalAlign.Center)

      if (this.dots.length > 0) {
        this.dotRow()
      }

      if (this.comboText.length > 0) {
        Text(this.comboText)
          .fontSize(14)
          .fontColor('#f08a4b')
          .fontWeight(FontWeight.Bold)
          .margin({ top: 6 })
      }

      Text(this.feedback)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.feedbackRight ? '#2f9e6f' : '#e06a6a')
        .height(24)
        .margin({ top: 6 })
    }
    .width('100%')
    .padding({ top: 14, bottom: 10 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  choiceView() {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
      ForEach(this.choices, (c: number) => {
        Text(String(c))
          .fontSize(30)
          .fontWeight(FontWeight.Bold)
          .fontColor('#3f7fcf')
          .width('46%')
          .height(82)
          .textAlign(TextAlign.Center)
          .borderRadius(18)
          .backgroundColor('#ffffff')
          .border({ width: 2, color: '#dbe7f3' })
          .shadow({ radius: 8, color: '#16284a15', offsetX: 0, offsetY: 2 })
          .margin({ bottom: 14 })
          .onClick(() => {
            if (this.game !== null) {
              this.game.submit(c);
            }
          })
      }, (c: number) => 'ch' + c)
    }
    .width('100%')
    .padding({ left: 20, right: 20 })
  }

  @Builder
  keypadView() {
    Column() {
      Text(this.bufferText)
        .fontSize(34)
        .fontWeight(FontWeight.Bold)
        .fontColor('#3f7fcf')
        .width(180)
        .height(60)
        .textAlign(TextAlign.Center)
        .borderRadius(14)
        .backgroundColor('#ffffff')
        .border({ width: 2, color: '#dbe7f3' })
        .margin({ bottom: 12 })

      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
        ForEach(KEYPAD, (k: string) => {
          Text(k === 'del' ? '⌫' : (k === 'enter' ? '✓' : k))
            .fontSize(k === 'del' || k === 'enter' ? 24 : 26)
            .fontWeight(FontWeight.Bold)
            .fontColor(k === 'enter' ? Color.White : '#3f7fcf')
            .width('31%')
            .height(56)
            .textAlign(TextAlign.Center)
            .borderRadius(14)
            .backgroundColor(k === 'enter' ? '#5b9be8' : '#ffffff')
            .border({ width: 2, color: k === 'enter' ? '#5b9be8' : '#dbe7f3' })
            .margin({ bottom: 10 })
            .onClick(() => {
              this.pressKey(k);
            })
        }, (k: string) => 'key' + k)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 20, right: 20 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  playView() {
    Scroll() {
      Column() {
        this.equationView()
        if (this.isChoice) {
          this.choiceView()
        } else {
          this.keypadView()
        }
        Blank().height(20)
      }
      .width('100%')
    }
    .width('100%')
    .layoutWeight(1)
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
  }

  build() {
    Stack() {
      Column() {
        GameTopBar({
          title: this.level === 2 ? this.diffTitleShort() : '口算闯关大冒险',
          stats: this.stats(),
          buttons: this.topButtons(),
          backText: this.level === 2 ? '‹ 地图' : '‹ 返回',
          onBack: (): void => {
            this.onBack();
          }
        })

        if (this.level === 0) {
          Scroll() {
            Column() {
              PageHeading({
                emoji: '🧮',
                title: '口算闯关大冒险',
                subtitle: '出题答题闯地图，加减乘除四档难度，选一选或打数字，连击 + 星星 + 错题重练',
                tip: '提示：先挑一档难度，一关一关往后闯；每关最多 3 颗星。'
              })
              CardGrid({
                cards: this.diffCards(),
                onPick: (key: string): void => {
                  for (let i: number = 0; i < this.diffs.length; i++) {
                    if (this.diffs[i].key === key) {
                      this.openDiff(i);
                      return;
                    }
                  }
                }
              })
              Blank().height(24)
            }
            .width('100%')
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
        } else if (this.level === 1) {
          Scroll() {
            Column() {
              PageHeading({
                emoji: this.diffs[this.curDiffIdx].emoji,
                title: this.diffTitle(),
                subtitle: this.diffs[this.curDiffIdx].desc
              })
              CardGrid({
                cards: this.nodeCards(),
                onPick: (key: string): void => {
                  const d: MathDiff = this.diffs[this.curDiffIdx];
                  for (let i: number = 0; i < d.levels.length; i++) {
                    if ('lv' + d.levels[i].id === key) {
                      this.openLevel(i);
                      return;
                    }
                  }
                }
              })
              Blank().height(24)
            }
            .width('100%')
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
        } else {
          this.playView()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#eaf4ff')

      // 彩屑层 (不挡触摸)
      Confetti({
        pulse: this.confettiPulse,
        sparklePulse: this.sparklePulse,
        centerX: this.sparkleX,
        centerY: this.sparkleY,
        sparkleCount: this.sparkleCount
      })

      if (this.winVisible) {
        Column() {
          WinCard({
            info: this.winInfo,
            onAgain: (): void => {
              this.againLevel();
            },
            onNext: (): void => {
              this.nextLevel();
            },
            onRetryWrong: (): void => {
              this.retryWrong();
            },
            onBack: (): void => {
              this.backToMap();
            }
          })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#10182866')
      }
    }
    .width('100%')
    .height('100%')
  }

  private diffTitleShort(): string {
    const d: MathDiff = this.diffs[this.curDiffIdx];
    const lv: MathLevel = d.levels[this.curLevelIdx];
    return d.emoji + ' ' + lv.emoji + ' ' + lv.name;
  }
}
