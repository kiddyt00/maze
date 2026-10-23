/**
 * 彩屑庆祝 + 局部火花 —— 对应 kids-games 的 core/celebrate.js。
 *
 * 原实现用 DOM + CSS animation; 这里用 Canvas 每帧重算粒子:
 *  - celebrate(): 全屏彩屑, 2.6s 后自动消失;
 *  - sparkle():   从某个元素中心喷一小撮 (连击时用), 0.9s。
 *
 * 只做视觉, 不读任何业务状态, 所以可以随意叠在页面最上层, 用 .hitTestBehavior(None) 不挡触摸。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0001;
const TAG: string = 'GameBox';

const CONFETTI_COLORS: string[] = ['#f4b942', '#5b9be8', '#ec7d7d', '#4cc1a1', '#b07be0', '#f08a4b'];
const CONFETTI_MS: number = 2600;
const SPARKLE_MS: number = 900;

class Particle {
  x: number = 0;
  y: number = 0;
  vx: number = 0;
  vy: number = 0;
  size: number = 6;
  color: string = '#f4b942';
  /** 已存活比例 0..1 */
  t: number = 0;
  life: number = 1;
  /** 是否做重力下落 (彩屑) 还是向外飞散 (火花) */
  fall: boolean = true;
  rotation: number = 0;
}

@Component
export struct Confetti {
  /** 0 = 无, 每次 +1 触发一波彩屑 */
  @Prop @Watch('onPulseChange') pulse: number = 0;
  /** 火花触发计数, 每次 +1 从 centerX/centerY 喷一撮 */
  @Prop @Watch('onSparkleChange') sparklePulse: number = 0;
  @Prop centerX: number = 0;
  @Prop centerY: number = 0;
  /** 火花粒子数 (原实现 8~20) */
  @Prop sparkleCount: number = 12;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private particles: Particle[] = [];
  private timer: number = -1;
  private w: number = 0;
  private h: number = 0;
  private lastPulse: number = 0;
  private lastSparkle: number = 0;
  private running: boolean = false;

  aboutToDisappear(): void {
    this.stopTimer();
  }

  private stopTimer(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
    this.running = false;
  }

  /** 全屏彩屑: 与原 celebrate() 一致, 60 片, 横向铺满, 错峰落下 */
  private burstConfetti(): void {
    const n: number = 60;
    for (let i: number = 0; i < n; i++) {
      const p: Particle = new Particle();
      p.x = (i / n) * this.w;
      p.y = -10 - (i % 10) * 8;
      p.vx = 0;
      p.vy = 120 + (i % 7) * 30;
      p.size = 6 + (i % 4) * 2;
      p.color = CONFETTI_COLORS[i % CONFETTI_COLORS.length];
      p.life = CONFETTI_MS;
      p.fall = true;
      p.rotation = (i % 8) * 45;
      this.particles.push(p);
    }
    this.ensureRunning();
  }

  /** 局部火花: 从 (centerX, centerY) 向外均匀飞散, 与原 sparkle() 的三角分布一致 */
  private burstSparkle(): void {
    const n: number = Math.max(4, this.sparkleCount);
    for (let i: number = 0; i < n; i++) {
      const p: Particle = new Particle();
      const ang: number = (i / n) * Math.PI * 2;
      const dist: number = 50 + Math.random() * 60;
      const dur: number = SPARKLE_MS;
      p.x = this.centerX;
      p.y = this.centerY;
      // 目标位移换算成速度 (px/ms)
      p.vx = (Math.cos(ang) * dist) / dur;
      p.vy = (Math.sin(ang) * dist) / dur;
      p.size = 5 + (i % 3) * 2;
      p.color = CONFETTI_COLORS[i % CONFETTI_COLORS.length];
      p.life = dur;
      p.fall = false;
      this.particles.push(p);
    }
    this.ensureRunning();
  }

  private ensureRunning(): void {
    if (this.running) {
      return;
    }
    this.running = true;
    let last: number = Date.now();
    this.timer = setInterval((): void => {
      const now: number = Date.now();
      const dt: number = Math.min(48, now - last);
      last = now;
      this.step(dt);
    }, 16);
  }

  private step(dt: number): void {
    if (this.particles.length === 0) {
      this.ctx.clearRect(0, 0, this.w, this.h);
      this.stopTimer();
      return;
    }
    this.ctx.clearRect(0, 0, this.w, this.h);
    const alive: Particle[] = [];
    for (let i: number = 0; i < this.particles.length; i++) {
      const p: Particle = this.particles[i];
      p.t += dt;
      if (p.t >= p.life) {
        continue;
      }
      if (p.fall) {
        p.vy += 0.9 * (dt / 16); // 重力
        p.rotation += 8 * (dt / 16);
      } else {
        // 火花: 位移速度恒定, 逐渐变淡
        p.vy += 0.25 * (dt / 16);
      }
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      const ratio: number = 1 - p.t / p.life;
      this.ctx.globalAlpha = Math.max(0, Math.min(1, ratio * 1.6));
      this.ctx.fillStyle = p.color;
      if (p.fall) {
        this.ctx.save();
        this.ctx.translate(p.x, p.y);
        this.ctx.rotate((p.rotation * Math.PI) / 180);
        this.ctx.fillRect(-p.size / 2, -p.size / 4, p.size, p.size / 2);
        this.ctx.restore();
      } else {
        this.ctx.beginPath();
        this.ctx.arc(p.x, p.y, p.size / 2, 0, Math.PI * 2);
        this.ctx.fill();
      }
      alive.push(p);
    }
    this.ctx.globalAlpha = 1;
    this.particles = alive;
    if (this.particles.length === 0) {
      this.ctx.clearRect(0, 0, this.w, this.h);
      this.stopTimer();
    }
  }

  build() {
    Canvas(this.ctx)
      .width('100%')
      .height('100%')
      .onReady((): void => {
        this.w = this.ctx.width;
        this.h = this.ctx.height;
      })
      .onAreaChange((oldV: Area, newV: Area): void => {
        this.w = Number(newV.width);
        this.h = Number(newV.height);
      })
      .hitTestBehavior(HitTestMode.None)
      .onAppear((): void => {
        hilog.debug(DOMAIN, TAG, 'confetti attached');
      })
  }

  aboutToAppear(): void {
    this.lastPulse = this.pulse;
    this.lastSparkle = this.sparklePulse;
  }

  onPulseChange(): void {
    if (this.pulse > this.lastPulse) {
      this.lastPulse = this.pulse;
      if (this.w <= 0) {
        return; // 画布还没测量到尺寸, 等 onReady/onAreaChange 后再来
      }
      this.burstConfetti();
    }
  }

  onSparkleChange(): void {
    if (this.sparklePulse > this.lastSparkle) {
      this.lastSparkle = this.sparklePulse;
      if (this.w <= 0) {
        return;
      }
      this.burstSparkle();
    }
  }
}
