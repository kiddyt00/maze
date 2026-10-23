/**
 * 语音播放 —— 对应 lilearn-english 的 voice.js + `new Audio(dataURI).play()`。
 *
 * 原实现把 305 段豆包语音以 base64 data URI 内嵌在 voice.js (8.3MB) 里,
 * 运行时 `new Audio(bank[key])` 播放。这里改成:
 *   voice.js 的 base64 解码成 resources/rawfile/voice/<key>.mp3
 *   → 用 resourceManager.getRawFdSync 拿到 fd
 *   → media.AVPlayer 的 fdSrc 播放。
 *
 * 为什么不照搬 dataURI: ArkTS 没有 Web Audio / HTMLAudioElement,
 * 也不能把 8MB base64 字符串当播放源。解码成真文件还能让 HAP 压缩更有效。
 *
 * 播放语义与原实现保持一致:
 *  - 同一时刻只播一段 (play 前先停上一段), 避免叠音;
 *  - 片段缺失时静默降级, 游戏照常可玩 (原实现也是 catch 后 console.warn);
 *  - play 返回 Promise, 在"开始播放"后即 resolve, 不阻塞流程。
 */
import { media } from '@kit.MediaKit';
import { common } from '@kit.AbilityKit';
import { resourceManager } from '@kit.LocalizationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0001;
const TAG: string = 'KidsEnglish';

/** 一段语音的句柄, 供页面判断是否还在播 */
export class VoiceClip {
  player: media.AVPlayer | null = null;
  /** getRawFd 的 offset, release 时要用 */
  fd: number = -1;
  key: string = '';
}

/**
 * 语音库: 懒加载 + 单通道播放。
 * 5.9MB 的 mp3 没有必要预载, 用到哪个 key 才开哪个 AVPlayer。
 */
export class VoiceBank {
  private rm: resourceManager.ResourceManager | null = null;
  private current: media.AVPlayer | null = null;
  private currentKey: string = '';
  private muted: boolean = false;
  private missing: Set<string> = new Set<string>();

  init(context: common.UIAbilityContext): void {
    if (this.rm === null) {
      this.rm = context.resourceManager;
    }
  }

  isMuted(): boolean {
    return this.muted;
  }

  setMuted(m: boolean): void {
    this.muted = m;
    if (m) {
      this.stop();
    }
  }

  /** 停掉当前这段 (对应原实现的 el.pause() + 重置) */
  stop(): void {
    const p: media.AVPlayer | null = this.current;
    this.current = null;
    this.currentKey = '';
    if (p === null) {
      return;
    }
    try {
      p.stop();
    } catch (e) {
      // 未进入可停止状态时忽略
    }
    p.release().catch((e: Error): void => {
      hilog.warn(DOMAIN, TAG, 'release failed: %{public}s', e.message);
    });
  }

  release(): void {
    this.stop();
  }

  /** 正在播的 key, 空表示没在播 (原实现用于判断是否要等语音结束) */
  playingKey(): string {
    return this.currentKey;
  }

  /**
   * 播一段语音。
   * @returns 是否真的开始播了 (key 不存在 / 静音 / 出错都返回 false)
   */
  async play(key: string): Promise<boolean> {
    if (this.muted || key.length === 0) {
      return false;
    }
    if (this.missing.has(key)) {
      return false;
    }
    if (this.rm === null) {
      return false;
    }
    // 同一段正在播就不重开
    if (this.currentKey === key && this.current !== null) {
      return true;
    }
    this.stop();

    let fd: resourceManager.RawFileDescriptor;
    try {
      fd = this.rm.getRawFdSync('voice/' + key + '.mp3');
    } catch (e) {
      // 片段缺失: 记下来以后不再重试, 静默降级
      this.missing.add(key);
      hilog.warn(DOMAIN, TAG, 'voice clip missing: %{public}s', key);
      return false;
    }

    try {
      const player: media.AVPlayer = await media.createAVPlayer();
      await new Promise<void>((resolve: () => void, reject: (e: Error) => void): void => {
        player.on('stateChange', (state: string): void => {
          if (state === 'initialized') {
            player.prepare().catch((e: Error): void => {
              reject(e);
            });
          } else if (state === 'prepared') {
            player.play().then((): void => {
              resolve();
            }).catch((e: Error): void => {
              reject(e);
            });
          } else if (state === 'completed') {
            // 播完自动收尾, 释放播放器
            player.release().catch((): void => {
            });
            if (this.current === player) {
              this.current = null;
              this.currentKey = '';
            }
          }
        });
        player.on('error', (err: Error): void => {
          hilog.warn(DOMAIN, TAG, 'playback error: %{public}s', err.message);
          reject(err);
        });
        // 设置 fdSrc 会触发进入 initialized
        player.fdSrc = { fd: fd.fd, offset: fd.offset, length: fd.length };
      });
      this.current = player;
      this.currentKey = key;
      return true;
    } catch (e) {
      const err: Error = e as Error;
      hilog.warn(DOMAIN, TAG, 'play %{public}s failed: %{public}s', key, err.message);
      this.stop();
      return false;
    }
  }
}
