/**
 * 子游戏: 打地鼠口算 —— 移植自 kids-games/games/mole。
 *
 * 两层页面: 选难度 → 限时开局 (60 秒)。
 * 地洞是固定网格, 地鼠按 popMs 换洞; 算式永远显示在上方, 所以要一边算一边找。
 *
 * 与原实现一致的两点:
 *  - 只有最易档读题 (高档边读边算反而慢);
 *  - 拍错不扣分, 只断连击 (低龄孩子不该被罚分)。
 */
import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { store, BestRecord, RecordResult } from '../games/box/Store';
import { Voice, mathToSpeech } from '../games/box/Voice';
import { Confetti } from '../games/box/Confetti';
import { CardGrid, CardInfo, GameTopBar, PageHeading, WinCard, WinInfo, BarButton } from '../games/box/Ui';
import { MoleDiff, MoleGame, MoleHandler, MoleSlot, MoleStats, buildDiffs } from '../games/mole/Mole';

const DOMAIN: number = 0x0001;
const TAG: string = 'KidsMole';

@Entry
@Component
struct MoleGamePage {
  @State diffs: MoleDiff[] = buildDiffs();
  /** 0 选难度 1 游戏 */
  @State level: number = 0;
  @State diffIdx: number = 0;

  @State equation: string = '';
  @State holes: MoleSlot[] = [];
  @State cols: number = 3;
  @State scoreText: string = '⭐ 0';
  @State timerText: string = '⏳ 60';
  @State hurry: boolean = false;
  @State comboText: string = '';

  @State winVisible: boolean = false;
  @State winInfo: WinInfo = new WinInfo();
  @State confettiPulse: number = 0;
  @State sparklePulse: number = 0;
  @State sparkleX: number = 0;
  @State sparkleY: number = 0;
  @State sparkleCount: number = 12;
  @State muted: boolean = false;
  @State readOn: boolean = true;

  private game: MoleGame | null = null;
  private voice: Voice = new Voice();
  /** 地鼠网格实测尺寸, 用来算火花喷发位置 */
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
    this.readOn = this.voice.isReadOn();
  }

  aboutToDisappear(): void {
    if (this.game !== null) {
      this.game.destroy();
      this.game = null;
    }
    this.voice.release();
  }

  private diffCards(): CardInfo[] {
    const out: CardInfo[] = [];
    for (let i: number = 0; i < this.diffs.length; i++) {
      const d: MoleDiff = this.diffs[i];
      const best: BestRecord | null = store.getMoleBest(d.key);
      const card: CardInfo = new CardInfo(d.key, d.emoji, d.label, d.desc);
      card.accent = '#f08a4b';
      card.badge = best !== null && best.score >= 0 ? '🏅 最高 ' + best.score + ' 分' : '未挑战';
      out.push(card);
    }
    return out;
  }

  private startGame(idx: number): void {
    if (this.game !== null) {
      this.game.destroy();
      this.game = null;
    }
    this.diffIdx = idx;
    const d: MoleDiff = this.diffs[idx];
    this.cols = d.holes >= 9 ? 3 : 3;
    this.scoreText = '⭐ 0';
    this.timerText = '⏳ ' + d.duration;
    this.hurry = false;
    this.comboText = '';
    this.equation = '';
    this.holes = [];
    this.winVisible = false;
    this.level = 1;

    const self: MoleGamePage = this;
    const h: MoleHandler = {
      onRound: (text: string, slots: MoleSlot[]): void => {
        self.equation = text;
        self.holes = slots;
        if (d.speak && self.readOn) {
          self.voice.speak(mathToSpeech(text) + ' 等于几');
        }
      },
      onScore: (score: number, combo: number): void => {
        self.scoreText = '⭐ ' + score;
        self.comboText = combo >= 2 ? '🔥 ×' + combo : '';
      },
      onTick: (left: number): void => {
        self.timerText = '⏳ ' + left;
        self.hurry = left <= 5;
      },
      onHit: (hole: number): void => {
        self.sparkleCount = 10;
        self.sparkleX = self.holeX(hole) + self.holeSize() / 2;
        self.sparkleY = self.holeY(hole) + self.holeSize() / 2;
        self.sparklePulse++;
      },
      onMiss: (hole: number): void => {
        // 拍错: 靠 slots 里的 miss 标记抖动, 这里只同步一次状态
        self.holes = self.currentSlots();
      },
      onEnd: (stats: MoleStats): void => {
        self.onEnd(stats);
      }
    };
    this.game = new MoleGame(d, h);
    this.game.start();
  }

  /** 从引擎再取一次状态 (拍错后要立刻看到抖动) */
  private currentSlots(): MoleSlot[] {
    if (this.game === null) {
      return this.holes;
    }
    const out: MoleSlot[] = [];
    for (let i: number = 0; i < this.game.holeMoles.length; i++) {
      const src: MoleSlot = this.game.holeMoles[i];
      const s: MoleSlot = new MoleSlot();
      s.value = src.value;
      s.isAnswer = src.isAnswer;
      s.up = src.up;
      s.bonk = src.bonk;
      s.miss = src.miss;
      out.push(s);
    }
    return out;
  }

  private onEnd(stats: MoleStats): void {
    const rec: RecordResult = store.recordMole(stats.diffKey, stats.score);
    const info: WinInfo = new WinInfo();
    info.emoji = '🏆';
    info.title = '时间到！';
    info.metrics.push('⭐ 得分 ' + stats.score + (rec.newRecord ? '  新纪录!' : ''));
    if (stats.maxCombo >= 2) {
      info.metrics.push('🔥 最高连击 ' + stats.maxCombo);
    }
    this.winInfo = info;
    this.winVisible = true;
    this.confettiPulse++;
    this.voice.speak('时间到，你真棒！');
  }

  // ===================== 网格尺寸 =====================

  private rows(): number {
    const n: number = this.holes.length === 0 ? 6 : this.holes.length;
    return Math.ceil(n / this.cols);
  }

  private holeSize(): number {
    if (this.fieldW <= 0) {
      return 80;
    }
    const gap: number = 10;
    const byW: number = (this.fieldW - (this.cols - 1) * gap) / this.cols;
    const byH: number = (this.fieldH - (this.rows() - 1) * gap) / this.rows();
    return Math.max(56, Math.floor(Math.min(byW, byH)));
  }

  private holeX(index: number): number {
    const c: number = index % this.cols;
    return c * (this.holeSize() + 10);
  }

  private holeY(index: number): number {
    const r: number = Math.floor(index / this.cols);
    return r * (this.holeSize() + 10);
  }

  private columnsTemplate(): string {
    let t: string = '';
    for (let i: number = 0; i < this.cols; i++) {
      t += (i === 0 ? '1fr' : ' 1fr');
    }
    return t;
  }

  private rowsTemplate(): string {
    let t: string = '';
    const n: number = this.rows();
    for (let i: number = 0; i < n; i++) {
      t += (i === 0 ? '1fr' : ' 1fr');
    }
    return t;
  }

  // ===================== 界面 =====================

  private topButtons(): BarButton[] {
    const self: MoleGamePage = this;
    const btns: BarButton[] = [];
    if (this.level === 1) {
      btns.push(new BarButton('重玩', (): void => {
        self.startGame(self.diffIdx);
      }));
    }
    btns.push(new BarButton(this.muted ? '🔇' : '🔊', (): void => {
      self.muted = self.voice.toggleMute(store);
    }));
    return btns;
  }

  private stats(): string[] {
    if (this.level !== 1) {
      return [];
    }
    const out: string[] = [this.scoreText, this.timerText];
    if (this.comboText.length > 0) {
      out.push(this.comboText);
    }
    return out;
  }

  @Builder
  fieldView() {
    Column() {
      Text(this.equation)
        .fontSize(34)
        .fontWeight(FontWeight.Bold)
        .fontColor('#2b3a4a')
        .margin({ top: 6, bottom: 4 })
      Text('拍中举着正确答案的地鼠 👇')
        .fontSize(12)
        .fontColor('#8fa0b4')
        .margin({ bottom: 8 })

      Column() {
        Grid() {
          ForEach(this.holes, (m: MoleSlot, i: number) => {
            GridItem() {
              Column() {
                // 洞 (深色椭圆底), 地鼠冒头时数字浮在上面
                Stack() {
                  Column()
                    .width('100%')
                    .height('100%')
                    .borderRadius(999)
                    .backgroundColor('#2b3f52')
                  if (m.up) {
                    Text(String(m.value))
                      .fontSize(this.holeSize() * 0.34)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(m.miss ? '#ec7d7d' : '#3a2a12')
                      .width('100%')
                      .height('100%')
                      .textAlign(TextAlign.Center)
                      .borderRadius(999)
                      .backgroundColor(m.bonk ? '#b8f0d0' : '#ffd87a')
                      .border({ width: 3, color: m.miss ? '#ec7d7d' : '#e0a83c' })
                  }
                }
                .width('100%')
                .height('100%')
                .backgroundColor('#7b5a35')
                .borderRadius(999)
                .onClick(() => {
                  if (this.game !== null) {
                    this.game.tapHole(i);
                  }
                })
              }
              .width(this.holeSize())
              .height(this.holeSize())
            }
            .width(this.holeSize())
            .height(this.holeSize())
          }, (m: MoleSlot, i: number) => 'hole' + i + (m.up ? 'u' : 'd') + m.value + (m.miss ? 'm' : ''))
        }
        .columnsTemplate(this.columnsTemplate())
        .rowsTemplate(this.rowsTemplate())
        .columnsGap(10)
        .rowsGap(10)
        .width(this.fieldW > 0 ? (this.holeSize() * this.cols + 10 * (this.cols - 1)) : '100%')
        .height(this.fieldH > 0 ? (this.holeSize() * this.rows() + 10 * (this.rows() - 1)) : '100%')
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .onAreaChange((oldV: Area, newV: Area): void => {
        this.fieldW = Number(newV.width) - 16;
        this.fieldH = Number(newV.height) - 16;
      })

      if (this.hurry) {
        Text('⏰ 快一点！')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor('#e06a6a')
          .margin({ bottom: 10 })
      } else {
        Blank().height(10)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 12, right: 12 })
  }

  build() {
    Stack() {
      Column() {
        GameTopBar({
          title: this.level === 1 ? this.diffs[this.diffIdx].emoji + ' 打地鼠口算' : '打地鼠口算',
          stats: this.stats(),
          buttons: this.topButtons(),
          backText: '‹ 返回',
          onBack: (): void => {
            if (this.game !== null) {
              this.game.destroy();
              this.game = null;
            }
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
                title: '打地鼠口算',
                subtitle: '算一算！拍中举着「正确答案」的那只地鼠，限时 60 秒比谁拍得多',
                tip: '提示：地鼠会换洞，盯准数字别拍错；连击越高越威风。'
              })
              CardGrid({
                cards: this.diffCards(),
                onPick: (key: string): void => {
                  for (let i: number = 0; i < this.diffs.length; i++) {
                    if (this.diffs[i].key === key) {
                      this.startGame(i);
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
          Column() {
            this.fieldView()
          }
          .layoutWeight(1)
          .width('100%')
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#fdf3e7')

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
              this.startGame(this.diffIdx);
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
