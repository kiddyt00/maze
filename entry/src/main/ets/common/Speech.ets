/**
 * 语音合成 (TTS) 封装 —— 跟读游戏的"标准音"来源。
 *
 * 依赖 @kit.CoreSpeechKit 的 textToSpeech (HMS 离线引擎):
 *  - online = 1 表示离线模式 (当前系统仅支持离线);
 *  - 中文音色 13 = 凌小珊(女声, 推荐), 0 为默认; 英文音色 8 = Laura(需下载);
 *  - 语言切换时重建引擎, 因为 language 是 createEngine 的必填参数。
 */
import { textToSpeech } from '@kit.CoreSpeechKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0001;
const TAG: string = 'KidsRead';

const EXTRA_ZH: Record<string, Object> = {
  'style': 'interaction-broadcast',
  'locate': 'CN',
  'name': 'trailstory_kids'
};

@Observed
export class SpeechState {
  speaking: boolean = false;
}

export class Speaker {
  private engine: textToSpeech.TextToSpeechEngine | null = null;
  private lang: string = '';
  private seq: number = 0;
  private busy: boolean = false;
  private pending: (() => void) | null = null;

  private releasePending(): void {
    const p: (() => void) | null = this.pending;
    if (p !== null) {
      this.pending = null;
      p();
    }
  }

  private async ensure(language: string): Promise<textToSpeech.TextToSpeechEngine> {
    if (this.engine !== null && this.lang === language) {
      return this.engine;
    }
    if (this.engine !== null) {
      this.engine.shutdown();
      this.engine = null;
      this.lang = '';
    }
    const params: textToSpeech.CreateEngineParams = {
      language: language,
      person: language.startsWith('en') ? 8 : 13,
      online: 1,
      extraParams: EXTRA_ZH
    };
    const engine: textToSpeech.TextToSpeechEngine = await textToSpeech.createEngine(params);
    engine.setListener({
      onStart: (requestId: string, response: textToSpeech.StartResponse): void => {
        hilog.info(DOMAIN, TAG, 'tts start %{public}s', requestId);
      },
      onComplete: (requestId: string, response: textToSpeech.CompleteResponse): void => {
        hilog.info(DOMAIN, TAG, 'tts complete %{public}s', requestId);
        this.busy = false;
        this.releasePending();
      },
      onStop: (requestId: string, response: textToSpeech.StopResponse): void => {
        hilog.info(DOMAIN, TAG, 'tts stop %{public}s', requestId);
        this.busy = false;
        this.releasePending();
      },
      onError: (requestId: string, errorCode: number, errorMessage: string): void => {
        hilog.error(DOMAIN, TAG, 'tts error %{public}d %{public}s', errorCode, errorMessage);
        this.busy = false;
        this.releasePending();
      }
    });
    this.engine = engine;
    this.lang = language;
    return engine;
  }

  /** 朗读一段文本。Promise 在"开始合成"后即返回, 不等播放结束。 */
  async say(text: string, language: string): Promise<void> {
    if (text.length === 0) {
      return;
    }
    const engine: textToSpeech.TextToSpeechEngine = await this.ensure(language);
    this.seq = this.seq + 1;
    const speakParams: textToSpeech.SpeakParams = {
      requestId: 'kids' + this.seq
    };
    engine.speak(text, speakParams);
    this.busy = true;
  }

  /** 朗读并等它播完 (最多等 timeoutMs, 防止回调丢失把流程卡死)。 */
  async speakAndWait(text: string, language: string, timeoutMs: number): Promise<void> {
    if (text.length === 0) {
      return;
    }
    const wait: Promise<void> = new Promise<void>((resolve: () => void): void => {
      this.pending = resolve;
    });
    await this.say(text, language);
    const guard: Promise<void> = new Promise<void>((resolve: () => void): void => {
      setTimeout((): void => {
        resolve();
      }, timeoutMs);
    });
    await Promise.race([wait, guard]);
    this.releasePending();
  }

  /** 逐段朗读 (用于"一个字一个字慢慢读"的引导), 段间留一点停顿。 */
  async saySeq(parts: string[], language: string, gapMs: number): Promise<void> {
    for (let i: number = 0; i < parts.length; i++) {
      const t: string = parts[i];
      if (t.length === 0) {
        continue;
      }
      await this.speakAndWait(t, language, 2500);
      if (gapMs > 0) {
        await new Promise<void>((resolve: () => void): void => {
          setTimeout((): void => {
            resolve();
          }, gapMs);
        });
      }
    }
  }

  isBusy(): boolean {
    if (this.engine === null) {
      return false;
    }
    return this.engine.isBusy();
  }

  stop(): void {
    if (this.engine !== null) {
      this.engine.stop();
    }
    this.releasePending();
  }

  release(): void {
    if (this.engine !== null) {
      this.engine.shutdown();
      this.engine = null;
      this.lang = '';
    }
  }
}
