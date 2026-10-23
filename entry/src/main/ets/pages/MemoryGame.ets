/**
 * 子游戏: 翻翻乐 —— 移植自 kids-games/games/memory。
 *
 * 三层页面:
 *   L0 选主题 (8 个) → L1 选难度 (3 档) → L2 翻牌
 *
 * 牌面用网格渲染: 每张牌两个状态 (盖着 = "?", 翻开 = 卡面)。
 * 原实现用 CSS 3D 翻转动画; 这里改成「缩放 + 渐显」的入场动画,
 * 效果取向一致 (翻牌有明确的形态变化), 但不用 3D 变换, 真机上更稳。
 *
 * 匹配判定、计数、连击、消失腾位全部由 games/memory/Engine.ets 负责。
 */
import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { store, BestRecord, RecordResult } from '../games/box/Store';
import { Voice, langOf } from '../games/box/Voice';
import { Confetti } from '../games/box/Confetti';
import { CardGrid, CardInfo, GameTopBar, PageHeading, WinCard, WinInfo, BarButton } from '../games/box/Ui';
import { Theme, Face, buildThemes } from '../games/memory/Themes';
import {
  MemCard, MemTier, MemStats, MemSnapshot, MemHandler, MemoryGame, buildTiers
} from '../games/memory/Engine';
import { paintFlag, flagOf } from '../games/memory/Flags';
import { fmtTime } from '../games/math/Levels';

const DOMAIN: number = 0x0001;
const TAG: string = 'KidsMemory';

/** 一张牌的显示状态 (页面只认这个) */
@Observed
class CardView {
  uid: string = '';
  /** 'back' 盖着 / 'front' 翻开 / 'matched' 已配对 */
  state: string = 'back';
  faceType: string = 'text';
  emoji: string = '';
  text: string = '';
  flagCode: string = '';
  /** 高档配对后消失腾位 */
  removed: boolean = false;
  /** 放错时的抖动标记 */
  miss: boolean = false;

  constructor(card: MemCard) {
    this.uid = card.uid;
    this.faceType = card.face.type;
    this.emoji = card.face.emoji;
    this.text = card.face.text;
    this.flagCode = card.face.code;
  }
}

@Entry
@Component
struct MemoryGamePage {
  @State themes: Theme[] = buildThemes();
  @State tiers: MemTier[] = buildTiers();
  /** 0 选主题 1 选难度 2 翻牌 */
  @State level: number = 0;
  @State themeIdx: number = 0;
  @State tierIdx: number = 0;

  @State cards: CardView[] = [];
  @State cols: number = 3;
  @State rows: number = 4;
  @State stepsText: string = '步数 0';
  @State timerText: string = '⏱️ 00:00';
  @State showTimer: boolean = false;
  @State comboText: string = '';

  @State winVisible: boolean = false;
  @State winInfo: WinInfo = new WinInfo();
  @State confettiPulse: number = 0;
  @State muted: boolean = false;

  private game: MemoryGame | null = null;
  private voice: Voice = new Voice();
  /** 网格尺寸测量, 用来算牌宽 (fitBoard 的原生版) */
  @State boardW: number = 0;
  @State boardH: number = 0;
  /** 国旗画布: uid -> 牌在网格里的位置, 由 Canvas 统一绘制 */
  @State flagUids: string[] = [];

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

  // ===================== 选主题 / 选难度 =====================

  private themeCards(): CardInfo[] {
    const out: CardInfo[] = [];
    for (let i: number = 0; i < this.themes.length; i++) {
      const t: Theme = this.themes[i];
      const card: CardInfo = new CardInfo(t.id, t.icon(), t.name, t.matchLabel());
      card.desc = t.pairs.length + ' 对 · ' + t.categoryLabel();
      card.accent = '#b07be0';
      out.push(card);
    }
    return out;
  }

  private tierCards(): CardInfo[] {
    const t: Theme = this.themes[this.themeIdx];
    const out: CardInfo[] = [];
    for (let i: number = 0; i < this.tiers.length; i++) {
      const tier: MemTier = this.tiers[i];
      const best: BestRecord | null = store.getMemoryBest(t.id, tier.key);
      const card: CardInfo = new CardInfo(tier.key, tier.emoji, tier.label, tier.desc);
      card.accent = '#b07be0';
      if (best === null) {
        card.badge = '未挑战';
      } else if (best.steps >= 0) {
        card.badge = '🏅 最少 ' + best.steps + ' 步' + (best.time >= 0 ? ' · ' + fmtTime(best.time) : '');
      } else {
        card.badge = '🏅 ' + fmtTime(best.time);
      }
      out.push(card);
    }
    return out;
  }

  private startGame(tierIdx: number): void {
    if (this.game !== null) {
      this.game.destroy();
      this.game = null;
    }
    this.tierIdx = tierIdx;
    const theme: Theme = this.themes[this.themeIdx];
    const tier: MemTier = this.tiers[tierIdx];
    this.cols = tier.cols;
    this.rows = tier.rows;
    this.showTimer = tier.timer;
    this.stepsText = '步数 0';
    this.timerText = '⏱️ 00:00';
    this.comboText = '';
    this.winVisible = false;
    this.level = 2;

    const self: MemoryGamePage = this;
    const h: MemHandler = {
      onBuild: (cards: MemCard[]): void => {
        self.onBuild(cards);
      },
      onFlip: (card: MemCard, first: boolean): void => {
        self.flipCard(card.uid, true);
        if (tier.speakOnFlip) {
          self.say(card.say);
        }
      },
      onMatch: (a: MemCard, b: MemCard, say: string, combo: number): void => {
        self.markMatched(a.uid, b.uid, tier.keepLit);
        self.say(say);
        self.comboText = combo >= 2 ? '🔥 连击 ×' + combo : '';
        if (combo >= 3) {
          self.confettiPulse += 0; // 配对不撒全屏彩屑, 只在通关时撒
        }
      },
      onMismatch: (a: MemCard, b: MemCard): void => {
        self.markMiss(a.uid, b.uid, tier.flipMs);
      },
      onTick: (sec: number): void => {
        self.timerText = '⏱️ ' + fmtTime(sec);
      },
      onStats: (snap: MemSnapshot): void => {
        self.stepsText = '步数 ' + snap.steps;
      },
      onWin: (stats: MemStats): void => {
        self.onWin(stats);
      }
    };
    this.game = new MemoryGame(theme, tier, h);
    this.game.build();
  }

  private onBuild(cards: MemCard[]): void {
    const out: CardView[] = [];
    const flags: string[] = [];
    for (let i: number = 0; i < cards.length; i++) {
      out.push(new CardView(cards[i]));
      if (cards[i].face.type === 'flag') {
        flags.push(cards[i].uid);
      }
    }
    this.cards = out;
    this.flagUids = flags;
  }

  private cardIndex(uid: string): number {
    for (let i: number = 0; i < this.cards.length; i++) {
      if (this.cards[i].uid === uid) {
        return i;
      }
    }
    return -1;
  }

  private flipCard(uid: string, up: boolean): void {
    const i: number = this.cardIndex(uid);
    if (i < 0) {
      return;
    }
    const next: CardView[] = this.cards.slice();
    const c: CardView = next[i];
    if (up) {
      c.state = 'front';
    } else if (c.state !== 'matched') {
      c.state = 'back';
    }
    next[i] = c;
    this.cards = next;
  }

  private markMatched(uidA: string, uidB: string, keepLit: boolean): void {
    const next: CardView[] = this.cards.slice();
    const ids: string[] = [uidA, uidB];
    for (let k: number = 0; k < ids.length; k++) {
      const i: number = this.cardIndex(ids[k]);
      if (i < 0) {
        continue;
      }
      const c: CardView = next[i];
      c.state = 'matched';
      next[i] = c;
    }
    this.cards = next;
    if (!keepLit) {
      // 高档: 短暂展示再消失腾位 (保留占位, 防记忆错乱)
      const self: MemoryGamePage = this;
      setTimeout((): void => {
        const after: CardView[] = self.cards.slice();
        for (let k: number = 0; k < ids.length; k++) {
          const i: number = self.cardIndex(ids[k]);
          if (i < 0) {
            continue;
          }
          const c: CardView = after[i];
          c.removed = true;
          after[i] = c;
        }
        self.cards = after;
      }, 600);
    }
  }

  private markMiss(uidA: string, uidB: string, flipMs: number): void {
    const next: CardView[] = this.cards.slice();
    const ids: string[] = [uidA, uidB];
    for (let k: number = 0; k < ids.length; k++) {
      const i: number = this.cardIndex(ids[k]);
      if (i < 0) {
        continue;
      }
      const c: CardView = next[i];
      c.miss = true;
      next[i] = c;
    }
    this.cards = next;
    this.comboText = '';
    const self: MemoryGamePage = this;
    setTimeout((): void => {
      const after: CardView[] = self.cards.slice();
      for (let k: number = 0; k < ids.length; k++) {
        const i: number = self.cardIndex(ids[k]);
        if (i < 0) {
          continue;
        }
        const c: CardView = after[i];
        c.state = 'back';
        c.miss = false;
        after[i] = c;
      }
      self.cards = after;
      if (self.game !== null) {
        self.game.clearMismatch();
      }
    }, flipMs);
  }

  private say(text: string): void {
    if (text.length === 0) {
      return;
    }
    const t: Theme = this.themes[this.themeIdx];
    this.voice.speak(text, langOf(t.sayLang));
  }

  // ===================== 结算 =====================

  private onWin(stats: MemStats): void {
    const rec: RecordResult = store.recordMemoryResult(stats.themeId, stats.tierKey,
      stats.steps, stats.timer ? stats.elapsed : -1);
    const info: WinInfo = new WinInfo();
    info.emoji = '🎉';
    info.title = '全部配对成功！';
    info.metrics.push('👣 步数 ' + stats.steps + (rec.newStepsRecord ? '  新纪录!' : ''));
    if (stats.maxCombo >= 2) {
      info.metrics.push('🔥 最高连击 ' + stats.maxCombo);
    }
    if (stats.timer) {
      info.metrics.push('⏱️ 用时 ' + fmtTime(stats.elapsed) + (rec.newTimeRecord ? '  新纪录!' : ''));
    }
    this.winInfo = info;
    this.winVisible = true;
    this.confettiPulse++;
    this.voice.speak('全部配对成功，你真棒！');
  }

  // ===================== 导航 =====================

  private onBack(): void {
    if (this.game !== null) {
      this.game.destroy();
      this.game = null;
    }
    this.winVisible = false;
    if (this.level === 2) {
      this.level = 1;
      return;
    }
    if (this.level === 1) {
      this.level = 0;
      return;
    }
    this.voice.release();
    router.back();
  }

  // ===================== 界面 =====================

  private topButtons(): BarButton[] {
    const self: MemoryGamePage = this;
    const btns: BarButton[] = [];
    if (this.level === 2) {
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
    if (this.level !== 2) {
      return [];
    }
    const out: string[] = [this.stepsText];
    if (this.showTimer) {
      out.push(this.timerText);
    }
    return out;
  }

  /** 按可用宽高双向算出最大牌宽 (原 fitBoard 的等价算法) */
  private cellW(): number {
    const gap: number = 8;
    const byW: number = (this.boardW - (this.cols - 1) * gap) / this.cols;
    // 牌高 = 牌宽 * 4/3
    const byH: number = ((this.boardH - (this.rows - 1) * gap) / this.rows) * 3 / 4;
    const cell: number = Math.min(byW <= 0 ? 60 : byW, byH <= 0 ? 60 : byH);
    return Math.max(36, Math.floor(cell));
  }

  @Builder
  cardFace(c: CardView) {
    Stack() {
      if (c.state === 'back') {
        Text('?')
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor('#a9c4e6')
      } else if (c.faceType === 'emoji') {
        Text(c.emoji).fontSize(this.cellW() * 0.5)
      } else if (c.faceType === 'flag') {
        FlagCanvas({
          code: c.flagCode,
          sizeW: this.cellW() * 0.66,
          sizeH: this.cellW() * 0.44
        })
      } else {
        Text(c.text)
          .fontSize(this.textSizeFor(c.text))
          .fontWeight(c.text.length <= 2 ? FontWeight.Bold : FontWeight.Medium)
          .fontColor('#2b3a4a')
          .maxLines(2)
          .textAlign(TextAlign.Center)
          .padding({ left: 4, right: 4 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(c.state === 'back' ? '#eaf2fb' : (c.state === 'matched' ? '#e6f7ef' : '#ffffff'))
    .borderRadius(12)
    .border({
      width: c.state === 'back' ? 2 : (c.state === 'matched' ? 2 : 1),
      color: c.miss ? '#ec7d7d' : (c.state === 'matched' ? '#4cc1a1' : '#dbe7f3')
    })
  }

  private textSizeFor(t: string): number {
    const base: number = this.cellW() * 0.42;
    if (t.length <= 2) {
      return Math.max(16, base);
    }
    if (t.length <= 4) {
      return Math.max(13, base * 0.62);
    }
    return Math.max(11, base * 0.46);
  }

  @Builder
  boardView() {
    Column() {
      if (this.comboText.length > 0) {
        Text(this.comboText)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor('#f08a4b')
          .margin({ bottom: 6 })
      }
      Grid() {
        ForEach(this.cards, (c: CardView) => {
          GridItem() {
            if (c.removed) {
              // 腾位: 保留空白占位, 不再显示卡面
              Column().width('100%').height('100%')
            } else {
              this.cardFace(c)
            }
          }
          .width(this.cellW())
          .height(this.cellW() * 4 / 3)
          .animation({ duration: 180, curve: Curve.EaseOut })
          .onClick(() => {
            if (this.game !== null && !c.removed) {
              this.game.flip(c.uid);
            }
          })
        }, (c: CardView) => c.uid + c.state + (c.removed ? 'r' : '') + (c.miss ? 'm' : ''))
      }
      .columnsTemplate(this.columnsTemplate())
      .rowsGap(8)
      .columnsGap(8)
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .padding(8)
    .onAreaChange((oldV: Area, newV: Area): void => {
      this.boardW = Number(newV.width) - 16;
      this.boardH = Number(newV.height) - 16;
    })
  }

  private columnsTemplate(): string {
    let t: string = '';
    for (let i: number = 0; i < this.cols; i++) {
      t += (i === 0 ? '1fr' : ' 1fr');
    }
    return t;
  }

  build() {
    Stack() {
      Column() {
        GameTopBar({
          title: this.level === 2 ? this.themes[this.themeIdx].name : '翻翻乐',
          stats: this.stats(),
          buttons: this.topButtons(),
          backText: '‹ 返回',
          onBack: (): void => {
            this.onBack();
          }
        })

        if (this.level === 0) {
          Scroll() {
            Column() {
              PageHeading({
                emoji: '🃏',
                title: '翻翻乐',
                subtitle: '翻牌找一对。八个主题：动物水果、汉字拼音、反义词、单词字母、国旗省会',
                tip: '提示：低龄档配对后留亮不计时，高档会消失腾位还要计时。'
              })
              CardGrid({
                cards: this.themeCards(),
                onPick: (key: string): void => {
                  for (let i: number = 0; i < this.themes.length; i++) {
                    if (this.themes[i].id === key) {
                      this.themeIdx = i;
                      this.level = 1;
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
                emoji: this.themes[this.themeIdx].icon(),
                title: this.themes[this.themeIdx].name + ' · 选难度',
                subtitle: this.themes[this.themeIdx].matchLabel() + '：' + this.themes[this.themeIdx].name
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
            this.boardView()
          }
          .layoutWeight(1)
          .width('100%')
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#fdf3e7')

      Confetti({ pulse: this.confettiPulse })

      if (this.winVisible) {
        Column() {
          WinCard({
            info: this.winInfo,
            onAgain: (): void => {
              this.startGame(this.tierIdx);
            },
            onBack: (): void => {
              this.level = 1;
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

/** 一面旗: 单独的小画布, 避免在网格里塞 SVG */
@Component
struct FlagCanvas {
  @Prop code: string = '';
  @Prop sizeW: number = 40;
  @Prop sizeH: number = 27;
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  build() {
    Canvas(this.ctx)
      .width(this.sizeW)
      .height(this.sizeH)
      .onReady((): void => {
        this.ctx.clearRect(0, 0, this.sizeW, this.sizeH);
        if (flagOf(this.code) !== null) {
          paintFlag(this.ctx, this.code, 0, 0, this.sizeW, this.sizeH);
        }
      })
  }
}
