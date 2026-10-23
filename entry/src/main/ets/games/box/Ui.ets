/**
 * 游戏盒共用 UI 组件 —— 对应 kids-games 的 css/base.css 里的
 * .screen / h1 / .subtitle / .card-row / .diff-card / .btn / .win-card / .stat。
 *
 * 五个游戏页面都用同一套外壳, 保证观感一致, 也避免每个页面重写一遍顶栏。
 *
 * 配色沿用原 base.css 的浅色系 (孩子们在浅底上看大字更清楚),
 * 但和游戏盒大厅 (#10141C 深色) 之间的过渡由各页面自己决定。
 */

/** 难度卡/主题卡数据: 对应原 .diff-card 的字段 */
export class CardInfo {
  key: string = '';
  emoji: string = '';
  /** 主标题: 原 .diff-label */
  label: string = '';
  /** 副标题: 原 .diff-age (年龄/规格) */
  age: string = '';
  /** 描述: 原 .diff-desc, 可为空 */
  desc: string = '';
  /** 角标: 原 .diff-badge (⭐ 3/9 / 🏅 最快 00:42 / 未开始) */
  badge: string = '';
  /** 主题色, 用来做卡片左侧色条 */
  accent: string = '#5b9be8';
  /** 是否禁用 (关卡未解锁) */
  disabled: boolean = false;

  constructor(key: string, emoji: string, label: string, age: string) {
    this.key = key;
    this.emoji = emoji;
    this.label = label;
    this.age = age;
  }
}

/** 结算数据: 对应原 .win-card 的内容 */
export class WinInfo {
  emoji: string = '🎉';
  title: string = '';
  /** 若干条指标, 原 .win-metrics 的 <span> */
  metrics: string[] = [];
  /** 主按钮文案, 空则用 "再玩一次" */
  againText: string = '再玩一次';
  /** 是否显示 "下一关" */
  showNext: boolean = false;
  /** 是否显示 "错题重练" */
  showRetryWrong: boolean = false;
}

/** 顶栏右侧按钮样式 */
export class BarButton {
  text: string = '';
  onTap: () => void = () => {
  };

  constructor(text: string, onTap: () => void) {
    this.text = text;
    this.onTap = onTap;
  }
}

/** 通用大按钮 (原 .btn / .btn-primary / .btn-ghost) */
@Component
export struct BigButton {
  @Prop text: string = '';
  @Prop primary: boolean = false;
  @Prop danger: boolean = false;
  @Prop fontSize: number = 17;
  @Prop heightVp: number = 52;
  onTap: () => void = () => {
  };

  build() {
    Text(this.text)
      .fontSize(this.fontSize)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.primary || this.danger ? Color.White : '#3f7fcf')
      .width('100%')
      .height(this.heightVp)
      .textAlign(TextAlign.Center)
      .borderRadius(this.heightVp / 2)
      .backgroundColor(this.danger ? '#ec7d7d' : (this.primary ? '#5b9be8' : '#eef5fc'))
      .onClick(() => {
        this.onTap();
      })
  }
}

/** 游戏顶栏: 返回 / 标题 / 右侧若干按钮 (含计时、分数这类只读文字) */
@Component
export struct GameTopBar {
  @Prop title: string = '';
  /** 只读状态文字, 如 "⭐ 0" "⏱️ 00:42" */
  @Prop stats: string[] = [];
  @Prop buttons: BarButton[] = [];
  @Prop backText: string = '‹ 返回';
  onBack: () => void = () => {
  };

  build() {
    Row() {
      Text(this.backText)
        .fontSize(15)
        .fontColor('#9FB0CC')
        .padding({ left: 10, right: 10, top: 8, bottom: 8 })
        .onClick(() => {
          this.onBack();
        })
      Column() {
        Text(this.title)
          .fontSize(16)
          .fontColor(Color.White)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.stats.length > 0) {
          Row() {
            ForEach(this.stats, (s: string, i: number) => {
              Text(s)
                .fontSize(12)
                .fontColor(i === 0 ? '#FFD37C' : '#9FB0CC')
                .backgroundColor('#1B2230')
                .borderRadius(999)
                .padding({ left: 9, right: 9, top: 3, bottom: 3 })
                .margin({ left: i === 0 ? 0 : 6 })
            }, (s: string, i: number) => 'st' + i + s)
          }
          .margin({ top: 4 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .padding({ top: 4, bottom: 4 })

      ForEach(this.buttons, (b: BarButton, i: number) => {
        Text(b.text)
          .fontSize(15)
          .fontColor('#3f7fcf')
          .backgroundColor('#eef5fc')
          .borderRadius(999)
          .padding({ left: 12, right: 12, top: 7, bottom: 7 })
          .margin({ left: 6 })
          .onClick(() => {
            b.onTap();
          })
      }, (b: BarButton, i: number) => 'bb' + i + b.text)
    }
    .width('100%')
    .padding({ left: 4, right: 10, top: 6, bottom: 6 })
    .alignItems(VerticalAlign.Center)
  }
}

/** 页面标题块 (原 h1 + .subtitle) */
@Component
export struct PageHeading {
  @Prop emoji: string = '';
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop tip: string = '';

  build() {
    Column() {
      Row() {
        if (this.emoji.length > 0) {
          Text(this.emoji).fontSize(30).margin({ right: 8 })
        }
        Text(this.title)
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor('#2b3a4a')
      }
      .alignItems(VerticalAlign.Center)

      Text(this.subtitle)
        .fontSize(13)
        .fontColor('#6b7c8d')
        .textAlign(TextAlign.Center)
        .width('100%')
        .margin({ top: 8 })

      if (this.tip.length > 0) {
        Text(this.tip)
          .fontSize(12)
          .fontColor('#93a2b2')
          .textAlign(TextAlign.Center)
          .width('100%')
          .margin({ top: 10 })
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 10, bottom: 14 })
  }
}

/** 难度/主题卡 (原 .diff-card, 双列) */
@Component
export struct CardGrid {
  @Prop cards: CardInfo[] = [];
  /** 窄屏一列, 宽屏两列; 这里固定两列, 与原 .card-row 的响应式一致 */
  onPick: (key: string) => void = () => {
  };

  build() {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
      ForEach(this.cards, (c: CardInfo) => {
        Column() {
          Text(c.emoji).fontSize(38)
          Text(c.label)
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(c.disabled ? '#a9b5c2' : '#2b3a4a')
            .margin({ top: 6 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (c.age.length > 0) {
            Text(c.age)
              .fontSize(12)
              .fontColor('#6b7c8d')
              .margin({ top: 4 })
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          if (c.desc.length > 0) {
            Text(c.desc)
              .fontSize(11)
              .fontColor('#93a2b2')
              .textAlign(TextAlign.Center)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 5 })
              .padding({ left: 6, right: 6 })
          }
          if (c.badge.length > 0) {
            Text(c.badge)
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(c.disabled ? '#a9b5c2' : '#3f7fcf')
              .backgroundColor(c.disabled ? '#eef1f5' : '#e7f0fb')
              .borderRadius(999)
              .padding({ left: 10, right: 10, top: 3, bottom: 3 })
              .margin({ top: 8 })
          }
        }
        .width('48%')
        .padding({ top: 14, bottom: 14, left: 8, right: 8 })
        .backgroundColor('#ffffff')
        .borderRadius(16)
        .border({ width: 1, color: '#e3ecf5' })
        .shadow({ radius: 10, color: '#1a28466e', offsetX: 0, offsetY: 3 })
        .margin({ bottom: 12 })
        .opacity(c.disabled ? 0.72 : 1)
        .onClick(() => {
          if (!c.disabled) {
            this.onPick(c.key);
          }
        })
      }, (c: CardInfo) => c.key)
    }
    .width('100%')
  }
}

/** 结算卡 (原 .win-card) */
@Component
export struct WinCard {
  @Prop info: WinInfo = new WinInfo();
  onAgain: () => void = () => {
  };
  onNext: () => void = () => {
  };
  onRetryWrong: () => void = () => {
  };
  onBack: () => void = () => {
  };

  build() {
    Column() {
      Text(this.info.emoji).fontSize(58)
      Text(this.info.title)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor('#2b3a4a')
        .margin({ top: 10 })
        .textAlign(TextAlign.Center)

      Column() {
        ForEach(this.info.metrics, (m: string, i: number) => {
          Text(m)
            .fontSize(15)
            .fontColor('#4a5b6d')
            .margin({ top: i === 0 ? 0 : 8 })
            .textAlign(TextAlign.Center)
        }, (m: string, i: number) => 'wm' + i + m)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .margin({ top: 16 })

      Column() {
        BigButton({
          text: this.info.againText,
          primary: true,
          fontSize: 18,
          heightVp: 56,
          onTap: () => {
            this.onAgain();
          }
        })
        if (this.info.showNext) {
          BigButton({
            text: '下一关 ▶',
            primary: true,
            fontSize: 17,
            heightVp: 52,
            onTap: () => {
              this.onNext();
            }
          })
            .margin({ top: 10 })
        }
        if (this.info.showRetryWrong) {
          BigButton({
            text: '📝 错题重练',
            fontSize: 16,
            heightVp: 48,
            onTap: () => {
              this.onRetryWrong();
            }
          })
            .margin({ top: 10 })
        }
        BigButton({
          text: '↩ 返回',
          fontSize: 16,
          heightVp: 48,
          onTap: () => {
            this.onBack();
          }
        })
          .margin({ top: 10 })
      }
      .width('100%')
      .padding({ left: 24, right: 24 })
      .margin({ top: 22 })
    }
    .width('88%')
    .padding({ top: 28, bottom: 24 })
    .backgroundColor('#ffffff')
    .borderRadius(22)
    .shadow({ radius: 22, color: '#1a284633', offsetX: 0, offsetY: 6 })
  }
}
