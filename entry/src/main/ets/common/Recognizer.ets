/**
 * 录音 + 语音识别 (ASR) 封装 —— 跟读游戏的"听"那一半。
 *
 * 原理: speechRecognizer 不自己开麦, 需要调用方用 AudioCapturer 采集 PCM 再
 * 通过 writeAudio 喂进去 (只接受 640 / 1280 字节一包, 16k / 16bit / 单声道)。
 * 所以我们自己读麦克风, 顺便用 RMS 做两件事:
 *   1) 驱动界面上的波形动画;
 *   2) 检测"说完之后的静音", 连续静音 1.2s 就自动收尾 (小朋友不用按停止)。
 *
 * 注意: 端侧离线识别引擎目前只支持中文 (zh-CN)。英文的识别结果不可靠,
 * 调用方需要自己决定英文条目怎么评分。
 */
import { speechRecognizer } from '@kit.CoreSpeechKit';
import { audio } from '@kit.AudioKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0001;
const TAG: string = 'KidsRead';

const SAMPLE_RATE: number = 16000;
const READ_BYTES: number = 1280;        // 40ms @ 16kHz/16bit/单声道
const FRAME_MS: number = 40;
const SILENCE_RMS: number = 450;        // 低于这个能量算静音
const SILENCE_HOLD_MS: number = 1200;   // 连续静音多久判定"读完了"
const MIN_SPEECH_MS: number = 300;      // 有效发音至少这么久
const MAX_RECORD_MS: number = 12000;    // 硬上限
const NO_SPEECH_MS: number = 6000;      // 一直不出声就放弃

export interface AsrOutcome {
  text: string;
  ok: boolean;
  reason: string; // '' | 'nospeech' | 'engine' | 'capture'
  /** 有效发音时长 (毫秒), 用于流利度评分 */
  speechMs: number;
}

export interface AsrHandlers {
  onLevel: (level: number) => void;
  onPartial: (text: string) => void;
  onDone: (outcome: AsrOutcome) => void;
}

export class Recognizer {
  private engine: speechRecognizer.SpeechRecognitionEngine | null = null;
  private capturer: audio.AudioCapturer | null = null;
  private sid: string = '';
  private running: boolean = false;
  private lastText: string = '';
  private waitDone: (() => void) | null = null;
  private handlers: AsrHandlers | null = null;

  isRunning(): boolean {
    return this.running;
  }

  private async engineOf(): Promise<speechRecognizer.SpeechRecognitionEngine> {
    if (this.engine !== null) {
      return this.engine;
    }
    const params: speechRecognizer.CreateEngineParams = { language: 'zh-CN', online: 1 };
    const engine: speechRecognizer.SpeechRecognitionEngine = await speechRecognizer.createEngine(params);
    engine.setListener({
      onStart: (sessionId: string, eventMessage: string): void => {
        hilog.info(DOMAIN, TAG, 'asr start %{public}s', eventMessage);
      },
      onEvent: (sessionId: string, eventCode: number, eventMessage: string): void => {
        hilog.info(DOMAIN, TAG, 'asr event %{public}d %{public}s', eventCode, eventMessage);
      },
      onResult: (sessionId: string, result: speechRecognizer.SpeechRecognitionResult): void => {
        if (result.result.length > 0) {
          this.lastText = result.result;
          const h: AsrHandlers | null = this.handlers;
          if (h !== null) {
            h.onPartial(result.result);
          }
        }
        if (result.isLast || result.isFinal) {
          this.releaseWait();
        }
      },
      onComplete: (sessionId: string, eventMessage: string): void => {
        hilog.info(DOMAIN, TAG, 'asr complete %{public}s', eventMessage);
        this.releaseWait();
      },
      onError: (sessionId: string, errorCode: number, errorMessage: string): void => {
        hilog.error(DOMAIN, TAG, 'asr error %{public}d %{public}s', errorCode, errorMessage);
        this.releaseWait();
      }
    });
    this.engine = engine;
    return engine;
  }

  private releaseWait(): void {
    const w: (() => void) | null = this.waitDone;
    if (w !== null) {
      this.waitDone = null;
      w();
    }
  }

  /**
   * 开始一次跟读录音。Promise 在整段交互 (录音 + 识别) 结束后才 resolve,
   * 结果通过 handlers.onDone 回调。
   */
  async start(handlers: AsrHandlers): Promise<void> {
    if (this.running) {
      return;
    }
    this.handlers = handlers;
    this.running = true;
    this.lastText = '';

    let engine: speechRecognizer.SpeechRecognitionEngine;
    try {
      engine = await this.engineOf();
    } catch (e) {
      const err: Error = e as Error;
      hilog.error(DOMAIN, TAG, 'asr createEngine failed: %{public}s', err.message);
      this.running = false;
      handlers.onDone({ text: '', ok: false, reason: 'engine', speechMs: 0 });
      return;
    }

    let capturer: audio.AudioCapturer;
    try {
      capturer = await this.openMic();
    } catch (e) {
      const err: Error = e as Error;
      hilog.error(DOMAIN, TAG, 'capturer failed: %{public}s', err.message);
      this.running = false;
      handlers.onDone({ text: '', ok: false, reason: 'capture', speechMs: 0 });
      return;
    }
    this.capturer = capturer;

    const sid: string = 'kids' + Date.now();
    this.sid = sid;
    const startParams: speechRecognizer.StartParams = {
      sessionId: sid,
      audioInfo: {
        audioType: 'pcm',
        sampleRate: SAMPLE_RATE,
        soundChannel: 1,
        sampleBit: 16
      }
    };
    try {
      engine.startListening(startParams);
      await capturer.start();
    } catch (e) {
      const err: Error = e as Error;
      hilog.error(DOMAIN, TAG, 'startListening/start failed: %{public}s', err.message);
      await this.cleanup(false);
      this.running = false;
      handlers.onDone({ text: '', ok: false, reason: 'engine', speechMs: 0 });
      return;
    }

    let elapsed: number = 0;
    let speechMs: number = 0;
    let silenceMs: number = 0;
    let heard: boolean = false;
    let aborted: boolean = false;

    while (this.running) {
      let chunk: Uint8Array;
      try {
        const buf: ArrayBuffer = await capturer.read(READ_BYTES, true);
        chunk = new Uint8Array(buf);
      } catch (e) {
        const err: Error = e as Error;
        hilog.error(DOMAIN, TAG, 'read failed: %{public}s', err.message);
        aborted = true;
        break;
      }
      if (!this.running) {
        break;
      }

      const rms: number = Recognizer.rmsOf(chunk);
      handlers.onLevel(Recognizer.levelOf(rms));

      if (rms >= SILENCE_RMS) {
        heard = true;
        speechMs += FRAME_MS;
        silenceMs = 0;
      } else if (heard) {
        silenceMs += FRAME_MS;
      }
      elapsed += FRAME_MS;

      try {
        engine.writeAudio(sid, chunk);
      } catch (e) {
        const err: Error = e as Error;
        hilog.error(DOMAIN, TAG, 'writeAudio failed: %{public}s', err.message);
        aborted = true;
        break;
      }

      if (elapsed >= MAX_RECORD_MS) {
        break;
      }
      if (heard && silenceMs >= SILENCE_HOLD_MS) {
        break;
      }
      if (!heard && elapsed >= NO_SPEECH_MS) {
        break;
      }
    }

    this.running = false;
    const noSpeech: boolean = !heard || speechMs < MIN_SPEECH_MS;

    if (!aborted && !noSpeech) {
      // 告诉引擎"说完了", 等最后一次识别结果回来 (最多等 1.2s)。
      const p: Promise<void> = new Promise<void>((resolve: () => void): void => {
        this.waitDone = resolve;
      });
      try {
        engine.finish(sid);
      } catch (e) {
        const err: Error = e as Error;
        hilog.error(DOMAIN, TAG, 'finish failed: %{public}s', err.message);
        this.releaseWait();
      }
      await Promise.race([p, Recognizer.delay(1200)]);
    } else {
      try {
        engine.cancel(sid);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'cancel failed');
      }
    }

    await this.cleanup(true);
    const text: string = this.lastText;
    hilog.info(DOMAIN, TAG, 'asr done heard=%{public}d speech=%{public}d text=%{public}s',
      heard ? 1 : 0, speechMs, text);
    handlers.onDone({
      text: text,
      ok: !aborted && !noSpeech && text.length > 0,
      reason: aborted ? 'capture' : (noSpeech ? 'nospeech' : ''),
      speechMs: speechMs
    });
  }

  /** 小朋友中途放弃 / 退出页面时调用。 */
  stop(): void {
    this.running = false;
  }

  release(): void {
    this.running = false;
    this.releaseWait();
    const c: audio.AudioCapturer | null = this.capturer;
    this.capturer = null;
    if (c !== null) {
      c.stop().then((): void => {
        c.release();
      }).catch((): void => {
        hilog.warn(DOMAIN, TAG, 'capturer release failed');
      });
    }
    if (this.engine !== null) {
      this.engine.shutdown();
      this.engine = null;
    }
  }

  private async cleanup(releaseEngine: boolean): Promise<void> {
    const c: audio.AudioCapturer | null = this.capturer;
    this.capturer = null;
    if (c !== null) {
      try {
        await c.stop();
        await c.release();
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'capturer cleanup failed');
      }
    }
    if (releaseEngine && this.engine !== null) {
      // 引擎保留复用, 只停监听会话。
      hilog.info(DOMAIN, TAG, 'asr session closed');
    }
  }

  private async openMic(): Promise<audio.AudioCapturer> {
    const options: audio.AudioCapturerOptions = {
      streamInfo: {
        samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_16000,
        channels: audio.AudioChannel.CHANNEL_1,
        sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
        encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
      },
      capturerInfo: {
        source: audio.SourceType.SOURCE_TYPE_VOICE_RECOGNITION,
        capturerFlags: 0
      }
    };
    return await audio.createAudioCapturer(options);
  }

  /** 16bit 小端 PCM 的均方根能量。 */
  private static rmsOf(pcm: Uint8Array): number {
    const count: number = pcm.length >> 1;
    if (count === 0) {
      return 0;
    }
    let sum: number = 0;
    for (let i: number = 0; i < count; i++) {
      const lo: number = pcm[i * 2];
      const hi: number = pcm[i * 2 + 1];
      let v: number = (hi << 8) | lo;
      if (v >= 32768) {
        v = v - 65536;
      }
      sum += v * v;
    }
    return Math.sqrt(sum / count);
  }

  /** 把能量映射成 0..1 的动画强度。 */
  private static levelOf(rms: number): number {
    const v: number = rms / 4000;
    return v > 1 ? 1 : v;
  }

  private static delay(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void): void => {
      setTimeout((): void => {
        resolve();
      }, ms);
    });
  }
}
