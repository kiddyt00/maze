/**
 * 子游戏: 打地鼠 (星芽版) —— 移植自 kids-learning-games 的 WhackAMoleScene。
 *
 * 页面结构:
 *   0 开始屏 (三档难度, 与原来的覆盖层一致)
 *   1 游戏 (9 个洞 + HUD + 命中反馈)
 * 结束结算卡。
 *
 * 渲染: 洞用固定 3×3 网格; 地鼠的"升起"用 rise 进度驱动位移与透明度,
 * 命中用 hitFlash 驱动缩放 —— 对应原实现的 tween, 但不依赖动画框架。
 */
import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { store, BestRecord, RecordResult } from '../games/box/Store';
import { Voice } from '../games/box/Voice';
import { Confetti } from '../games/box/Confetti';
import { CardGrid, CardInfo, GameTopBar, PageHeading, WinCard, WinInfo, BarButton } from '../games/box/Ui';
import {
  MoleRound, MoleSlot, MoleStats, MoleHandler, kindInfo, MoleKindInfo,
  KIND_BOMB, KIND_GOLD, KIND_HELMET, KIND_CLOCK, ST_IDLE
} from '../games/moleprime/MoleRound';

const DOMAIN: number = 0x0001;
const TAG: string = 'KidsMolePrime';
/** 推进步长: 20fps 的状态推进足够顺滑, 又不会让 UI 过度重建 */
const TICK_MS: number = 50;

/** 一个洞的显示状态 */
@Observed
class HoleView {
  index: number = 0;
  /** 'idle' 空 / 'live' 有地鼠 */
  state: string = 'idle';
  emoji: string = '🐹';
  color: string = '#A96D3E';
  /** 升起进度 0..1 */
  rise: number = 0;
  hitFlash: number = 0;
  label: string = '';
}

@Entry
@Component
struct MolePrimePage {
  /** 0 开始屏 1 游戏中 */
  @State level: number = 0;
  @State holes: HoleView[] = [];
  @State score: number = 0;
  @State timeLeft: number = 45;
  @State combo: number = 0;
  @State lives: number = 3;
  @State accuracy: number = 100;
  @State feedback: string = '';
  @State feedbackGood: boolean = true;
  @State bestScore: number = -1;
  @State difficulty: string = 'normal';
  @State difficultyLabel: string = '欢乐挑战';

  @State winVisible: boolean = false;
  @State winInfo: WinInfo = new WinInfo();
  @State confettiPulse: number = 0;
  @State sparklePulse: number = 0;
  @State sparkleX: number = 0;
  @State sparkleY: number = 0;
  @State sparkleCount: number = 10;
  @State muted: boolean = false;

  private round: MoleRound | null = null;
  private ticker: number = -1;
  private feedbackTimer: number = -1;
  private voice: Voice = new Voice();
  /** 洞区实测尺寸, 用来算火花位置 */
  @State fieldW: number = 0;
  @State fieldH: number = 0;

  aboutToAppear(): void {
    try {
      store.init(getContext(this) as common.UIAbilityContext);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'store init failed');
    }
    this.voice.load(store);
    this.muted = this.voice.isMuted();
    const best: BestRecord | null = store.getMoleBest('prime');
    this.bestScore = best === null ? -1 : best.score;
    this.buildHoles();
  }

  aboutToDisappear(): void {
    this.stopTicker();
    this.voice.release();
  }

  private buildHoles(): void {
    const out: HoleView[] = [];
    for (let i: number = 0; i < 9; i++) {
      const h: HoleView = new HoleView();
      h.index = i;
      out.push(h);
    }
    this.holes = out;
  }

  private difficultyCards(): CardInfo[] {
    const easy: CardInfo = new CardInfo('easy', '🐣', '悠闲敲打', '地鼠停留更久');
    easy.accent = '#7DBA51';
    const normal: CardInfo = new CardInfo('normal', '🐹', '欢乐挑战', '推荐的游戏节奏');
    normal.accent = '#E7A443';
    const hard: CardInfo = new CardInfo('hard', '⚡', '闪电手速', '更快更多地鼠');
    hard.accent = '#D76755';
    return [easy, normal, hard];
  }

  // ===================== 开局 / 结束 =====================

  private startGame(difficulty: string): void {
    this.stopTicker();
    this.difficulty = difficulty;
    this.difficultyLabel = difficulty === 'easy' ? '悠闲敲打'
      : (difficulty === 'hard' ? '闪电手速' : '欢乐挑战');
    this.buildHoles();
    this.score = 0;
    this.combo = 0;
    this.lives = 3;
    this.accuracy = 100;
    this.feedback = '';
    this.winVisible = false;
    this.level = 1;

    const self: MolePrimePage = this;
    const h: MoleHandler = {
      onSlots: (slots: MoleSlot[]): void => {
        self.applySlots(slots);
      },
      onHud: (score: number, timeLeft: number, combo: number, lives: number, acc: number): void => {
        self.score = score;
        self.timeLeft = Math.ceil(timeLeft);
        self.combo = combo;
        self.lives = lives;
        self.accuracy = acc;
      },
      onFeedback: (text: string, good: boolean): void => {
        self.showFeedback(text, good);
      },
      onEnd: (stats: MoleStats): void => {
        self.onEnd(stats);
      }
    };
    this.round = new MoleRound(h);
    this.round.start(difficulty);
    this.applySlots(this.round.slots);
    this.timeLeft = Math.ceil(this.round.timeRemaining());

    let last: number = Date.now();
    this.ticker = setInterval((): void => {
      if (self.round === null) {
        return;
      }
      const now: number = Date.now();
      const dt: number = Math.min(0.2, (now - last) / 1000);
      last = now;
      self.round.tick(dt);
    }, TICK_MS);
  }

  private applySlots(slots: MoleSlot[]): void {
    const out: HoleView[] = [];
    for (let i: number = 0; i < slots.length; i++) {
      const s: MoleSlot = slots[i];
      const v: HoleView = new HoleView();
      v.index = s.index;
      v.state = s.state === ST_IDLE ? 'idle' : 'live';
      v.rise = s.rise;
      v.hitFlash = s.hitFlash;
      if (s.state !== ST_IDLE && s.kind.length > 0) {
        const info: MoleKindInfo = kindInfo(s.kind);
        v.emoji = info.emoji;
        v.color = info.color;
        v.label = info.label;
        // 头盔鼠被敲一下后换成"裂开"的标记
        if (s.kind === KIND_HELMET && s.health < info.health) {
          v.emoji = '💥';
        }
      }
      out.push(v);
    }
    this.holes = out;
  }

  private showFeedback(text: string, good: boolean): void {
    this.feedback = text;
    this.feedbackGood = good;
    if (this.feedbackTimer >= 0) {
      clearTimeout(this.feedbackTimer);
    }
    this.feedbackTimer = setTimeout((): void => {
      this.feedback = '';
    }, 900);
  }

  private onEnd(stats: MoleStats): void {
    this.stopTicker();
    const rec: RecordResult = store.recordMole('prime', stats.score);
    if (rec.newRecord) {
      this.bestScore = stats.score;
    }
    const info: WinInfo = new WinInfo();
    info.emoji = '🏆';
    info.title = '时间到！';
    info.metrics.push('⭐ 得分 ' + stats.score + (rec.newRecord ? '  新纪录!' : ''));
    info.metrics.push('🎯 命中率 ' + (stats.attempts === 0 ? 100 : Math.round(stats.hits * 100 / stats.attempts)) + '%');
    if (stats.maxCombo >= 2) {
      info.metrics.push('🔥 最高连击 ' + stats.maxCombo);
    }
    if (this.bestScore >= 0) {
      info.metrics.push('🏅 最高分 ' + this.bestScore);
    }
    this.winInfo = info;
    this.winVisible = true;
    this.confettiPulse++;
    this.voice.speak('时间到，你真棒！');
  }

  private stopTicker(): void {
    if (this.ticker >= 0) {
      clearInterval(this.ticker);
      this.ticker = -1;
    }
    if (this.feedbackTimer >= 0) {
      clearTimeout(this.feedbackTimer);
      this.feedbackTimer = -1;
    }
  }

  // ===================== 布局 =====================

  private holeSize(): number {
    if (this.fieldW <= 0) {
      return 100;
    }
    const gap: number = 10;
    const byW: number = (this.fieldW - gap * 2) / 3;
    const byH: number = (this.fieldH - gap * 2) / 3;
    return Math.max(64, Math.floor(Math.min(byW, byH)));
  }

  private holeX(index: number): number {
    const c: number = index % 3;
    return c * (this.holeSize() + 10);
  }

  private holeY(index: number): number {
    const r: number = Math.floor(index / 3);
    return r * (this.holeSize() + 10);
  }

  // ===================== 界面 =====================

  private topButtons(): BarButton[] {
    const self: MolePrimePage = this;
    const btns: BarButton[] = [];
    btns.push(new BarButton(this.muted ? '🔇' : '🔊', (): void => {
      self.muted = self.voice.toggleMute(store);
    }));
    return btns;
  }

  @Builder
  hudView() {
    Column() {
      Row() {
        Text('⭐ ' + this.score)
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontColor('#8A561F')
        Blank()
        Text('⏱️ ' + this.timeLeft)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.timeLeft <= 10 ? '#C94C50' : '#4B6630')
        Blank()
        Text('❤️ ' + this.lives)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor('#BB4652')
      }
      .width('100%')

      // 时间条
      Row() {
        Row()
          .width(Math.max(0, Math.min(100, this.timeLeft / 60 * 100)) + '%')
          .height(7)
          .backgroundColor(this.timeLeft <= 10 ? '#C94C50' : '#79B84C')
          .borderRadius(4)
      }
      .width('100%')
      .height(7)
      .backgroundColor('#DCE8C8')
      .borderRadius(4)
      .margin({ top: 6 })

      Row() {
        Text(this.combo >= 2 ? '🔥 ' + this.combo + ' 连击' : '')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#D78522')
        Blank()
        Text('🎯 ' + this.accuracy + '%')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#5B7D40')
      }
      .width('100%')
      .height(24)
      .margin({ top: 4 })

      Text(this.feedback)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.feedbackGood ? '#4B7A32' : '#8A6A48')
        .height(24)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 4, bottom: 2 })
  }

  @Builder
  fieldView() {
    Column() {
      this.hudView()

      Column() {
        Grid() {
          ForEach(this.holes, (h: HoleView, i: number) => {
            GridItem() {
              Stack() {
                // 洞口
                Column()
                  .width('100%')
                  .height('100%')
                  .borderRadius(999)
                  .backgroundColor('#8A633B')
                  .border({ width: 4, color: '#714A29' })
                Column()
                  .width('86%')
                  .height('62%')
                  .borderRadius(999)
                  .backgroundColor('#2D1C12')
                  .align(Alignment.Center)
                // 地鼠: rise 驱动从洞里升起
                if (h.state === 'live') {
                  Column() {
                    Text(h.emoji)
                      .fontSize(this.holeSize() * 0.5)
                    if (h.label.length > 0 && h.rise >= 0.95) {
                      Text(h.label)
                        .fontSize(10)
                        .fontColor('#ffffff')
                        .backgroundColor(h.color)
                        .borderRadius(999)
                        .padding({ left: 6, right: 6, top: 1, bottom: 1 })
                    }
                  }
                  .width('100%')
                  .height('100%')
                  .justifyContent(FlexAlign.Center)
                  .borderRadius(999)
                  .backgroundColor(h.color)
                  .opacity(h.rise)
                  .translate({ y: (1 - h.rise) * this.holeSize() * 0.55 })
                  .scale({
                    x: 1 + h.hitFlash * 0.16,
                    y: 1 - h.hitFlash * 0.2
                  })
                }
              }
              .width('100%')
              .height('100%')
              .onClick((): void => {
                if (this.round !== null) {
                  this.round.whack(h.index);
                }
              })
            }
            .width(this.holeSize())
            .height(this.holeSize())
          }, (h: HoleView, i: number) => 'hole' + i + h.state + h.emoji + Math.round(h.rise * 20)
            + Math.round(h.hitFlash * 10))
        }
        .columnsTemplate('1fr 1fr 1fr')
        .rowsTemplate('1fr 1fr 1fr')
        .columnsGap(10)
        .rowsGap(10)
        .width(this.fieldW > 0 ? (this.holeSize() * 3 + 20) : '100%')
        .height(this.fieldH > 0 ? (this.holeSize() * 3 + 20) : '100%')
        .scrollBar(BarState.Off)
        .onClick((): void => {
          // 网格空白处的点击算一次挥空 (原 createPlayArea 的 missAttempt)
          if (this.round !== null) {
            this.round.missAttempt();
          }
        })
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .onAreaChange((oldV: Area, newV: Area): void => {
        this.fieldW = Number(newV.width) - 20;
        this.fieldH = Number(newV.height) - 20;
      })
    }
    .width('100%')
    .height('100%')
  }

  build() {
    Stack() {
      Column() {
        GameTopBar({
          title: this.level === 1 ? '打地鼠 · ' + this.difficultyLabel : '打地鼠',
          stats: this.level === 1 ? ['⭐ ' + this.score, '⏱️ ' + this.timeLeft] : [],
          buttons: this.topButtons(),
          backText: this.level === 1 ? '‹ 退出' : '‹ 返回',
          onBack: (): void => {
            this.stopTicker();
            this.winVisible = false;
            if (this.level === 1) {
              this.level = 0;
              return;
            }
            this.voice.release();
            router.back();
          }
        })

        if (this.level === 0) {
          Scroll() {
            Column() {
              PageHeading({
                emoji: '🔨',
                title: '打地鼠',
                subtitle: '看准时机，连击得分翻倍',
                tip: this.bestScore >= 0 ? '🏅 你的最高分：' + this.bestScore : '地鼠会自己溜走，敲空会断连击'
              })
              CardGrid({
                cards: this.difficultyCards(),
                onPick: (key: string): void => {
                  this.startGame(key);
                }
              })
              Text('金鼠 +3 · 时钟鼠 +3 秒 · 头盔鼠要敲两下 · 别敲炸弹')
                .fontSize(12)
                .fontColor('#8fa0b4')
                .textAlign(TextAlign.Center)
                .width('100%')
                .margin({ top: 6 })
              Blank().height(24)
            }
            .width('100%')
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
        } else {
          Column() {
            this.fieldView()
          }
          .layoutWeight(1)
          .width('100%')
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.level === 1 ? '#DFF3B7' : '#eaf4ff')

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
              this.startGame(this.difficulty);
            },
            onBack: (): void => {
              this.level = 0;
              this.winVisible = false;
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
}
