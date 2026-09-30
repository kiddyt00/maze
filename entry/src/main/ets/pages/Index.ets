import { Scene } from '@kit.ArkGraphics3D';
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
    }).catch((e: Error): void => {
      this.statusText = '构建失败: ' + e.message;
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
      Component3D({ scene: this.scene })
        .width('100%')
        .height('84%')
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
