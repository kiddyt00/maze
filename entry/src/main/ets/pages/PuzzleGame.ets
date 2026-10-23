/**
 * 子游戏: 拼拼中国 —— 移植自 kids-games/games/puzzle。
 *
 * 三层页面:
 *   L0 选玩法 (拼全国 / 分省) → L1 选难度 或 选省份 → L2 拼图
 *
 * 拼图交互的关键设计 (与原实现一致):
 *  - 拖拽判定看「落点离该块重心的距离 < 吸附半径」, 不看形状重合, 孩子手指不必精确;
 *  - 吸附半径按难度收缩 (简单 58 / 中等 32 / 困难 18 / 分省用各省 snapHint);
 *  - 只有真的拖到棋盘上却放错, 才记一次失误; 在托盘里随手松开不罚;
 *  - 简单档按七大区分 7 关, 一关一关来, 还有省名提示和拼音。
 *
 * 渲染是一整块 Canvas (见 games/puzzle/Renderer.ets), 拖拽时只额外画浮层。
 */
import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { store } from '../games/box/Store';
import { Voice } from '../games/box/Voice';
import { Confetti } from '../games/box/Confetti';
import { CardGrid, CardInfo, GameTopBar, PageHeading, WinCard, WinInfo, BarButton } from '../games/box/Ui';
import { Dataset, Piece, MapLoader, ProvinceEntry } from '../games/puzzle/MapData';
import {
  PuzzleDiff, PuzzleGame, PuzzleHandler, PuzzleStats, BoardMap,
  buildNationalDiffs, buildProvinceDiff
} from '../games/puzzle/Puzzle';
import { drawBoard, drawDragClone, drawTrayPiece, boardMap } from '../games/puzzle/Renderer';
import { fmtTime } from '../games/math/Levels';

const DOMAIN: number = 0x0001;
const TAG: string = 'KidsPuzzle';

/** 托盘里的一块: 画在小画布上 */
@Observed
class TrayItem {
  pieceIndex: number = 0;
  name: string = '';
  pinyin: string = '';
  /** 画布是否已就绪 (就绪后立即补画, 避免首帧空白) */
  drawn: boolean = false;

  constructor(pieceIndex: number, name: string, pinyin: string) {
    this.pieceIndex = pieceIndex;
    this.name = name;
    this.pinyin = pinyin;
  }
}

@Entry
@Component
struct PuzzleGamePage {
  /** 0 选玩法 1 选难度/选省 2 拼图 */
  @State level: number = 0;
  @State mode: string = 'national'; // 'national' | 'province'
  @State diffIdx: number = 0;

  @State nationalDiffs: PuzzleDiff[] = buildNationalDiffs();
  @State provinceList: ProvinceEntry[] = [];

  // ---- 拼图状态 ----
  @State tray: TrayItem[] = [];
  @State placedCount: number = 0;
  @State totalCount: number = 0;
  @State levelText: string = '';
  @State progressText: string = '';
  @State timerText: string = '';
  @State showTimer: boolean = false;
  @State errorsText: string = '';
  @State showErrors: boolean = false;
  /** 当前高亮的大区 (简单档分关) */
  @State activeRegion: string = '';

  // ---- 拖拽 ----
  @State dragging: boolean = false;
  @State dragCx: number = 0;
  @State dragCy: number = 0;
  @State dragName: string = '';

  @State loading: boolean = false;
  @State loadError: string = '';
  @State winVisible: boolean = false;
  @State winInfo: WinInfo = new WinInfo();
  @State confettiPulse: number = 0;
  @State muted: boolean = false;

  private game: PuzzleGame | null = null;
  private dataset: Dataset | null = null;
  private diff: PuzzleDiff = buildProvinceDiff();
  private voice: Voice = new Voice();
  private loader: MapLoader = new MapLoader();

  /** 棋盘画布 */
  private boardSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private boardCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.boardSettings);
  private map: BoardMap = new BoardMap();
  /** 棋盘几何: Canvas 在整页里的偏移 + 尺寸 (vp), 由 areaChange 得到 */
  @State boardX: number = 0;
  @State boardY: number = 0;
  @State boardW: number = 0;
  @State boardH: number = 0;
  /** 正在拖的块 */
  private dragPiece: number = -1;

  aboutToAppear(): void {
    try {
      store.init(getContext(this) as common.UIAbilityContext);
      this.loader.init(getContext(this) as common.UIAbilityContext);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'store/loader init failed');
    }
    this.voice.load(store);
    this.muted = this.voice.isMuted();
    this.provinceList = this.loader.provinceIndex();
  }

  aboutToDisappear(): void {
    if (this.game !== null) {
      this.game.destroy();
      this.game = null;
    }
    this.voice.release();
  }

  // ===================== 选玩法 / 选难度 =====================

  private modeCards(): CardInfo[] {
    const a: CardInfo = new CardInfo('national', '🇨🇳', '拼全国', '34 个省级行政区');
    a.desc = '把 34 个省级行政区拼回祖国版图，分三档难度';
    a.accent = '#ec7d7d';
    const b: CardInfo = new CardInfo('province', '🗺️', '分省拼图', '各省下辖地级市');
    b.desc = '选一个省，把它的各个地级市拼成全省地图';
    b.accent = '#5b9be8';
    return [a, b];
  }

  private diffCards(): CardInfo[] {
    const out: CardInfo[] = [];
    for (let i: number = 0; i < this.nationalDiffs.length; i++) {
      const d: PuzzleDiff = this.nationalDiffs[i];
      const card: CardInfo = new CardInfo(d.key, d.emoji, d.label, d.age);
      card.desc = d.desc;
      card.accent = '#ec7d7d';
      out.push(card);
    }
    return out;
  }

  private provinceCards(): CardInfo[] {
    const out: CardInfo[] = [];
    for (let i: number = 0; i < this.provinceList.length; i++) {
      const e: ProvinceEntry = this.provinceList[i];
      const card: CardInfo = new CardInfo(e.id, '🗺️', e.name, e.pieces + ' 个地市');
      card.accent = '#5b9be8';
      out.push(card);
    }
    return out;
  }

  // ===================== 开局 =====================

  private startNational(idx: number): void {
    const ds: Dataset | null = this.loader.national();
    if (ds === null) {
      this.loadError = '地图数据读取失败';
      return;
    }
    this.diffIdx = idx;
    this.diff = this.nationalDiffs[idx];
    this.startWith(this.diff, ds);
  }

  private startProvince(adcode: string): void {
    const ds: Dataset | null = this.loader.province(adcode);
    if (ds === null) {
      this.loadError = '这个省的地图数据读取失败';
      return;
    }
    this.diff = buildProvinceDiff();
    this.startWith(this.diff, ds);
  }

  private startWith(diff: PuzzleDiff, ds: Dataset): void {
    if (this.game !== null) {
      this.game.destroy();
      this.game = null;
    }
    this.dataset = ds;
    this.diff = diff;
    this.loadError = '';
    this.winVisible = false;
    this.placedCount = 0;
    this.totalCount = ds.items.length;
    this.timerText = '⏱️ 00:00';
    this.showTimer = diff.timer;
    this.errorsText = '❌ 0';
    this.showErrors = diff.timer || diff.key === 'medium' || !ds.byRegionCapable;
    this.activeRegion = '';
    this.dragPiece = -1;
    this.dragging = false;
    this.level = 2;

    const self: PuzzleGamePage = this;
    const h: PuzzleHandler = {
      onPlaced: (pieceIndex: number, remaining: number): void => {
        self.onPlaced(pieceIndex, remaining);
      },
      onError: (errors: number): void => {
        self.errorsText = '❌ ' + errors;
        self.voice.speak('再试试');
      },
      onLevel: (levelIndex: number, regionName: string, batch: number[]): void => {
        self.onLevel(levelIndex, regionName, batch);
      },
      onTick: (sec: number): void => {
        self.timerText = '⏱️ ' + fmtTime(sec);
      },
      onWin: (stats: PuzzleStats): void => {
        self.onWin(stats);
      }
    };
    this.game = new PuzzleGame(diff, ds, h);
    this.game.start();
  }

  private onLevel(levelIndex: number, regionName: string, batch: number[]): void {
    if (this.dataset === null || this.game === null) {
      return;
    }
    const byRegion: boolean = this.game.byRegion;
    this.activeRegion = byRegion ? regionName : '';
    if (byRegion) {
      this.levelText = '第 ' + (levelIndex + 1) + '/' + this.game.regions.length + ' 关 · ' + regionName;
    } else if (this.dataset.byRegionCapable) {
      this.levelText = this.diff.emoji + ' ' + this.diff.label;
    } else {
      this.levelText = '🗺️ ' + this.dataset.name;
    }
    this.refreshTray();
    this.redraw();
  }

  /** 把"还没放对、且属于当前关"的块塞进托盘 */
  private refreshTray(): void {
    if (this.game === null || this.dataset === null) {
      return;
    }
    const rest: number[] = this.game.remainingBatch();
    // 洗牌, 与原实现一致
    for (let i: number = rest.length - 1; i > 0; i--) {
      const j: number = Math.floor(Math.random() * (i + 1));
      const t: number = rest[i];
      rest[i] = rest[j];
      rest[j] = t;
    }
    const out: TrayItem[] = [];
    for (let i: number = 0; i < rest.length; i++) {
      const p: Piece = this.dataset.items[rest[i]];
      out.push(new TrayItem(rest[i], p.name, p.pinyin));
    }
    this.tray = out;
    this.placedCount = this.dataset.items.length - this.game.remainingBatch().length;
    this.progressText = this.game.byRegion
      ? '本关 ' + (this.game.currentBatch().length - this.game.remainingBatch().length)
        + '/' + this.game.currentBatch().length
      : '已拼 ' + this.placedCount + '/' + this.dataset.items.length;
  }

  private onPlaced(pieceIndex: number, remaining: number): void {
    if (this.dataset === null || this.game === null) {
      return;
    }
    const p: Piece = this.dataset.items[pieceIndex];
    if (this.diff.speakOnPlace) {
      this.voice.speak(p.name);
    }
    // 从托盘里移除
    const kept: TrayItem[] = [];
    for (let i: number = 0; i < this.tray.length; i++) {
      if (this.tray[i].pieceIndex !== pieceIndex) {
        kept.push(this.tray[i]);
      }
    }
    this.tray = kept;
    this.placedCount = this.dataset.items.length - this.game.remainingBatch().length;
    this.progressText = this.game.byRegion
      ? '本关 ' + (this.game.currentBatch().length - this.game.remainingBatch().length)
        + '/' + this.game.currentBatch().length
      : '已拼 ' + this.placedCount + '/' + this.dataset.items.length;
    this.redraw();
  }

  private onWin(stats: PuzzleStats): void {
    const info: WinInfo = new WinInfo();
    info.emoji = '🎉';
    if (!stats.byRegionCapable) {
      info.title = '拼好啦！';
      info.metrics.push('你把 ' + stats.name + ' 的 ' + stats.total + ' 个地市都拼好啦！');
    } else {
      info.title = '全部拼好啦！';
      info.metrics.push('你认识了全部 ' + stats.total + ' 个省级行政区，真厉害！');
    }
    if (stats.diff.timer) {
      info.metrics.push('⏱️ 用时 ' + fmtTime(stats.elapsed));
      info.metrics.push('❌ 放错 ' + stats.errors + ' 次');
    } else if (stats.diff.key === 'medium' || !stats.byRegionCapable) {
      info.metrics.push('❌ 放错 ' + stats.errors + ' 次');
    }
    this.winInfo = info;
    this.winVisible = true;
    this.confettiPulse++;
    this.voice.speak('全部拼好啦，你真棒！');
  }

  // ===================== 渲染 =====================

  private redraw(): void {
    if (this.dataset === null || this.boardW <= 0) {
      return;
    }
    const placed: Set<number> = this.game === null ? new Set<number>() : this.game.placed;
    this.map = boardMap(this.boardW, this.boardH, this.dataset);
    drawBoard(this.boardCtx, this.dataset, this.diff, this.map, placed,
      this.activeRegion, this.diff.outlineNames);
    if (this.dragging && this.dragPiece >= 0) {
      const p: Piece = this.dataset.items[this.dragPiece];
      drawDragClone(this.boardCtx, p, this.diff, this.map,
        this.dragCx - this.boardX, this.dragCy - this.boardY);
    }
  }

  // ===================== 触摸: 拖拽 =====================

  private onTouchBoard(event: TouchEvent): void {
    if (this.game === null || this.dataset === null) {
      return;
    }
    // 落点无块可拖时, 棋盘上的触摸不做事 (托盘负责拿起)
    if (this.dragPiece < 0) {
      return;
    }
    if (event.touches.length === 0) {
      return;
    }
    const t: TouchObject = event.touches[0];
    const type: TouchType = event.type;
    if (type === TouchType.Move) {
      this.dragCx = t.x;
      this.dragCy = t.y;
      this.redraw();
    } else if (type === TouchType.Up || type === TouchType.Cancel) {
      this.finishDrag(t.x, t.y);
    }
  }

  /** 从托盘拿起一块 (托盘各自处理自己的手指) */
  private pickUp(pieceIndex: number, globalX: number, globalY: number): void {
    this.dragPiece = pieceIndex;
    this.dragging = true;
    this.dragCx = globalX;
    this.dragCy = globalY;
    if (this.dataset !== null) {
      this.dragName = this.dataset.items[pieceIndex].name;
    }
    if (this.diff.speakOnPick) {
      this.voice.speak(this.dragName);
    }
    this.redraw();
  }

  private finishDrag(globalX: number, globalY: number): void {
    if (this.game === null || this.dataset === null || this.dragPiece < 0) {
      return;
    }
    const piece: number = this.dragPiece;
    this.dragPiece = -1;
    this.dragging = false;
    // 手指位置 → 棋盘内 vp → 地图坐标
    const localX: number = globalX - this.boardX;
    const localY: number = globalY - this.boardY;
    const overBoard: boolean = localX >= 0 && localY >= 0
      && localX <= this.boardW && localY <= this.boardH;
    const bx: number = (localX - this.map.ox) / this.map.scale;
    const by: number = (localY - this.map.oy) / this.map.scale;
    const r: string = this.game.drop(piece, bx, by, overBoard);
    if (r === 'miss') {
      hilog.info(DOMAIN, TAG, 'miss drop at %{public}f,%{public}f', bx, by);
    }
    this.redraw();
  }

  // ===================== 界面 =====================

  private topButtons(): BarButton[] {
    const self: PuzzleGamePage = this;
    const btns: BarButton[] = [];
    if (this.level === 2) {
      btns.push(new BarButton('重玩', (): void => {
        if (self.dataset !== null) {
          self.startWith(self.diff, self.dataset);
        }
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
    if (this.progressText.length > 0) {
      out.push(this.progressText);
    }
    if (this.showTimer) {
      out.push(this.timerText);
    }
    if (this.showErrors) {
      out.push(this.errorsText);
    }
    return out;
  }

  @Builder
  boardView() {
    Column() {
      Row() {
        Text(this.levelText)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#3f7fcf')
          .layoutWeight(1)
        Text('把拼块拖到地图上正确的位置 👇')
          .fontSize(11)
          .fontColor('#8fa0b4')
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 4, bottom: 4 })

      Stack() {
        // 棋盘
        Canvas(this.boardCtx)
          .width('100%')
          .height('100%')
          .borderRadius(12)
          .onReady((): void => {
            this.redraw();
          })
          .onAreaChange((oldV: Area, newV: Area): void => {
            this.boardW = Number(newV.width);
            this.boardH = Number(newV.height);
            this.redraw();
          })
          .onTouch((e: TouchEvent): void => {
            this.onTouchBoard(e);
          })
      }
      .width('100%')
      .layoutWeight(3)
      .backgroundColor('#ffffff')
      .borderRadius(12)
      .shadow({ radius: 10, color: '#1a28461a', offsetX: 0, offsetY: 2 })
      .onAreaChange((oldV: Area, newV: Area): void => {
        // Stack 的 areaChange 只给相对页面的偏移; 先记下来, 供坐标换算
        const pos: Area = newV as Area;
        this.boardX = Number(pos.position.x);
        this.boardY = Number(pos.position.y);
      })

      // 托盘
      Column() {
        Text('拼块 · 剩 ' + this.tray.length + ' 块')
          .fontSize(12)
          .fontColor('#8fa0b4')
          .margin({ bottom: 4 })
        Scroll() {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.tray, (it: TrayItem) => {
              Column() {
                TrayPiece({
                  dataset: this.dataset,
                  pieceIndex: it.pieceIndex,
                  name: it.name,
                  pinyin: this.diff.piecePinyin ? it.pinyin : '',
                  showName: this.diff.pieceName,
                  sizeVp: 72,
                  onTouchDown: (gx: number, gy: number): void => {
                    this.pickUp(it.pieceIndex, gx, gy);
                  },
                  onTouchMove: (gx: number, gy: number): void => {
                    if (this.dragPiece === it.pieceIndex) {
                      this.dragCx = gx;
                      this.dragCy = gy;
                      this.redraw();
                    }
                  },
                  onTouchUp: (gx: number, gy: number): void => {
                    if (this.dragPiece === it.pieceIndex) {
                      this.finishDrag(gx, gy);
                    }
                  }
                })
              }
              .width(80)
              .margin({ right: 4, bottom: 4 })
            }, (it: TrayItem) => 'tr' + it.pieceIndex)
          }
          .width('100%')
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 8, right: 8, top: 6, bottom: 6 })
      .backgroundColor('#ffffff')
      .borderRadius(12)
      .margin({ top: 8 })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 8, right: 8, bottom: 8 })
  }

  build() {
    Stack() {
      Column() {
        GameTopBar({
          title: this.level === 2 ? (this.dataset === null ? '拼拼中国' : (this.dataset.byRegionCapable ? '拼拼中国' : this.dataset.name)) : '拼拼中国',
          stats: this.stats(),
          buttons: this.topButtons(),
          backText: '‹ 返回',
          onBack: (): void => {
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
        })

        if (this.level === 0) {
          Scroll() {
            Column() {
              PageHeading({
                emoji: '🧩',
                title: '拼拼中国',
                subtitle: '把 34 个省级行政区拼回祖国版图，三档难度还能分省拼地级市'
              })
              CardGrid({
                cards: this.modeCards(),
                onPick: (key: string): void => {
                  this.mode = key;
                  this.level = 1;
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
              if (this.mode === 'national') {
                PageHeading({
                  emoji: '🇨🇳',
                  title: '拼全国 · 选难度',
                  subtitle: '按七大区一关一关来，还是一次拼全 34 个省'
                })
                CardGrid({
                  cards: this.diffCards(),
                  onPick: (key: string): void => {
                    for (let i: number = 0; i < this.nationalDiffs.length; i++) {
                      if (this.nationalDiffs[i].key === key) {
                        this.startNational(i);
                        return;
                      }
                    }
                  }
                })
              } else {
                PageHeading({
                  emoji: '🗺️',
                  title: '分省拼图',
                  subtitle: '选一个省，把它的地级市拼成全省地图'
                })
                CardGrid({
                  cards: this.provinceCards(),
                  onPick: (key: string): void => {
                    this.startProvince(key);
                  }
                })
              }
              if (this.loadError.length > 0) {
                Text(this.loadError)
                  .fontSize(13)
                  .fontColor('#e06a6a')
                  .margin({ top: 8 })
              }
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
      .backgroundColor('#eaf4ff')

      // 拖拽浮层: 跟着手指显示的省名, 不挡触摸
      if (this.dragging) {
        Text(this.dragName)
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor('#ffffff')
          .backgroundColor('#5b9be8cc')
          .borderRadius(999)
          .padding({ left: 10, right: 10, top: 3, bottom: 3 })
          .position({ x: this.dragCx - 30, y: this.dragCy + 26 })
          .hitTestBehavior(HitTestMode.None)
      }

      Confetti({ pulse: this.confettiPulse })

      if (this.winVisible) {
        Column() {
          WinCard({
            info: this.winInfo,
            onAgain: (): void => {
              if (this.dataset !== null) {
                this.startWith(this.diff, this.dataset);
              }
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

/** 托盘里的一块拼图: 独立小画布 + 名字 */
@Component
struct TrayPiece {
  @Prop dataset: Dataset | null = null;
  @Prop pieceIndex: number = 0;
  @Prop name: string = '';
  @Prop pinyin: string = '';
  @Prop showName: boolean = true;
  @Prop sizeVp: number = 72;
  onTouchDown: (gx: number, gy: number) => void = () => {
  };
  onTouchMove: (gx: number, gy: number) => void = () => {
  };
  onTouchUp: (gx: number, gy: number) => void = () => {
  };

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  @State ready: boolean = false;

  private paint(): void {
    if (this.dataset === null) {
      return;
    }
    const p: Piece = this.dataset.items[this.pieceIndex];
    if (p === undefined) {
      return;
    }
    drawTrayPiece(this.ctx, p, this.sizeVp, this.sizeVp);
  }

  build() {
    Column() {
      Canvas(this.ctx)
        .width(this.sizeVp)
        .height(this.sizeVp * 0.8)
        .onReady((): void => {
          this.ready = true;
          this.paint();
        })
        .onTouch((e: TouchEvent): void => {
          if (e.touches.length === 0) {
            return;
          }
          const t: TouchObject = e.touches[0];
          if (e.type === TouchType.Down) {
            this.onTouchDown(t.x, t.y);
          } else if (e.type === TouchType.Move) {
            this.onTouchMove(t.x, t.y);
          } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
            this.onTouchUp(t.x, t.y);
          }
        })
      if (this.showName) {
        Text(this.name)
          .fontSize(11)
          .fontColor('#4a5b6d')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      if (this.pinyin.length > 0) {
        Text(this.pinyin)
          .fontSize(9)
          .fontColor('#93a2b2')
          .maxLines(1)
      }
    }
    .width(this.sizeVp)
  }
}
