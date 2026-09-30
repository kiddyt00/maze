/**
 * ArkGraphics 3D 场景构建器 (M1: 静态渲染)。
 *
 * 架构 (见 DESIGN.md):
 *  - boardNode 容器持有地板/墙/小球/起终点标记, 后续 M2 通过旋转 boardNode 模拟倾斜;
 *  - 小球是 boardNode 的子节点, 物理运算在棋盘局部坐标系进行;
 *  - 相机/光源挂在场景根节点 (不随棋盘旋转);
 *  - 全场景用 UnlitMaterial (不依赖 IBL), 墙交替两种明度增强立体感。
 */
import { Scene, SceneResourceFactory, Node, Geometry, Camera, Light, LightType,
  Material, MaterialType, UnlitMaterial, CubeGeometry, SphereGeometry,
  Vec3, Quaternion, Color, Environment, EnvironmentBackgroundType } from '@kit.ArkGraphics3D';
import { Maze, CELL_WALL } from './MazeGen';

export interface MazeSceneRefs {
  scene: Scene;
  boardNode: Node;
  ballNode: Geometry;
  maze: Maze;
  cellSize: number;
  ballRadius: number;
}

export class SceneBuilder {
  static async build(maze: Maze): Promise<MazeSceneRefs> {
    const scene: Scene = await Scene.load();
    const rf: SceneResourceFactory = scene.getResourceFactory();
    const root: Node | null = scene.root;
    if (root === null) {
      throw new Error('scene.root is null, cannot attach nodes');
    }

    const cellSize: number = 1.0;
    const wallHeight: number = 0.55;
    const floorThickness: number = 0.06;
    const ballRadius: number = 0.18;
    const boardWidth: number = maze.cols * cellSize;
    const boardDepth: number = maze.rows * cellSize;
    const halfCols: number = maze.cols / 2;
    const halfRows: number = maze.rows / 2;

    // 环境: 无背景贴图, 用相机 clearColor 清屏
    let env: Environment | null = scene.environment;
    if (env === null) {
      env = await rf.createEnvironment({ name: 'env' });
      scene.environment = env;
    }
    env.backgroundType = EnvironmentBackgroundType.BACKGROUND_NONE;

    // 棋盘容器
    const boardNode: Node = await rf.createNode({ name: 'boardNode' });
    root.children.append(boardNode);

    // 地板 (薄长方体, 避免 PlaneGeometry 的朝向问题)
    const floorMat: UnlitMaterial = await SceneBuilder.createUnlitMaterial(rf, 'floorMat',
      { r: 0.10, g: 0.13, b: 0.18, a: 1 });
    const floor: Geometry = await SceneBuilder.createCube(rf, 'floor',
      { x: boardWidth, y: floorThickness, z: boardDepth });
    SceneBuilder.applyMaterial(floor, floorMat);
    floor.position = { x: 0, y: -floorThickness / 2, z: 0 };
    boardNode.children.append(floor);

    // 墙
    const wallMatA: UnlitMaterial = await SceneBuilder.createUnlitMaterial(rf, 'wallMatA',
      { r: 0.55, g: 0.62, b: 0.72, a: 1 });
    const wallMatB: UnlitMaterial = await SceneBuilder.createUnlitMaterial(rf, 'wallMatB',
      { r: 0.42, g: 0.48, b: 0.58, a: 1 });
    for (let r = 0; r < maze.rows; r++) {
      for (let c = 0; c < maze.cols; c++) {
        if (maze.grid[r][c] === CELL_WALL) {
          const wall: Geometry = await SceneBuilder.createCube(rf, 'wall_' + r + '_' + c,
            { x: cellSize, y: wallHeight, z: cellSize });
          SceneBuilder.applyMaterial(wall, (r + c) % 2 === 0 ? wallMatA : wallMatB);
          const wpos: Vec3 = SceneBuilder.cellCenter(r, c, halfRows, halfCols, cellSize);
          wall.position = { x: wpos.x, y: wallHeight / 2, z: wpos.z };
          boardNode.children.append(wall);
        }
      }
    }

    // 起点标记 (琥珀色薄片)
    const startMat: UnlitMaterial = await SceneBuilder.createUnlitMaterial(rf, 'startMat',
      { r: 1.0, g: 0.72, b: 0.20, a: 1 });
    const start: Geometry = await SceneBuilder.createCube(rf, 'startMarker',
      { x: cellSize * 0.7, y: 0.04, z: cellSize * 0.7 });
    SceneBuilder.applyMaterial(start, startMat);
    const startPos: Vec3 = SceneBuilder.cellCenter(maze.startRow, maze.startCol, halfRows, halfCols, cellSize);
    startPos.y = 0.02;
    start.position = startPos;
    boardNode.children.append(start);

    // 终点标记 (绿色薄片)
    const goalMat: UnlitMaterial = await SceneBuilder.createUnlitMaterial(rf, 'goalMat',
      { r: 0.20, g: 0.85, b: 0.40, a: 1 });
    const goal: Geometry = await SceneBuilder.createCube(rf, 'goalMarker',
      { x: cellSize * 0.7, y: 0.04, z: cellSize * 0.7 });
    SceneBuilder.applyMaterial(goal, goalMat);
    const goalPos: Vec3 = SceneBuilder.cellCenter(maze.goalRow, maze.goalCol, halfRows, halfCols, cellSize);
    goalPos.y = 0.02;
    goal.position = goalPos;
    boardNode.children.append(goal);

    // 小球 (橙色, M1 静态)
    const ballMat: UnlitMaterial = await SceneBuilder.createUnlitMaterial(rf, 'ballMat',
      { r: 1.0, g: 0.42, b: 0.16, a: 1 });
    const ballGeo: SphereGeometry = new SphereGeometry();
    ballGeo.radius = ballRadius;
    ballGeo.segmentCount = 32; // 必须显式设置, 默认为 0 会导致原生侧 rings/sectors=0 建网格失败
    const ballMesh = await rf.createMesh({ name: 'ballMesh' }, ballGeo);
    const ballNode: Geometry = await rf.createGeometry({ name: 'ballNode' }, ballMesh);
    SceneBuilder.applyMaterial(ballNode, ballMat);
    ballNode.position = { x: startPos.x, y: ballRadius, z: startPos.z };
    boardNode.children.append(ballNode);

    // 平行光 (M1 场景全 Unlit 暂无效果, 为 M2 PBR 材质预留)
    const light: Light = await rf.createLight({ name: 'keyLight' }, LightType.DIRECTIONAL);
    light.color = { r: 1, g: 1, b: 1, a: 1 };
    light.intensity = 3;
    light.position = { x: 0, y: 15, z: 5 };
    light.rotation = SceneBuilder.quatFromUnitTo({ x: 0, y: 0, z: -1 }, { x: 0, y: -1, z: 0 });
    root.children.append(light);

    // 相机: 俯瞰视角, 按棋盘大小自动取景
    const camera: Camera = await rf.createCamera({ name: 'mainCamera' });
    camera.fov = Math.PI / 3;
    camera.nearPlane = 0.1;
    camera.farPlane = 200;
    camera.clearColor = { r: 0.05, g: 0.06, b: 0.09, a: 1 };
    const eye: Vec3 = SceneBuilder.cameraEye(boardWidth);
    camera.position = eye;
    camera.rotation = SceneBuilder.lookAtQuat(eye, { x: 0, y: 0, z: 0 }, { x: 0, y: 1, z: 0 });
    root.children.append(camera);

    return {
      scene: scene,
      boardNode: boardNode,
      ballNode: ballNode,
      maze: maze,
      cellSize: cellSize,
      ballRadius: ballRadius
    };
  }

  /** 网格 cell 中心的世界坐标 (棋盘局部, y=0) */
  private static cellCenter(row: number, col: number, halfRows: number, halfCols: number, cellSize: number): Vec3 {
    return {
      x: (col + 0.5 - halfCols) * cellSize,
      y: 0,
      z: (row + 0.5 - halfRows) * cellSize
    };
  }

  /** 竖屏取景: 相机在棋盘中心上方, 略向 +Z 偏移制造俯瞰 3D 视角 */
  private static cameraEye(boardWidth: number): Vec3 {
    const vfov: number = Math.PI / 3;
    const aspect: number = 0.46; // 竖屏手机近似宽高比
    const tanHalfH: number = Math.tan(vfov / 2) * aspect;
    const dist: number = (boardWidth * 1.25) / (2 * tanHalfH);
    const tilt: number = 18 * Math.PI / 180;
    return {
      x: 0,
      y: dist * Math.cos(tilt),
      z: dist * Math.sin(tilt)
    };
  }

  private static async createUnlitMaterial(rf: SceneResourceFactory, name: string, color: Color): Promise<UnlitMaterial> {
    const mat: Material = await rf.createMaterial({ name: name }, MaterialType.UNLIT);
    const unlit: UnlitMaterial = mat as UnlitMaterial;
    unlit.baseColor = { image: null, factor: { x: color.r, y: color.g, z: color.b, w: color.a } };
    return unlit;
  }

  private static async createCube(rf: SceneResourceFactory, name: string, size: Vec3): Promise<Geometry> {
    const cube: CubeGeometry = new CubeGeometry();
    cube.size = size;
    const mesh = await rf.createMesh({ name: name + '_mesh' }, cube);
    return await rf.createGeometry({ name: name }, mesh);
  }

  private static applyMaterial(geo: Geometry, mat: Material): void {
    if (geo.mesh.subMeshes.length > 0) {
      geo.mesh.subMeshes[0].material = mat;
    }
  }

  /**
   * from 与 to 均为单位向量, 返回旋转 from 到 to 的四元数。
   * 引擎相机默认前向假设为 -Z; 若真机上画面镜像, 把调用处 from 改为 (0,0,1)。
   */
  private static quatFromUnitTo(from: Vec3, to: Vec3): Quaternion {
    const dot: number = from.x * to.x + from.y * to.y + from.z * to.z;
    if (dot > 0.999999) {
      return { x: 0, y: 0, z: 0, w: 1 };
    }
    if (dot < -0.999999) {
      return { x: 1, y: 0, z: 0, w: 0 };
    }
    const ax: number = from.y * to.z - from.z * to.y;
    const ay: number = from.z * to.x - from.x * to.z;
    const az: number = from.x * to.y - from.y * to.x;
    const s: number = Math.sqrt(2 * (1 + dot));
    return { x: ax / s, y: ay / s, z: az / s, w: s / 2 };
  }

  /** 标准 lookAt: 相机局部 -Z 指向 target, +Y 对齐 up (假定引擎相机前向为 -Z)。 */
  private static lookAtQuat(eye: Vec3, target: Vec3, up: Vec3): Quaternion {
    let fx: number = target.x - eye.x;
    let fy: number = target.y - eye.y;
    let fz: number = target.z - eye.z;
    const fl: number = Math.sqrt(fx * fx + fy * fy + fz * fz);
    if (fl < 1e-9) {
      return { x: 0, y: 0, z: 0, w: 1 };
    }
    fx = fx / fl;
    fy = fy / fl;
    fz = fz / fl;

    let rx: number = fy * up.z - fz * up.y;
    let ry: number = fz * up.x - fx * up.z;
    let rz: number = fx * up.y - fy * up.x;
    let rl: number = Math.sqrt(rx * rx + ry * ry + rz * rz);
    if (rl < 1e-9) {
      rx = 1;
      ry = 0;
      rz = 0;
      rl = 1;
    }
    rx = rx / rl;
    ry = ry / rl;
    rz = rz / rl;

    const ux: number = ry * fz - rz * fy;
    const uy: number = rz * fx - rx * fz;
    const uz: number = rx * fy - ry * fx;

    // 旋转矩阵列: [right, up, -forward]
    const m00: number = rx;
    const m01: number = ry;
    const m02: number = rz;
    const m10: number = ux;
    const m11: number = uy;
    const m12: number = uz;
    const m20: number = -fx;
    const m21: number = -fy;
    const m22: number = -fz;

    const trace: number = m00 + m11 + m22;
    let qx: number = 0;
    let qy: number = 0;
    let qz: number = 0;
    let qw: number = 1;
    if (trace > 0) {
      const s: number = Math.sqrt(trace + 1) * 2;
      qw = 0.25 * s;
      qx = (m21 - m12) / s;
      qy = (m02 - m20) / s;
      qz = (m10 - m01) / s;
    } else if (m00 > m11 && m00 > m22) {
      const s: number = Math.sqrt(1 + m00 - m11 - m22) * 2;
      qw = (m21 - m12) / s;
      qx = 0.25 * s;
      qy = (m01 + m10) / s;
      qz = (m02 + m20) / s;
    } else if (m11 > m22) {
      const s: number = Math.sqrt(1 + m11 - m00 - m22) * 2;
      qw = (m02 - m20) / s;
      qx = (m01 + m10) / s;
      qy = 0.25 * s;
      qz = (m12 + m21) / s;
    } else {
      const s: number = Math.sqrt(1 + m22 - m00 - m11) * 2;
      qw = (m10 - m01) / s;
      qx = (m02 + m20) / s;
      qy = (m12 + m21) / s;
      qz = 0.25 * s;
    }
    return { x: qx, y: qy, z: qz, w: qw };
  }
}
