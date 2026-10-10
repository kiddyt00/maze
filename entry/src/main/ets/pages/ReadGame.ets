/**
 * 子游戏: 跟读乐园 (儿童跟读训练)。
 *
 * 面向还不识字的小朋友: 大图形 + 语音 + 星星, 文字只作为家长辅助。
 *
 * 核心闭环 (读卡页 4 个阶段):
 *   P_READY  待跟读 —— 自动播放标准音, 大按钮"我来读"
 *   P_REC    录音中 —— 实时波形 + 实时识别文字, 静音 1.2s 自动收尾
 *   P_SCORE  评分中 —— 短暂过渡动画
 *   P_RESULT 结果   —— 星星 + 正向话术 + 逐字纠音提示 + "再读一遍/下一个"
 *
 * 递进式脚手架 (绝不卡关): 第 1 轮原样跟读 -> 第 2 轮逐字慢读 -> 第 3 轮逐字慢读
 * -> 第 4 轮无论结果都可以过关并标记"需复习"。
 */
import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { abilityAccessCtrl, common, Permissions, PermissionRequestResult } from '@kit.AbilityKit';
import { Speaker } from '../common/Speech';
import { Recognizer, AsrOutcome, AsrHandlers } from '../common/Recognizer';
import { ReadHall, ReadModule, ReadItem, buildHalls } from '../games/read/Content';
import { ReadScore, scoreRead, noSpeechScore, scaffoldOf } from '../games/read/Score';

const DOMAIN: number = 0x0001;
const TAG: string = 'KidsRead';

const P_READY: number = 0;
const P_REC: number = 1;
const P_SCORE: number = 2;
const P_RESULT: number = 3;

const MAX_ROUND: number = 3;
const WAVE_BARS: number[] = [0.45, 0.7, 1.0, 0.6, 0.9, 0.5, 0.8, 1.0, 0.55, 0.75, 0.45, 0.85, 0.6, 1.0, 0.5, 0.9, 0.4, 0.7];

@Entry
@Component
struct ReadGame {
  @State halls: ReadHall[] = buildHalls();
  @State level: number = 0; // 0=选馆 1=选主题 2=选词 3=读卡
  @State hallIdx: number = 0;
  @State moduleIdx: number = 0;
  @State itemIdx: number = 0;
  @State tip: string = '';
  // 读卡页状态机
  @State phase: number = P_READY;
  @State round: number = 0;
  @State wave: number = 0;
  @State partial: string = '';
  @State stars: number = 0;      // 本次累计星星
  @State rStars: number = 0;
  @State rTier: number = 0;
  @State rScore: number = 0;
  @State rVerdict: string = '';
  @State rHeard: string = '';
  @State rWeak: string = '';
  @State micDenied: boolean = false;
  @State parent: boolean = false;
  private speaker: Speaker = new Speaker();
  private recognizer: Recognizer = new Recognizer();

  aboutToDisappear(): void {
    this.recognizer.release();
    this.speaker.release();
  }

  // ---------- 取值辅助 (避免在 @Builder 中做空值断言) ----------
  private curHall(): ReadHall | null {
    const h: ReadHall = this.halls[this.hallIdx];
    return h === undefined ? null : h;
  }

  private curModules(): ReadModule[] {
    const h: ReadHall | null = this.curHall();
    return h === null ? [] : h.modules;
  }

  private curModule(): ReadModule | null {
    const m: ReadModule = this.curModules()[this.moduleIdx];
    return m === undefined ? null : m;
  }

  private curItems(): ReadItem[] {
    const m: ReadModule | null = this.curModule();
    return m === null ? [] : m.items;
  }

  private curItem(): ReadItem | null {
    const it: ReadItem = this.curItems()[this.itemIdx];
    return it === undefined ? null : it;
  }

  private curEmoji(): string {
    const it: ReadItem | null = this.curItem();
    return it === null ? '' : it.emoji;
  }

  private curText(): string {
    const it: ReadItem | null = this.curItem();
    return it === null ? '' : it.text;
  }

  private curHint(): string {
    const it: ReadItem | null = this.curItem();
    return it === null ? '' : it.hint;
  }

  private curLang(): string {
    const it: ReadItem | null = this.curItem();
    return it === null ? 'zh-CN' : it.lang;
  }

  private titleText(): string {
    if (this.level === 0) {
      return '跟读乐园';
    }
    if (this.level === 1) {
      const h: ReadHall | null = this.curHall();
      return h === null ? '' : h.name;
    }
    if (this.level === 2) {
      const m: ReadModule | null = this.curModule();
      return m === null ? '' : m.name;
    }
    return '跟我读';
  }

  private starStr(n: number): string {
    let s: string = '';
    for (let i: number = 0; i < n; i++) {
      s += '⭐';
    }
    return s;
  }

  private roundText(): string {
    if (this.round <= 0) {
      return '第 1 次';
    }
    return '第 ' + (this.round + 1) + ' 次';
  }

  // ---------- 跟读闭环 ----------
  private speakCurrent(): void {
    const it: ReadItem | null = this.curItem();
    if (it === null) {
      return;
    }
    this.tip = '正在播放标准音…';
    this.speaker.say(it.text, it.lang).then((): void => {
      this.tip = this.round > 0 ? scaffoldOf(this.round) : '听完啦，轮到你读一遍～';
    }).catch((e: Error): void => {
      this.tip = '语音播放失败: ' + e.message;
      hilog.error(DOMAIN, TAG, 'tts failed: %{public}s', e.message);
    });
  }

  private async ensureMic(): Promise<boolean> {
    try {
      const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      const at: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const perms: Permissions[] = ['ohos.permission.MICROPHONE'];
      const res: PermissionRequestResult = await at.requestPermissionsFromUser(ctx, perms);
      if (res.authResults.length > 0 && res.authResults[0] === 0) {
        this.micDenied = false;
        return true;
      }
    } catch (e) {
      const err: Error = e as Error;
      hilog.error(DOMAIN, TAG, 'request permission failed: %{public}s', err.message);
    }
    this.micDenied = true;
    return false;
  }

  private startRead(): void {
    this.ensureMic().then((ok: boolean): void => {
      if (!ok) {
        this.tip = '需要麦克风权限才能听你读哦，请在设置里打开';
        return;
      }
      this.speaker.stop();
      this.wave = 0;
      this.partial = '';
      this.tip = '我正在听…读完了就停下来';
      this.phase = P_REC;

      const handlers: AsrHandlers = {
        onLevel: (v: number): void => {
          this.wave = v;
        },
        onPartial: (t: string): void => {
          this.partial = t;
        },
        onDone: (o: AsrOutcome): void => {
          this.onRecorded(o);
        }
      };
      this.recognizer.start(handlers).catch((e: Error): void => {
        hilog.error(DOMAIN, TAG, 'asr start failed: %{public}s', e.message);
        this.phase = P_READY;
        this.tip = '录音出了点问题，我们再试一次';
      });
    });
  }

  private onRecorded(o: AsrOutcome): void {
    this.wave = 0;
    this.phase = P_SCORE;
    this.tip = '让我想想…';

    let s: ReadScore;
    if (!o.ok && o.text.length === 0) {
      s = noSpeechScore();
    } else {
      s = scoreRead(this.curText(), o.text, o.speechMs, this.curLang());
    }
    this.rStars = s.stars;
    this.rTier = s.tier;
    this.rScore = s.score;
    this.rVerdict = s.verdict;
    this.rHeard = s.heard.length === 0 ? '(没听清)' : s.heard;
    this.rWeak = s.weak.length === 0 ? '无' : s.weak.join(' ');

    const self: ReadGame = this;
    setTimeout((): void => {
      self.phase = P_RESULT;
      self.tip = '';
      self.speaker.say(s.praiseVoice, 'zh-CN').catch((): void => {
        hilog.warn(DOMAIN, TAG, 'praise tts failed');
      });
    }, 450);
  }

  private again(): void {
    if (this.phase === P_REC) {
      this.recognizer.stop();
      return;
    }
    if (this.round < MAX_ROUND) {
      this.round = this.round + 1;
    }
    this.phase = P_READY;
    this.rStars = 0;
    this.rVerdict = '';
    this.rHeard = '';
    const it: ReadItem | null = this.curItem();
    if (it === null) {
      return;
    }
    const hint: string = scaffoldOf(this.round);
    this.tip = hint;
    if (this.round >= 2) {
      // 逐字慢读示范: 一个字一个字念给孩子听。
      const parts: string[] = [];
      for (let i: number = 0; i < it.text.length; i++) {
        parts.push(it.text.charAt(i));
      }
      this.speaker.saySeq(parts, it.lang, 350).catch((): void => {
        hilog.warn(DOMAIN, TAG, 'saySeq failed');
      });
    } else {
      this.speakCurrent();
    }
  }

  private nextItem(): void {
    if (this.phase === P_RESULT) {
      this.stars = this.stars + this.rStars;
    }
    this.round = 0;
    this.rStars = 0;
    this.rVerdict = '';
    this.rHeard = '';
    this.phase = P_READY;
    this.step(1);
  }

  private goBack(): void {
    if (this.phase === P_REC) {
      this.recognizer.stop();
      this.phase = P_READY;
      return;
    }
    this.speaker.stop();
    this.tip = '';
    if (this.level === 0) {
      router.back();
      return;
    }
    if (this.level === 1) {
      this.level = 0;
    } else if (this.level === 2) {
      this.level = 1;
    } else {
      this.round = 0;
      this.rStars = 0;
      this.rVerdict = '';
      this.phase = P_READY;
      this.level = 2;
    }
  }

  private openHall(i: number): void {
    this.hallIdx = i;
    this.moduleIdx = 0;
    this.itemIdx = 0;
    this.level = 1;
    this.tip = '';
  }

  private openModule(i: number): void {
    this.moduleIdx = i;
    this.itemIdx = 0;
    this.level = 2;
    this.tip = '';
  }

  private openItem(i: number): void {
    this.itemIdx = i;
    this.level = 3;
    this.phase = P_READY;
    this.round = 0;
    this.rStars = 0;
    this.rVerdict = '';
    this.tip = '';
    this.speakCurrent();
  }

  private step(delta: number): void {
    const n: number = this.curItems().length;
    if (n === 0) {
      return;
    }
    this.itemIdx = (this.itemIdx + delta + n) % n;
    this.phase = P_READY;
    this.round = 0;
    this.rStars = 0;
    this.rVerdict = '';
    this.tip = '';
    this.speakCurrent();
  }

  // ---------- 界面 ----------
  @Builder
  topBar() {
    Row() {
      Text('‹ 返回')
        .fontSize(15)
        .fontColor('#9FB0CC')
        .padding(8)
        .onClick(() => {
          this.goBack();
        })
      Text(this.titleText())
        .fontSize(17)
        .fontColor(Color.White)
        .fontWeight(FontWeight.Medium)
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
      Text('⭐ ' + this.stars)
        .fontSize(14)
        .fontColor('#FFD37C')
        .padding(8)
    }
    .width('100%')
    .padding({ left: 6, right: 6, top: 4 })
  }

  @Builder
  hallView() {
    Column() {
      Text('听一听，读一读，收集小星星')
        .fontSize(13)
        .fontColor('#9AA6BC')
        .margin({ top: 16, bottom: 22 })
      ForEach(this.halls, (h: ReadHall, i: number) => {
        Column() {
          Text(h.emoji).fontSize(46)
          Text(h.name)
            .fontSize(22)
            .fontColor(Color.White)
            .fontWeight(FontWeight.Medium)
            .margin({ top: 10 })
          Text(h.modules.length + ' 个主题')
            .fontSize(12)
            .fontColor('#C2CCDE')
            .margin({ top: 6 })
        }
        .width('86%')
        .height(150)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(h.color)
        .borderRadius(20)
        .margin({ bottom: 16 })
        .onClick(() => {
          this.openHall(i);
        })
      }, (h: ReadHall) => h.key)
      Blank()
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  moduleView() {
    Scroll() {
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
        ForEach(this.curModules(), (m: ReadModule, i: number) => {
          Column() {
            Text(m.emoji).fontSize(36)
            Text(m.name)
              .fontSize(16)
              .fontColor(Color.White)
              .margin({ top: 8 })
            Text(m.items.length + ' 词')
              .fontSize(11)
              .fontColor('#C2CCDE')
              .margin({ top: 4 })
          }
          .width('47%')
          .height(118)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(m.color)
          .borderRadius(18)
          .margin({ bottom: 14 })
          .onClick(() => {
            this.openModule(i);
          })
        }, (m: ReadModule) => m.key)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 20 })
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  itemView() {
    Scroll() {
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
        ForEach(this.curItems(), (it: ReadItem, i: number) => {
          Column() {
            Text(it.emoji).fontSize(40)
            Text(it.text)
              .fontSize(20)
              .fontColor(Color.White)
              .fontWeight(FontWeight.Medium)
              .margin({ top: 8 })
            Text(it.hint)
              .fontSize(12)
              .fontColor('#B9C6DC')
              .margin({ top: 4 })
          }
          .width('47%')
          .height(128)
          .justifyContent(FlexAlign.Center)
          .backgroundColor('#1E2836')
          .borderRadius(18)
          .margin({ bottom: 14 })
          .onClick(() => {
            this.openItem(i);
          })
        }, (it: ReadItem) => it.text)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 20 })
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  waveRow() {
    Row() {
      ForEach(WAVE_BARS, (b: number, i: number) => {
        Column()
          .width(7)
          .height(10 + this.wave * b * 76)
          .backgroundColor('#5FE0A0')
          .borderRadius(4)
          .margin({ left: 3, right: 3 })
      }, (b: number, i: number) => 'w' + i)
    }
    .height(96)
    .justifyContent(FlexAlign.Center)
  }

  /** 结果页的星星 */
  @Builder
  resultStars() {
    Text(this.starStr(this.rStars))
      .fontSize(46)
      .margin({ top: 6 })
  }

  @Builder
  cardView() {
    Column() {
      if (this.phase === P_RESULT) {
        Text('🎉')
          .fontSize(64)
          .margin({ top: 4 })
        Text(this.curEmoji())
          .fontSize(76)
        this.resultStars()
        Text(this.rVerdict)
          .fontSize(21)
          .fontColor('#FFD37C')
          .fontWeight(FontWeight.Medium)
          .width('90%')
          .textAlign(TextAlign.Center)
          .margin({ top: 10 })
        Text('我听到的是：' + this.rHeard)
          .fontSize(13)
          .fontColor('#8FA0BC')
          .width('90%')
          .textAlign(TextAlign.Center)
          .margin({ top: 8 })
      } else if (this.phase === P_REC) {
        Text(this.curEmoji())
          .fontSize(96)
          .margin({ top: 4 })
        Text(this.curText())
          .fontSize(46)
          .fontColor(Color.White)
          .fontWeight(FontWeight.Bold)
        this.waveRow()
        Text(this.partial.length === 0 ? '…' : this.partial)
          .fontSize(20)
          .fontColor('#5FE0A0')
          .width('90%')
          .textAlign(TextAlign.Center)
          .height(30)
      } else if (this.phase === P_SCORE) {
        Text('🤔')
          .fontSize(80)
          .margin({ top: 30 })
        Text('让我想想…')
          .fontSize(20)
          .fontColor('#9AA6BC')
          .margin({ top: 16 })
      } else {
        Text(this.curEmoji())
          .fontSize(110)
          .margin({ top: 6 })
        Text(this.curText())
          .fontSize(52)
          .fontColor(Color.White)
          .fontWeight(FontWeight.Bold)
          .margin({ top: 8 })
        Text(this.curHint())
          .fontSize(20)
          .fontColor('#9AA6BC')
          .margin({ top: 8 })
        Text(this.roundText() + (this.round > 0 ? ' · 再来一次' : ''))
          .fontSize(13)
          .fontColor('#8FA0BC')
          .margin({ top: 8 })
      }

      if (this.phase === P_RESULT) {
        Button(this.round >= MAX_ROUND || this.rTier >= 3 ? '➡️  下一个' : '🔁  再读一遍')
          .width(250)
          .height(70)
          .fontSize(21)
          .backgroundColor(this.round >= MAX_ROUND || this.rTier >= 3 ? '#2F6BD8' : '#2F7D53')
          .margin({ top: 22 })
          .onClick(() => {
            if (this.round >= MAX_ROUND || this.rTier >= 3) {
              this.nextItem();
            } else {
              this.again();
            }
          })
        Button('➡️  下一个')
          .width(250)
          .height(52)
          .fontSize(17)
          .backgroundColor('#2A3648')
          .margin({ top: 12 })
          .onClick(() => {
            this.nextItem();
          })
      } else if (this.phase === P_REC) {
        Button('⏹  读完了')
          .width(250)
          .height(70)
          .fontSize(21)
          .backgroundColor('#B4453B')
          .margin({ top: 20 })
          .onClick(() => {
            this.recognizer.stop();
          })
      } else {
        Button('🎤  我来读')
          .width(250)
          .height(74)
          .fontSize(23)
          .backgroundColor('#2F7D53')
          .margin({ top: 22 })
          .onClick(() => {
            this.startRead();
          })
        Button('🔊  再听一遍')
          .width(250)
          .height(56)
          .fontSize(18)
          .backgroundColor('#2F6BD8')
          .margin({ top: 14 })
          .onClick(() => {
            this.speakCurrent();
          })
      }

      Text(this.tip)
        .fontSize(14)
        .fontColor('#FFD37C')
        .width('88%')
        .textAlign(TextAlign.Center)
        .margin({ top: 14 })

      if (this.parent) {
        Column() {
          Text('家长看板')
            .fontSize(13)
            .fontColor('#8FA0BC')
          Text('评分 ' + this.rScore + ' · 完整度 ' + Math.round(this.rScore) + ' · 需复习: ' + this.rWeak)
            .fontSize(12)
            .fontColor('#B9C6DC')
            .margin({ top: 4 })
        }
        .width('90%')
        .padding(10)
        .backgroundColor('#161C27')
        .borderRadius(10)
        .margin({ top: 10 })
      }

      Row() {
        Text('家长')
          .fontSize(12)
          .fontColor('#5D6B84')
          .padding(8)
          .onClick(() => {
            this.parent = !this.parent;
          })
        Text(this.micDenied ? '麦克风未授权' : '')
          .fontSize(12)
          .fontColor('#B4453B')
        Blank()
        Button('‹ 上一个')
          .width(110)
          .height(42)
          .fontSize(14)
          .backgroundColor('#2A3648')
          .onClick(() => {
            this.step(-1);
          })
        Button('下一个 ›')
          .width(110)
          .height(42)
          .fontSize(14)
          .backgroundColor('#2A3648')
          .margin({ left: 10 })
          .onClick(() => {
            this.step(1);
          })
      }
      .width('92%')
      .margin({ top: 16 })

      Blank()
    }
    .width('100%')
    .layoutWeight(1)
  }

  build() {
    Column() {
      this.topBar()
      if (this.level === 0) {
        this.hallView()
      } else if (this.level === 1) {
        this.moduleView()
      } else if (this.level === 2) {
        this.itemView()
      } else {
        this.cardView()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#10141C')
  }
}
