/**
 * 子游戏: 奇妙迷宫 (99 关) —— 移植自 kids-maze-game。
 *
 * 两层页面: 选关网格 (99 个主题卡) → 走迷宫。
 *
 * 渲染策略: 整张迷宫画在**一块 Canvas** 上, 不给每格加 border。
 * 原因: 原实现给每个 cell 设 4 条边的 border 宽度, 但 45×45=2025 个带四边
 * 边框的 ArkUI 节点太重, 且小尺寸下边框像素会被挤压。Canvas 一次画完所有墙线,
 * 节点数恒为 1, 45×45 也是满帧。
 *
 * 交互与原实现一致: 撞墙只抖一下 (不扣分不失败), 到终点后 3 秒自动进下一关。
 */
import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Voice } from '../games/box/Voice';
import { store } from '../games/box/Store';
import { Confetti } from '../games/box/Confetti';
import { GameTopBar, PageHeading, WinCard, WinInfo, BarButton } from '../games/box/Ui';
import {
  Cell, MazeLevel, MazeTheme, MazeLoader, WALL_N, WALL_E, WALL_S, WALL_W,
  tryMove, isAtGoal, themeFor, MoveResult
} from '../games/maze99/MazeLevels';

const DOMAIN: number = 0x0001;
const TAG: string = 'KidsMaze99';
const CLEARED_KEY: string = 'kids_maze_cleared';
const WIN_COUNTDOWN_SEC: number = 3;

@Entry
@Component
struct KidsMazePage {
  /** 0 选关 1 走迷宫 */
  @State level: number = 0;
  @State levels: MazeLevel[] = [];
  @State curIndex: number = 0;
  @State gridN: number = 10;
  @State title: string = '';
  @State playerEmoji: string = '🐰';
  @State goalEmoji: string = '🏠';

  // 主题色 (随关卡切换)
  @State colBg: string = '#e8f5d8';
  @State colInk: string = '#2a3b1f';
  @State colWall: string = '#6b8f4e';
  @State colPath: string = '#fff8e7';
  @State colAccent: string = '#f0a83a';

  @State clearedIds: string[] = [];
  @State bumping: boolean = false;
  @State winVisible: boolean = false;
  @State countdown: number = 0;
  @State winInfo: WinInfo = new WinInfo();
  @State confettiPulse: number = 0;
  @State muted: boolean = false;
  @State soundOn: boolean = true;

  private mazeSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private mazeCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.mazeSettings);
  private loader: MazeLoader = new MazeLoader();
  private voice: Voice = new Voice();
  private pos: Cell = new Cell(0, 0);
  private moveLocked: boolean = false;
  private countdownTimer: number = -1;
  /** 网格实测尺寸, 用来算格子大小 */
  @State gW: number = 0;
  @State gH: number = 0;
  /** 玩家/终点在画布里的中心位置 (vp), 供叠加的 Text 定位 */
  @State playerX: number = 0;
  @State playerY: number = 0;
  @State goalX: number = 0;
  @State goalY: number = 0;
  @State cellPxCache: number = 0;

  aboutToAppear(): void {
    const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    try {
      store.init(ctx);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'store init failed');
    }
    this.loader.init(ctx);
    this.voice.load(store);
    this.muted = this.voice.isMuted();
    this.levels = this.loader.levels();
    this.clearedIds = this.loadCleared(ctx);
    if (this.levels.length === 0) {
      this.title = '关卡数据加载失败';
    }
  }

  aboutToDisappear(): void {
    this.clearCountdown();
    this.voice.release();
  }

  // ===================== 通关记录 (原 localStorage 键 kids-maze-cleared) ----------

  private loadCleared(ctx: common.UIAbilityContext): string[] {
    try {
      const opt: preferences.Options = { name: 'kg_maze' };
      const p: preferences.Preferences = preferences.getPreferencesSync(ctx, opt);
      const raw: preferences.ValueType = p.getSync(CLEARED_KEY, '');
      if (typeof raw !== 'string' || (raw as string).length === 0) {
        return [];
      }
      const arr: string[] = JSON.parse(raw as string) as string[];
      return arr;
    } catch (e) {
      return [];
    }
  }

  private markCleared(ctx: common.UIAbilityContext, id: string): void {
    if (this.clearedIds.indexOf(id) >= 0) {
      return;
    }
    const next: string[] = this.clearedIds.slice();
    next.push(id);
    this.clearedIds = next;
    try {
      const opt: preferences.Options = { name: 'kg_maze' };
      const p: preferences.Preferences = preferences.getPreferencesSync(ctx, opt);
      p.putSync(CLEARED_KEY, JSON.stringify(next));
      p.flush();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'save cleared failed');
    }
  }

  private isCleared(id: string): boolean {
    return this.clearedIds.indexOf(id) >= 0;
  }

  // ===================== 开局 =====================

  private startLevel(i: number): void {
    if (i < 0 || i >= this.levels.length) {
      return;
    }
    this.clearCountdown();
    this.curIndex = i;
    const lv: MazeLevel = this.levels[i];
    this.gridN = lv.size;
    this.title = lv.title;
    this.playerEmoji = lv.playerEmoji;
    this.goalEmoji = lv.goalEmoji;
    const t: MazeTheme = themeFor(lv);
    this.colBg = t.bg;
    this.colInk = t.ink;
    this.colWall = t.wall;
    this.colPath = t.path;
    this.colAccent = t.accent;

    this.pos = new Cell(lv.start.r, lv.start.c);
    this.moveLocked = false;
    this.winVisible = false;
    this.bumping = false;
    this.level = 1;
    // 等布局稳定后再画 (Canvas 尺寸要等 onAreaChange)
    setTimeout((): void => {
      this.paintMaze();
    }, 0);
  }

  /** 重绘 (走一步或换关后调用) */
  private repaint(): void {
    this.paintMaze();
  }

  private move(dir: string): void {
    if (this.moveLocked || this.level !== 1) {
      return;
    }
    const lv: MazeLevel = this.levels[this.curIndex];
    const res: MoveResult = tryMove(lv, this.pos, dir);
    if (res.bumped) {
      this.bump();
      return;
    }
    this.pos = res.pos;
    this.repaint();
    if (isAtGoal(lv, this.pos)) {
      this.win();
    }
  }

  private bump(): void {
    this.bumping = true;
    setTimeout((): void => {
      this.bumping = false;
    }, 220);
  }

  private win(): void {
    this.moveLocked = true;
    const lv: MazeLevel = this.levels[this.curIndex];
    this.markCleared(getContext(this) as common.UIAbilityContext, lv.id);
    this.confettiPulse++;

    const hasNext: boolean = this.curIndex < this.levels.length - 1;
    const info: WinInfo = new WinInfo();
    info.emoji = '⭐';
    info.title = '太棒了！';
    if (!hasNext) {
      info.metrics.push('全部通关啦！');
      info.againText = '回到选关';
    } else {
      info.metrics.push(this.countdown > 0 ? this.countdown + ' 秒后进入下一关' : '正在进入下一关…');
      info.againText = '下一关';
    }
    this.winInfo = info;
    this.winVisible = true;
    this.startCountdown();
  }

  private startCountdown(): void {
    this.clearCountdown();
    const hasNext: boolean = this.curIndex < this.levels.length - 1;
    if (!hasNext) {
      return;
    }
    this.countdown = WIN_COUNTDOWN_SEC;
    this.refreshWinMetrics();
    this.countdownTimer = setInterval((): void => {
      this.countdown--;
      if (this.countdown <= 0) {
        this.clearCountdown();
        this.nextLevel();
        return;
      }
      this.refreshWinMetrics();
    }, 1000);
  }

  private refreshWinMetrics(): void {
    const info: WinInfo = new WinInfo();
    info.emoji = '⭐';
    info.title = '太棒了！';
    info.againText = '下一关';
    info.metrics.push(this.countdown > 0 ? this.countdown + ' 秒后进入下一关' : '正在进入下一关…');
    this.winInfo = info;
  }

  private clearCountdown(): void {
    if (this.countdownTimer >= 0) {
      clearInterval(this.countdownTimer);
      this.countdownTimer = -1;
    }
  }

  private nextLevel(): void {
    this.winVisible = false;
    if (this.curIndex < this.levels.length - 1) {
      this.startLevel(this.curIndex + 1);
    } else {
      this.level = 0;
    }
  }

  // ===================== 布局 =====================

  /** 每格边长 (vp): 取宽高可容纳的较小值 */
  private cellPx(): number {
    if (this.gW <= 0 || this.gH <= 0) {
      return 0;
    }
    return Math.max(4, Math.floor(Math.min(this.gW, this.gH) / this.gridN));
  }

  /**
   * 把整张迷宫画到 Canvas 上。
   * 墙宽随格子缩放 (最细 1px, 保证小格也看得见), 玩家/终点用 emoji 画。
   */
  private paintMaze(): void {
    const px: number = this.cellPx();
    if (px <= 0 || this.level !== 1) {
      return;
    }
    const lv: MazeLevel = this.levels[this.curIndex];
    const side: number = px * this.gridN;
    const ox: number = Math.floor((this.gW - side) / 2);
    const oy: number = Math.floor((this.gH - side) / 2);
    const ctx: CanvasRenderingContext2D = this.mazeCtx;

    ctx.clearRect(0, 0, this.gW + 20, this.gH + 20);
    // 地板
    ctx.fillStyle = this.colPath;
    ctx.fillRect(ox, oy, side, side);
    // 终点格
    ctx.fillStyle = this.colAccent;
    ctx.globalAlpha = 0.35;
    ctx.fillRect(ox + lv.goal.c * px, oy + lv.goal.r * px, px, px);
    ctx.globalAlpha = 1;

    // 墙: 逐格画有墙的边 (相邻两格各自画一半, 保证视觉是整条线)
    const lw: number = Math.max(1, Math.min(3, px * 0.12));
    ctx.strokeStyle = this.colWall;
    ctx.lineWidth = lw;
    ctx.lineCap = 'round';
    ctx.beginPath();
    for (let r: number = 0; r < lv.size; r++) {
      for (let c: number = 0; c < lv.size; c++) {
        const w: number = lv.cells[r][c];
        const x0: number = ox + c * px;
        const y0: number = oy + r * px;
        if ((w & WALL_N) !== 0) {
          ctx.moveTo(x0, y0);
          ctx.lineTo(x0 + px, y0);
        }
        if ((w & WALL_W) !== 0) {
          ctx.moveTo(x0, y0);
          ctx.lineTo(x0, y0 + px);
        }
        // 只画右/下边会造成外框缺口, 所以最右列和最下行补上
        if ((w & WALL_E) !== 0 && c === lv.size - 1) {
          ctx.moveTo(x0 + px, y0);
          ctx.lineTo(x0 + px, y0 + px);
        }
        if ((w & WALL_S) !== 0 && r === lv.size - 1) {
          ctx.moveTo(x0, y0 + px);
          ctx.lineTo(x0 + px, y0 + px);
        }
      }
    }
    ctx.stroke();

    // 终点/玩家标记改用叠加的 Text 组件 (Canvas 的 fillText 不渲染 emoji),
    // 位置由这里算好写进状态
    this.goalX = ox + (lv.goal.c + 0.5) * px;
    this.goalY = oy + (lv.goal.r + 0.5) * px;
    this.playerX = ox + (this.pos.c + 0.5) * px;
    this.playerY = oy + (this.pos.r + 0.5) * px;
    this.cellPxCache = px;
  }

  // ===================== 界面 =====================

  private topButtons(): BarButton[] {
    const self: KidsMazePage = this;
    const btns: BarButton[] = [];
    if (this.level === 1) {
      btns.push(new BarButton('重来', (): void => {
        self.startLevel(self.curIndex);
      }));
    }
    btns.push(new BarButton(this.muted ? '🔇' : '🔊', (): void => {
      self.muted = self.voice.toggleMute(store);
    }));
    return btns;
  }

  @Builder
  mazeView() {
    Column() {
      Column() {
        Stack() {
          Canvas(this.mazeCtx)
            .width('100%')
            .height('100%')
            .onReady((): void => {
              this.paintMaze();
            })
            .onAreaChange((oldV: Area, newV: Area): void => {
              this.gW = Number(newV.width);
              this.gH = Number(newV.height);
              this.paintMaze();
            })
          if (this.cellPxCache > 0) {
            // 终点
            Text(this.goalEmoji)
              .fontSize(this.cellPxCache * 0.78)
              .position({ x: this.goalX - this.cellPxCache / 2, y: this.goalY - this.cellPxCache / 2 })
              .width(this.cellPxCache)
              .height(this.cellPxCache)
              .textAlign(TextAlign.Center)
              .hitTestBehavior(HitTestMode.None)
            // 玩家
            Text(this.playerEmoji)
              .fontSize(this.cellPxCache * 0.82)
              .position({ x: this.playerX - this.cellPxCache / 2, y: this.playerY - this.cellPxCache / 2 })
              .width(this.cellPxCache)
              .height(this.cellPxCache)
              .textAlign(TextAlign.Center)
              .scale({ x: this.bumping ? 1.18 : 1, y: this.bumping ? 0.88 : 1 })
              .animation({ duration: 160, curve: Curve.EaseOut })
              .hitTestBehavior(HitTestMode.None)
          }
        }
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .layoutWeight(1)
      .constraintSize({ minWidth: '100%' })
      .alignItems(HorizontalAlign.Center)
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })

      // 方向键 (原 .dpad): 上 / 左 右 / 下
      Column() {
        Text('▲')
          .fontSize(26)
          .fontColor(this.colInk)
          .width(76)
          .height(58)
          .textAlign(TextAlign.Center)
          .borderRadius(18)
          .backgroundColor(this.colAccent)
          .scale({ x: this.bumping ? 0.96 : 1, y: this.bumping ? 0.96 : 1 })
          .animation({ duration: 140, curve: Curve.EaseOut })
          .onClick((): void => {
            this.move('N');
          })
        Row() {
          Text('◀')
            .fontSize(26)
            .fontColor(this.colInk)
            .width(76)
            .height(58)
            .textAlign(TextAlign.Center)
            .borderRadius(18)
            .backgroundColor(this.colAccent)
            .margin({ right: 14 })
            .onClick((): void => {
              this.move('W');
            })
          Text('▶')
            .fontSize(26)
            .fontColor(this.colInk)
            .width(76)
            .height(58)
            .textAlign(TextAlign.Center)
            .borderRadius(18)
            .backgroundColor(this.colAccent)
            .margin({ left: 14 })
            .onClick((): void => {
              this.move('E');
            })
        }
        .margin({ top: 8, bottom: 8 })
        Text('▼')
          .fontSize(26)
          .fontColor(this.colInk)
          .width(76)
          .height(58)
          .textAlign(TextAlign.Center)
          .borderRadius(18)
          .backgroundColor(this.colAccent)
          .onClick((): void => {
            this.move('S');
          })
      }
      .width('100%')
      .padding({ top: 2, bottom: 12 })
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  levelGrid() {
    Scroll() {
      Column() {
        PageHeading({
          emoji: '🌀',
          title: '奇妙迷宫',
          subtitle: '点一个就开始玩 · 用方向键走到终点',
          tip: this.levels.length > 0 ? '共 ' + this.levels.length + ' 关，通关 ' + this.clearedIds.length + ' 关' : ''
        })
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.levels, (lv: MazeLevel, i: number) => {
            Column() {
              Text(lv.playerEmoji)
                .fontSize(24)
              Text(String(i + 1))
                .fontSize(11)
                .fontColor(this.isCleared(lv.id) ? '#f0a83a' : '#8fa0b4')
                .fontWeight(FontWeight.Bold)
                .margin({ top: 1 })
            }
            .width('21%')
            .height(66)
            .justifyContent(FlexAlign.Center)
            .backgroundColor(this.isCleared(lv.id) ? '#fff8e7' : '#ffffff')
            .borderRadius(14)
            .border({
              width: 2,
              color: this.isCleared(lv.id) ? '#f0a83a' : '#e3ecf5'
            })
            .margin({ right: '3.2%', bottom: 8 })
            .onClick((): void => {
              this.startLevel(i);
            })
          }, (lv: MazeLevel, i: number) => lv.id + (this.isCleared(lv.id) ? 'c' : ''))
        }
        .width('100%')
        Blank().height(20)
      }
      .width('100%')
      .padding({ left: 14, right: 14 })
    }
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  build() {
    Stack() {
      Column() {
        GameTopBar({
          title: this.level === 1 ? this.title : '奇妙迷宫',
          stats: this.level === 1 ? ['第 ' + (this.curIndex + 1) + '/' + this.levels.length + ' 关'] : [],
          buttons: this.topButtons(),
          backText: '‹ 返回',
          onBack: (): void => {
            this.clearCountdown();
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
          this.levelGrid()
        } else {
          this.mazeView()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.level === 1 ? this.colBg : '#eaf4ff')

      Confetti({ pulse: this.confettiPulse })

      if (this.winVisible) {
        Column() {
          WinCard({
            info: this.winInfo,
            onAgain: (): void => {
              this.nextLevel();
            },
            onBack: (): void => {
              this.clearCountdown();
              this.winVisible = false;
              this.level = 0;
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
