/**
 * 游戏大厅: 游戏盒子的入口页。
 * 每新增一个子游戏, 只需往 GAMES 里加一条, 并在 main_pages.json 注册对应页面。
 *
 * 卡片按 section 分组显示 (动脑 / 动手 / 探索), 组内双列排列。
 */
import { router } from '@kit.ArkUI';

interface GameEntry {
  key: string;
  emoji: string;
  name: string;
  desc: string;
  bg: string;
  route: string;
  ready: boolean;
  /** 卡片角标, 空则不显示 */
  tag: string;
  /** 所属分区, 必须出现在 SECTIONS 里 */
  section: string;
}

/** 分区顺序 */
const SECTIONS: string[] = ['动脑', '动手', '探索'];

const GAMES: GameEntry[] = [
  // ---------- 动脑: 数学 / 记忆 / 专注 ----------
  {
    key: 'math',
    emoji: '🧮',
    name: '口算闯关',
    desc: '加减乘除四档难度，连击拿星星',
    bg: '#1F3E33',
    route: 'pages/MathGame',
    ready: true,
    tag: '数学',
    section: '动脑'
  },
  {
    key: 'memory',
    emoji: '🃏',
    name: '翻翻乐',
    desc: '翻牌找一对，八个主题认物识字',
    bg: '#402F4F',
    route: 'pages/MemoryGame',
    ready: true,
    tag: '记忆',
    section: '动脑'
  },
  {
    key: 'schulte',
    emoji: '🔢',
    name: '舒尔特方格',
    desc: '按顺序点数字，练专注力',
    bg: '#26374A',
    route: 'pages/SchulteGame',
    ready: true,
    tag: '专注力',
    section: '动脑'
  },
  {
    key: 'puzzle',
    emoji: '🧩',
    name: '拼拼中国',
    desc: '拖一拖，把省份拼回祖国版图',
    bg: '#4A3326',
    route: 'pages/PuzzleGame',
    ready: true,
    tag: '地理',
    section: '动脑'
  },
  {
    key: 'mole',
    emoji: '🔨',
    name: '打地鼠口算',
    desc: '拍中举着正确答案的地鼠',
    bg: '#4A3A26',
    route: 'pages/MoleGame',
    ready: true,
    tag: '数学街机',
    section: '动脑'
  },
  // ---------- 动手: 迷宫 / 街机 ----------
  {
    key: 'maze99',
    emoji: '🌀',
    name: '奇妙迷宫',
    desc: '99 关主题迷宫，方向键走到终点',
    bg: '#2A3F2B',
    route: 'pages/KidsMazePage',
    ready: true,
    tag: '迷宫',
    section: '动手'
  },
  {
    key: 'moleprime',
    emoji: '🔨',
    name: '打地鼠',
    desc: '地鼠会溜走，连击得分翻倍',
    bg: '#33421F',
    route: 'pages/MolePrimePage',
    ready: true,
    tag: '街机',
    section: '动手'
  },
  {
    key: 'maze',
    emoji: '🌀',
    name: '重力迷宫',
    desc: '晃动手机，让小球滚到终点',
    bg: '#26405E',
    route: 'pages/MazeGame',
    ready: true,
    tag: '3D',
    section: '动手'
  },
  // ---------- 探索: 语音 / 英语 ----------
  {
    key: 'read',
    emoji: '🎤',
    name: '跟读乐园',
    desc: '听一听、读一读，收集小星星',
    bg: '#4A2E4F',
    route: 'pages/ReadGame',
    ready: true,
    tag: '语音',
    section: '探索'
  }
];

/** 取某个分区的卡片 (顺序即 GAMES 里的顺序) */
function sectionGames(sec: string): GameEntry[] {
  const out: GameEntry[] = [];
  for (let i: number = 0; i < GAMES.length; i++) {
    if (GAMES[i].section === sec) {
      out.push(GAMES[i]);
    }
  }
  return out;
}

/** 一张游戏卡 */
@Component
struct GameCard {
  @Prop game: GameEntry = {
    key: '', emoji: '', name: '', desc: '', bg: '#26405E', route: '', ready: false, tag: '', section: ''
  };

  build() {
    Column() {
      if (this.game.tag.length > 0) {
        Text(this.game.tag)
          .fontSize(10)
          .fontColor('#C2CCDE')
          .backgroundColor('#FFFFFF1A')
          .borderRadius(999)
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
      }
      Text(this.game.emoji)
        .fontSize(38)
        .margin({ top: this.game.tag.length > 0 ? 4 : 0 })
      Text(this.game.name)
        .fontSize(18)
        .fontColor(Color.White)
        .fontWeight(FontWeight.Medium)
        .margin({ top: 6 })
      Text(this.game.desc)
        .fontSize(11)
        .fontColor('#C2CCDE')
        .margin({ top: 4 })
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .padding({ left: 8, right: 8 })
      Text(this.game.ready ? '开始 ▶' : '敬请期待')
        .fontSize(12)
        .fontColor(this.game.ready ? '#7CEDAA' : '#7C8598')
        .margin({ top: 6 })
    }
    .width('47%')
    .padding({ top: 12, bottom: 12 })
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.game.bg)
    .borderRadius(18)
    .margin({ bottom: 12 })
    .onClick(() => {
      if (this.game.ready && this.game.route.length > 0) {
        router.pushUrl({ url: this.game.route });
      }
    })
  }
}

@Entry
@Component
struct Lobby {
  build() {
    Column() {
      Column() {
        Text('TrailStory 游戏盒')
          .fontSize(26)
          .fontColor(Color.White)
          .fontWeight(FontWeight.Bold)
        Text('选一个小游戏开始吧')
          .fontSize(13)
          .fontColor('#9AA6BC')
          .margin({ top: 8 })
      }
      .width('100%')
      .padding({ top: 26, bottom: 14 })

      Scroll() {
        Column() {
          ForEach(SECTIONS, (sec: string) => {
            Column() {
              if (sectionGames(sec).length > 0) {
                Text(sec)
                  .fontSize(13)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#7F8CA3')
                  .width('100%')
                  .padding({ left: 2, top: 2, bottom: 8 })

                Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
                  ForEach(sectionGames(sec), (g: GameEntry) => {
                    GameCard({ game: g })
                  }, (g: GameEntry) => g.key)
                }
                .width('100%')
              }
            }
            .width('100%')
          }, (sec: string) => sec)

          Blank().height(8)
        }
        .width('100%')
        .padding({ left: 18, right: 18 })
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Auto)

      Text('本机为儿童与家庭使用 · 数据不出设备')
        .fontSize(11)
        .fontColor('#5F6880')
        .padding({ top: 8, bottom: 14 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#10141C')
  }
}
