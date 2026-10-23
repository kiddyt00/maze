/**
 * 游戏盒共用朗读 —— 对应 kids-games 的 core/speaker.js。
 *
 * 原实现用浏览器 speechSynthesis + SpeechSynthesisUtterance(rate 0.85 / pitch 1.05),
 * 这里桥接本机离线 TTS (都是 @kit.CoreSpeechKit 的 textToSpeech, 与跟读乐园同源)。
 *
 * 与原实现的对应关系:
 *  - speak(text, {lang})            -> say(): 直接朗读, 不等待;
 *  - 静音 / 读题两个开关              -> ready() / speak() 里统一判断;
 *  - 语音引擎不可用时静默降级         -> 全程 catch, 失败只记日志, 游戏照常可玩。
 *
 * 额外提供 speakMath(): 把 "3 × 4" 读成 "3 乘 4 等于几"(原 main.js 里的 replace 链)。
 */
import { Speaker } from '../../common/Speech';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ProgressStore } from './Store';

const DOMAIN: number = 0x0001;
const TAG: string = 'GameBox';

const ZH: string = 'zh-CN';
const EN: string = 'en-US';

/** 把算式文本转成口语 ("3 × 4" -> "3 乘 4") */
export function mathToSpeech(text: string): string {
  let s: string = text;
  s = s.replace(/×/g, ' 乘 ');
  s = s.replace(/÷/g, ' 除以 ');
  s = s.replace(/\+/g, ' 加 ');
  s = s.replace(/-/g, ' 减 ');
  s = s.replace(/[()]/g, ' ');
  return s;
}

export class Voice {
  private speaker: Speaker = new Speaker();
  private muted: boolean = false;
  /** 读题开关: 只影响"读题/读词", 不影响答对答错的鼓励语 */
  private readOn: boolean = true;

  /**
   * 从存档恢复音量设置。必须在任何朗读前调用一次。
   * 注意与原实现一致: 引擎不支持时也照样记录下来, 只是不出声。
   */
  load(store: ProgressStore): void {
    const s = store.getSettings();
    this.muted = s.muted;
    this.readOn = s.speakRead;
  }

  isMuted(): boolean {
    return this.muted;
  }

  isReadOn(): boolean {
    return this.readOn;
  }

  /** 返回新的静音状态, 供顶栏按钮显示 🔊 / 🔇 */
  toggleMute(store: ProgressStore): boolean {
    this.muted = !this.muted;
    store.setMuted(this.muted);
    if (this.muted) {
      this.speaker.stop();
    }
    return this.muted;
  }

  /** 返回新的读题状态, 供顶栏按钮显示 📢 / 🔕 */
  toggleRead(store: ProgressStore): boolean {
    this.readOn = !this.readOn;
    store.setSpeakRead(this.readOn);
    return this.readOn;
  }

  /** 悄悄读 (鼓励语 / 音效式语音): 只受静音影响 */
  speak(text: string, lang: string = ZH): void {
    if (this.muted || text.length === 0) {
      return;
    }
    this.speaker.say(text, lang).catch((e: Error): void => {
      hilog.warn(DOMAIN, TAG, 'tts failed: %{public}s', e.message);
    });
  }

  /** 读题: 同时受静音与读题开关影响 */
  speakRead(text: string, lang: string = ZH): void {
    if (!this.readOn) {
      return;
    }
    this.speak(text, lang);
  }

  /** 读算式并补一句"等于几" */
  speakMath(text: string): void {
    this.speakRead(mathToSpeech(text) + ' 等于几');
  }

  stop(): void {
    this.speaker.stop();
  }

  release(): void {
    this.speaker.release();
  }
}

/** 中英通吃的语言选择: 给翻翻乐的英文主题用 */
export function langOf(lang: string | undefined): string {
  if (lang !== undefined && lang.startsWith('en')) {
    return EN;
  }
  return ZH;
}
