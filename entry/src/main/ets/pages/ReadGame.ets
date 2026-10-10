/**
 * 子游戏: 跟读乐园 (儿童跟读训练)。
 *
 * 面向还不识字的小朋友: 全图形 + 语音, 文字只作为家长辅助。
 * 当前进度: 内容浏览 (选馆 -> 选主题 -> 选词) + 标准音播放 (TTS)。
 * 下一步: 录音(AudioCapturer) -> 识别(speechRecognizer) -> 评分 -> 递进式引导复练 -> 端侧 LLM 伙伴。
 */
import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Speaker } from '../common/Speech';
import { ReadHall, ReadModule, ReadItem, buildHalls } from '../games/read/Content';

const DOMAIN: number = 0x0001;
const TAG: string = 'KidsRead';

@Entry
@Component
struct ReadGame {
  @State halls: ReadHall[] = buildHalls();
  @State level: number = 0; // 0=选馆 1=选主题 2=选词 3=读卡
  @State hallIdx: number = 0;
  @State moduleIdx: number = 0;
  @State itemIdx: number = 0;
  @State tip: string = '';
  private speaker: Speaker = new Speaker();

  aboutToDisappear(): void {
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

  private curEmoji(): string {
    const it: ReadItem = this.curItems()[this.itemIdx];
    return it === undefined ? '' : it.emoji;
  }

  private curText(): string {
    const it: ReadItem = this.curItems()[this.itemIdx];
    return it === undefined ? '' : it.text;
  }

  private curHint(): string {
    const it: ReadItem = this.curItems()[this.itemIdx];
    return it === undefined ? '' : it.hint;
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

  // ---------- 交互 ----------
  private speakCurrent(): void {
    const it: ReadItem = this.curItems()[this.itemIdx];
    if (it === undefined) {
      return;
    }
    this.tip = '正在播放标准音…';
    this.speaker.say(it.text, it.lang).then((): void => {
      this.tip = '听完啦，轮到你读一遍～';
    }).catch((e: Error): void => {
      this.tip = '语音播放失败: ' + e.message;
      hilog.error(DOMAIN, TAG, 'tts failed: %{public}s', e.message);
    });
  }

  private goBack(): void {
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
    this.tip = '';
    this.speakCurrent();
  }

  private step(delta: number): void {
    const n: number = this.curItems().length;
    if (n === 0) {
      return;
    }
    this.itemIdx = (this.itemIdx + delta + n) % n;
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
      Text('    ')
        .fontSize(15)
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
  cardView() {
    Column() {
      Text(this.curEmoji())
        .fontSize(110)
        .margin({ top: 10 })
      Text(this.curText())
        .fontSize(52)
        .fontColor(Color.White)
        .fontWeight(FontWeight.Bold)
        .margin({ top: 12 })
      Text(this.curHint())
        .fontSize(20)
        .fontColor('#9AA6BC')
        .margin({ top: 10 })

      Button('🔊  听标准音')
        .width(240)
        .height(66)
        .fontSize(20)
        .backgroundColor('#2F6BD8')
        .margin({ top: 30 })
        .onClick(() => {
          this.speakCurrent();
        })

      Button('🎤  我来读')
        .width(240)
        .height(66)
        .fontSize(20)
        .backgroundColor('#2F7D53')
        .margin({ top: 16 })
        .onClick(() => {
          this.tip = '录音跟读正在开发中，先多听几遍吧～';
        })

      Text(this.tip)
        .fontSize(14)
        .fontColor('#FFD37C')
        .width('88%')
        .textAlign(TextAlign.Center)
        .margin({ top: 20 })

      Row() {
        Button('‹ 上一个')
          .width(140)
          .height(46)
          .fontSize(15)
          .backgroundColor('#2A3648')
          .onClick(() => {
            this.step(-1);
          })
        Button('下一个 ›')
          .width(140)
          .height(46)
          .fontSize(15)
          .backgroundColor('#2A3648')
          .onClick(() => {
            this.step(1);
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceEvenly)
      .margin({ top: 24 })

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
