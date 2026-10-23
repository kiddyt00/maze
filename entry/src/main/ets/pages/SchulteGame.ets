/**
 * 子游戏: 舒尔特方格 —— 移植自 kids-games/games/schulte。
 *
 * 两层页面: 选难度 (3×3 ~ 6×6) → 点格子。
 * 计时只在开一局时启动, 点完最后一个数字立刻停表; 最优用时存进 preferences。
 *
 * 与原实现的一处语气差别: 原版点错只抖一下不扣分, 这里保持一致 —— 点错只记录次数,
 * 给家长的看板里能看到, 孩子端不出现"错/失败"字样。
 */
import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { store, BestRecord, RecordResult } from '../games/box/Store';
import { Voice } from '../games/box/Voice';
import { Confetti } from '../games/box/Confetti';
import { CardGrid, CardInfo, GameTopBar, PageHeading, WinCard, WinInfo, BarButton } from '../games/box/Ui';
import {
  CellState, SchulteGame, SchulteHandler, SchulteStats, SchulteTier, buildTiers
} from '../games/schulte/Schulte';
import { fmtTime } from '../games/math/Levels';

const DOMAIN: number = 0x0001;
const TAG: string = 'KidsSchulte';

@Entry
@Component
struct SchulteGamePage {
  @State tiers: SchulteTier[] = buildTiers();
  /** 0 选难度 1 游戏 */
  @State level: number = 0;
  @State tierIdx: number = 0;

  @State cells: CellState[] = [];
  @State gridN: number = 3;
  @State nextText: string = '👉 找 1';
  @State timerText: string = '⏱️ 00:00';
  @State errorsText: string = '❌ 0';

  @State winVisible: boolean = false;
  @State winInfo: WinInfo = new WinInfo();
  @State confettiPulse: number = 0;
  @State muted: boolean = false;
  @State sparklePulse: number = 0;
  @State sparkleX: number = 0;
  @State sparkleY: number = 0;
  @State sparkleCount: number = 8;
  /** 点错的格子索引, 抖一下再清掉 */
  @State wrongIdx: number = -1;

  private game: SchulteGame | null = null;
  private voice: Voice = new Voice();
  /** 网格实测宽高, 用来算格子边长 */
  @State boardW: number = 0;
  @State boardH: number = 0;

  aboutToAppear(): void {
    try {
      store.init(getContext(this) as common.UIAbilityContext);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'store init failed');
    }
    this.voice.load(store);
    this.muted = this.voice.isMuted();
  }

  aboutToDisappear(): void {
    if (this.game !== null) {
      this.game.destroy();
      this.game = null;
    }
    this.voice.release();
  }

  private tierCards(): CardInfo[] {
    const out: CardInfo[] = [];
    for (let i: number = 0; i < this.tiers.length; i++) {
      const t: SchulteTier = this.tiers[i];
      const best: BestRecord | null = store.getSchulteBest(t.key);
      const card: CardInfo = new CardInfo(t.key, t.emoji, t.label, t.desc);
      card.accent = '#4cc1a1';
      card.badge = best !== null && best.time >= 0 ? '🏅 最快 ' + fmtTime(best.time) : '未挑战';
      out.push(card);
    }
    return out;
  }

  private startGame(idx: number): void {
    if (this.game !== null) {
      this.game.destroy();
      this.game = null;
    }
    this.tierIdx = idx;
    const tier: SchulteTier = this.tiers[idx];
    this.gridN = tier.size;
    this.nextText = '👉 找 1';
    this.timerText = '⏱️ 00:00';
    this.errorsText = '❌ 0';
    this.wrongIdx = -1;
    this.winVisible = false;
    this.level = 1;

    const self: SchulteGamePage = this;
    const h: SchulteHandler = {
      onGrid: (cells: CellState[]): void => {
        self.cells = cells;
      },
      onNext: (next: number): void => {
        self.nextText = '👉 找 ' + next;
        // 与原实现一致: 只在小格子上读数, 免得大格子读数字反而分散注意力
        if (tier.size <= 4) {
          self.voice.speak(String(next));
        }
      },
      onErrors: (errors: number): void => {
        self.errorsText = '❌ ' + errors;
      },
      onTick: (sec: number): void => {
        self.timerText = '⏱️ ' + fmtTime(sec);
      },
      onTapRight: (val: number, index: number): void => {
        const c: CellState = self.cells[index];
        c.found = true;
        self.cells = self.cells.slice();
        self.sparkleCount = 8;
        self.sparkleX = self.cellX(index) + self.cellSize() / 2;
        self.sparkleY = self.cellY(index) + self.cellSize() / 2;
        self.sparklePulse++;
      },
      onTapWrong: (val: number, index: number): void => {
        self.wrongIdx = index;
        setTimeout((): void => {
          self.wrongIdx = -1;
        }, 320);
      },
      onWin: (stats: SchulteStats): void => {
        self.onWin(stats);
      }
    };
    this.game = new SchulteGame(tier, h);
    this.game.start();
  }

  private onWin(stats: SchulteStats): void {
    const rec: RecordResult = store.recordSchulte(stats.tierKey, stats.elapsed);
    const info: WinInfo = new WinInfo();
    info.emoji = '🎉';
    info.title = '全部找到啦！';
    info.metrics.push('⏱️ 用时 ' + fmtTime(stats.elapsed) + (rec.newRecord ? '  新纪录!' : ''));
    info.metrics.push('❌ 点错 ' + stats.errors + ' 次');
    this.winInfo = info;
    this.winVisible = true;
    this.confettiPulse++;
    this.voice.speak('全部找到，真厉害！');
  }

  // ===================== 布局计算 =====================

  private cellSize(): number {
    if (this.boardW <= 0) {
      return 60;
    }
    const gap: number = this.gridN >= 5 ? 6 : 9;
    const byW: number = (this.boardW - (this.gridN - 1) * gap) / this.gridN;
    const byH: number = (this.boardH - (this.gridN - 1) * gap) / this.gridN;
    const s: number = Math.min(byW, byH);
    return Math.max(34, Math.floor(s));
  }

  private cellX(index: number): number {
    const gap: number = this.gridN >= 5 ? 6 : 9;
    const c: number = index % this.gridN;
    return c * (this.cellSize() + gap);
  }

  private cellY(index: number): number {
    const gap: number = this.gridN >= 5 ? 6 : 9;
    const r: number = Math.floor(index / this.gridN);
    return r * (this.cellSize() + gap);
  }

  private gridGap(): number {
    return this.gridN >= 5 ? 6 : 9;
  }

  private columnsTemplate(): string {
    let t: string = '';
    for (let i: number = 0; i < this.gridN; i++) {
      t += (i === 0 ? '1fr' : ' 1fr');
    }
    return t;
  }

  private rowsTemplate(): string {
    return this.columnsTemplate();
  }

  // ===================== 界面 =====================

  private topButtons(): BarButton[] {
    const self: SchulteGamePage = this;
    const btns: BarButton[] = [];
    if (this.level === 1) {
      btns.push(new BarButton('重玩', (): void => {
        self.startGame(self.tierIdx);
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
    return [this.nextText, this.timerText, this.errorsText];
  }

  @Builder
  gridView() {
    Column() {
      Grid() {
        ForEach(this.cells, (c: CellState, i: number) => {
          GridItem() {
            Text(String(c.val))
              .fontSize(this.gridN >= 5 ? 20 : 26)
              .fontWeight(FontWeight.Bold)
              .fontColor(c.found ? '#9fc9b6' : '#2b3a4a')
              .width('100%')
              .height('100%')
              .textAlign(TextAlign.Center)
              .borderRadius(12)
              .backgroundColor(c.found ? '#e8f6ee' : (this.wrongIdx === i ? '#fdecec' : '#ffffff'))
              .border({
                width: 2,
                color: c.found ? '#bfe6d2' : (this.wrongIdx === i ? '#ec7d7d' : '#e3ecf5')
              })
              .onClick(() => {
                if (this.game !== null) {
                  this.game.tap(c.val, i);
                }
              })
          }
          .width(this.cellSize())
          .height(this.cellSize())
        }, (c: CellState, i: number) => 'cell' + i + c.val + (c.found ? 'f' : ''))
      }
      .columnsTemplate(this.columnsTemplate())
      .rowsTemplate(this.rowsTemplate())
      .columnsGap(this.gridGap())
      .rowsGap(this.gridGap())
      .width(this.boardW > 0 ? (this.cellSize() * this.gridN + this.gridGap() * (this.gridN - 1)) : '100%')
      .height(this.boardH > 0 ? (this.cellSize() * this.gridN + this.gridGap() * (this.gridN - 1)) : '100%')
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding(10)
    .onAreaChange((oldV: Area, newV: Area): void => {
      this.boardW = Number(newV.width) - 20;
      this.boardH = Number(newV.height) - 20;
    })
  }

  build() {
    Stack() {
      Column() {
        GameTopBar({
          title: this.level === 1 ? '舒尔特方格 · ' + this.tiers[this.tierIdx].label : '舒尔特方格',
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
                emoji: '🔢',
                title: '舒尔特方格',
                subtitle: '按 1、2、3… 的顺序，又快又准地把数字都点一遍，练专注力',
                tip: '提示：方格越大越难；计时冲你的最快纪录！'
              })
              CardGrid({
                cards: this.tierCards(),
                onPick: (key: string): void => {
                  for (let i: number = 0; i < this.tiers.length; i++) {
                    if (this.tiers[i].key === key) {
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
            this.gridView()
          }
          .layoutWeight(1)
          .width('100%')
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#eaf4ff')

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
              this.startGame(this.tierIdx);
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
