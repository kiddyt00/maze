import { Scene } from '@kit.ArkGraphics3D';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { generateMaze } from '../game/MazeGen';
import { SceneBuilder, MazeSceneRefs } from '../game/SceneBuilder';

@Entry
@Component
struct Index {
  @State scene: Scene | undefined = undefined;
  @State statusText: string = '正在生成迷宫…';
  private refs: MazeSceneRefs | null = null;
  private readonly mazeSize: number = 11;

  aboutToAppear(): void {
    this.startGame();
  }

  private startGame(): void {
    this.statusText = '正在生成迷宫…';
    const maze = generateMaze(this.mazeSize, this.mazeSize);
    SceneBuilder.build(maze).then((refs: MazeSceneRefs): void => {
      this.refs = refs;
      this.scene = refs.scene;
      this.statusText = '迷宫 ' + this.mazeSize + '×' + this.mazeSize + ' · 终点在右下角';
      hilog.info(0x0001, 'MazeDebug', 'scene built ok, nodes=%d', refs.scene.root?.children.count ?? -1);
    }).catch((e: Error): void => {
      this.statusText = '构建失败: ' + e.message;
      hilog.error(0x0001, 'MazeDebug', 'build failed: %{public}s', e.message);
    });
  }

  private restart(): void {
    if (this.refs !== null) {
      this.refs.scene.destroy();
      this.refs = null;
    }
    this.scene = undefined;
    this.startGame();
  }

  build() {
    Column() {
      Text(this.statusText)
        .fontSize(15)
        .fontColor(Color.White)
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: 8, bottom: 4 })
      if (this.scene !== undefined) {
        Component3D({ scene: this.scene })
          .width('100%')
          .height('84%')
      } else {
        // 场景构建中: 先占位, 避免以 undefined 创建 Component3D (SceneOptions 不可变, 后绑定 scene 无效)
        Stack() {
          Progress({ value: 0 })
            .width(60)
            .height(60)
            .color(Color.White)
          Text('加载中…')
            .fontSize(14)
            .fontColor(Color.White)
            .margin({ top: 90 })
        }
        .width('100%')
        .height('84%')
        .alignContent(Alignment.Center)
      }
      Button('重新生成迷宫')
        .width(180)
        .height(40)
        .margin({ top: 8, bottom: 8 })
        .onClick(() => {
          this.restart();
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#10141C')
  }
}
