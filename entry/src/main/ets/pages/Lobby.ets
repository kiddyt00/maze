/**
 * 游戏大厅: 游戏盒子的入口页。
 * 每新增一个子游戏, 只需往 GAMES 里加一条, 并在 main_pages.json 注册对应页面。
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
}

const GAMES: GameEntry[] = [
  {
    key: 'maze',
    emoji: '🌀',
    name: '重力迷宫',
    desc: '晃动手机，让小球滚到终点',
    bg: '#26405E',
    route: 'pages/MazeGame',
    ready: true
  },
  {
    key: 'read',
    emoji: '🎤',
    name: '跟读乐园',
    desc: '听一听、读一读，收集小星星',
    bg: '#4A2E4F',
    route: 'pages/ReadGame',
    ready: true
  },
  {
    key: 'soon1',
    emoji: '✨',
    name: '敬请期待',
    desc: '更多小游戏正在路上',
    bg: '#1B2230',
    route: '',
    ready: false
  },
  {
    key: 'soon2',
    emoji: '🚧',
    name: '敬请期待',
    desc: '更多小游戏正在路上',
    bg: '#1B2230',
    route: '',
    ready: false
  }
];

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
      .padding({ top: 30, bottom: 20 })

      Scroll() {
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
          ForEach(GAMES, (g: GameEntry) => {
            Column() {
              Text(g.emoji).fontSize(50)
              Text(g.name)
                .fontSize(19)
                .fontColor(Color.White)
                .fontWeight(FontWeight.Medium)
                .margin({ top: 12 })
              Text(g.desc)
                .fontSize(12)
                .fontColor('#C2CCDE')
                .margin({ top: 6 })
                .textAlign(TextAlign.Center)
                .padding({ left: 8, right: 8 })
              Text(g.ready ? '开始 ▶' : '敬请期待')
                .fontSize(13)
                .fontColor(g.ready ? '#7CEDAA' : '#7C8598')
                .margin({ top: 14 })
            }
            .width('47%')
            .height(200)
            .justifyContent(FlexAlign.Center)
            .backgroundColor(g.bg)
            .borderRadius(20)
            .margin({ bottom: 16 })
            .onClick(() => {
              if (g.ready && g.route.length > 0) {
                router.pushUrl({ url: g.route });
              }
            })
          }, (g: GameEntry) => g.key)
        }
        .width('100%')
        .padding({ left: 18, right: 18 })
      }
      .layoutWeight(1)
      .width('100%')

      Text('本机为儿童与家庭使用 · 数据不出设备')
        .fontSize(11)
        .fontColor('#5F6880')
        .padding({ top: 12, bottom: 18 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#10141C')
  }
}
