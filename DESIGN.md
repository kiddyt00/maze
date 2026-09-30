# 重力迷宫（Tilt Maze）技术设计 — HarmonyOS NEXT 原生真3D

> 概念：俯瞰 3D 迷宫，小球靠倾斜手机（重力）滚动到终点。真3D（ArkGraphics 3D）、只做鸿蒙原生。
> 设计基于：本地 CLT SDK API 26 类型声明（`.harmonyos-tools/sdk-types/*.d.ts`）+ 华为官方文档 + 社区实战核验（2026-09-30）。

---

## 1. 已核实的技术事实

| 主题 | 结论 |
|---|---|
| Kit 形态 | `@kit.ArkGraphics3D`，底层模块 `@ohos.graphics.scene`，能力标识 `SystemCapability.ArkUi.Graphics3D`，首批 API 12；本地 SDK **API 26**（version 26.0.0.105，platformVersion 26.0.0） |
| 呈现组件 | ArkUI **`Component3D`**（不是 SceneView/XComponent）。两种模式：自动场景（传资源路径，框架建相机光源+自带旋转缩放手势）/ **自定义场景（传 Scene 对象，全部自管，无内置相机控制器）**。游戏必须走自定义模式 |
| 模型/纹理 | 仅 **glTF**（.gltf/.glb）；纹理仅 png/jpg/ktx。**本游戏全部程序化几何，无需美术资产** |
| 资源创建 | 除几何定义类外**一切资源必须经 `SceneResourceFactory` 创建**，不能 `new`。可 `new` 的只有：`CubeGeometry`/`PlaneGeometry`/`SphereGeometry`/`CylinderGeometry`/`CustomGeometry`（均 @since 18） |
| 工厂流程 | `new CubeGeometry()` → `rf.createMesh({name}, geo): Promise<MeshResource>` → `rf.createGeometry({name}, mesh): Promise<Geometry>` |
| 节点体系 | `Node` 子类仅 5 个：`Geometry`/`Camera`/`Light`/`SpotLight`/`DirectionalLight`。**没有 addChild/removeChild**，用 `Container<T>.append()/insertAfter()/remove()/get()/clear()/count()` |
| 节点变换 | `position: Position3`、`rotation: Quaternion`、`scale: Scale3` 直接挂在 Node 上（无 transform 聚合对象） |
| 相机 | 仅透视投影；`fov` 单位**弧度**；字段名 `nearPlane`/`farPlane`/`enabled`；无 lookAt，相机朝向四元数要自己算 |
| 光照 | 只有 `LightType.DIRECTIONAL` 和 `SPOT`，**无点光/无环境光**；环境光靠 `Environment`（IBL，.ktx/cubemap）。阴影两级开关：`Light.shadowEnabled` + `Material.shadowReceiver`（默认 false，容易漏） |
| 材质 | `MetallicRoughnessMaterial`（API 20+），字段全是 `MaterialProperty{image,factor,sampler}`；金属度/粗糙度打包在 `material.factor`（Vec4）且分量顺序未文档化 → **外观尽量走贴图/纯色，不硬编 factor 分量**；另有 `UnlitMaterial`（23+）适合简单色块 |
| 动画/释放 | 动画类名 `Animation`（非 Animator）；资源释放是 **`destroy()`**（无 dispose），之后引用置 null |
| 按需渲染 | `scene.renderFrame({ alwaysRender })`（API 15+）：交互/游戏期连续渲染，静止期停帧省电 |
| 数学类型 | `Vec2/3/4`、`Quaternion`、`Mat4x4` 来自 `@kit.ArkGraphics3D`；`@ohos.vector3`/`@ohos.quaternion` 不存在；ArkUI 的 `matrix4` 在 `@kit.ArkUI` 且 transformPoint 仅 2D |
| 坐标系 | ArkUI 组件系：x 右、y 下、z 出屏（左手系）；ArkGraphics 3D 世界坐标：场景单位（cm/m/km 不强制），glTF 是 y 上右手系。程序化场景自行约定坐标即可 |
| 预览器 | **DevEco 预览器不支持 Component3D，效果以真机为准** → 3D 开发必须真机（我们已有 hdc 管线） |
| SceneOptions | 控件创建后**不可动态修改** → 场景构建完成后再一次性赋给 @State |
| **物理引擎** | **本地 d.ts 无 RigidBody/Collider/PhysicsWorld** → ArkGraphics 3D 不带物理。小球物理自写（对本游戏反而是优点：手感完全可控） |

参考：官方 [Component3D 文档](https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/ts-basic-components-component3d)、[命令行构建流水线](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V14/ide-command-line-building-app-V14)、社区实战核验文 [可交互 3D 组件全解析](https://ost.51cto.com/posts/57573)。

---

## 2. 总体架构

```
┌─────────────┐   ┌───────────────────┐   ┌─────────────────────┐
│ 传感器输入    │ → │ 物理（棋盘局部系）   │ → │ 渲染（Component3D）   │
│ 加速度计      │   │ 加速度→速度→位置    │   │ 棋盘节点整体旋转(3D)  │
│ 低通滤波→倾角 │   │ 圆 vs 墙AABB碰撞   │   │ + 相机俯视 + 光照阴影 │
└─────────────┘   └───────────────────┘   └─────────────────────┘
        ↑                                            ↑
┌─────────────┐                             ┌─────────────┐
│ 迷宫生成 DFS │ 每帧 16ms GameLoop ──────────→ │ 胜利判定/UI  │
└─────────────┘                             └─────────────┘
```

关键决策：**倾斜旋转的是整个"棋盘"节点（boardNode）**，小球是 boardNode 的子节点——视觉上就是手机倾斜、3D 棋盘跟着倾斜、球往低处滚，这正是用户要的"晃动手机 + 3D"效果。物理在棋盘局部坐标系里算（墙固定不动，重力方向恒定），渲染自动带上棋盘旋转。

---

## 3. 项目结构

```
harmonyos-maze/
├── AppScope/                     # 应用级配置（图标/应用名）
├── entry/
│   ├── build-profile.json5       # 编译配置 + signingConfigs（签名）
│   ├── oh-package.json5
│   └── src/main/
│       ├── module.json5          # 模块声明（abilities/权限）
│       ├── resources/            # 资源（字符串/图标）
│       └── ets/
│           ├── entryability/EntryAbility.ets
│           ├── pages/Index.ets   # 页面壳：Component3D + UI 覆盖层
│           └── game/
│               ├── MazeGen.ets      # 递归回溯迷宫生成 → 墙/路网格
│               ├── TiltInput.ets    # 传感器订阅 + 低通滤波 → 倾角四元数
│               ├── BallPhysics.ets  # 自写物理：积分 + AABB 碰撞
│               ├── SceneBuilder.ets # 程序化 3D 场景（地板/墙/球/终点/相机/光照）
│               └── GameLoop.ets     # 16ms 游戏循环 + 胜利判定
```

---

## 4. 模块设计

### 4.1 TiltInput — 传感器（@kit.SensorServiceKit）

- `import { sensor } from '@kit.SensorServiceKit';`，`sensor.on(sensor.SensorId.ACCELEROMETER, cb, { interval: sensor.SensorInterval.GAME })`。
- 加速度计返回含重力的三轴加速度（静止时模≈9.8 m/s²），**属普通传感器，无需敏感权限**。
- 倾角：`pitch = atan2(ax, az)`、`roll = atan2(ay, az)`（符号/轴方向真机微调）。
- 低通滤波：`smoothed = smoothed + (raw - smoothed) * alpha`，alpha≈0.2，消除手抖。
- 棋盘旋转四元数：由 (pitch, roll) 按固定轴序转欧拉→四元数（自实现，参考标准公式）；旋转轴方向真机调。
- 页面退出 `sensor.off(...)`。

### 4.2 MazeGen — 迷宫生成

- 奇数尺寸网格（如 21×21），**递归回溯（DFS）** 随机打通 → 保证任意两格连通、有唯一解路径。
- 输出：墙格集合、起点（左上）、终点（右下）。

### 4.3 SceneBuilder — 程序化 3D 场景

- 空场景：`Scene.load()`（无参）或工厂 `createScene()`（实现时确认空场景创建方式）。
- 坐标约定：棋盘平面在 **XZ**，Y 向上；格宽 `CELL=0.2` 场景单位；墙高 `0.18`；球半径 `0.06`。
- 工厂流程（已核实签名）：
  ```typescript
  import { Scene, SceneResourceFactory, CubeGeometry, PlaneGeometry, SphereGeometry,
           MaterialType, MetallicRoughnessMaterial, LightType, Light,
           Quaternion, Container } from '@kit.ArkGraphics3D';
  // 墙：new CubeGeometry() → createMesh → createGeometry
  const geo = new CubeGeometry();            // @since 18，唯一可 new 的
  geo.size = { x: CELL, y: WALL_H, z: CELL };
  const mesh = await rf.createMesh({ name: 'wallMesh' }, geo);   // → MeshResource
  const wallNode = await rf.createGeometry({ name: 'wall' }, mesh); // → Geometry
  board.children.append(wallNode);           // Container.append，无 addChild
  ```
- 地板 `PlaneGeometry`（size Vec2）；小球 `SphereGeometry`（r 0.06）；终点格放一块自发光/高对比色块。
- 材质：简单纯色走 `UnlitMaterial`（23+）或 `MetallicRoughnessMaterial`（只设 baseColor 颜色/贴图，不碰 factor 分量）；所有墙/球设 `shadowReceiver = true` 才有阴影。
- 光照：主 `DIRECTIONAL`（`shadowEnabled=true`）+ 补光 `DIRECTIONAL`；IBL `Environment` 可选（需 .ktx，后续增强）。
- 相机：`createCamera`，`fov = 50 * Math.PI / 180`（弧度！），`nearPlane/farPlane`；位置棋盘上方斜俯视（俯瞰+3D 感），朝向四元数手算（无 lookAt）。
- 层级：`scene.root.children.append(board)`，`board.children.append(地板/墙/终点/球)`。
- 场景构建完成后一次性 `this.sceneOpt = { scene, modelType: ModelType.SURFACE }` 赋 @State（SceneOptions 创建后不可改）。

### 4.4 BallPhysics — 自写物理（棋盘局部坐标）

每帧 dt（≈16ms）：

```
acc = (tiltX * G, tiltY * G)        # G≈9.8，tilt 来自 TiltInput，棋盘局部系
v += acc * dt
v *= exp(-k * dt)                   # k 阻尼系数（手感调参）
pos += v * dt
碰撞：圆 vs 墙AABB（墙按格离散）
  穿透修正 + 法向速度反射（restitution≈0.3）+ 切向摩擦
边界 clamp；速度 < 阈值 → 置 0（防微颤）
```

- 球位置写回 `ballNode.position`（球是 boardNode 子节点 → 渲染自动带棋盘旋转）。
- 手感参数（G 增益、阻尼 k、摩擦、反弹系数）做成常量，真机集中调。

### 4.5 GameLoop

- `setInterval` 16ms 驱动：每帧读最新倾角 → 更新 boardNode.rotation → 物理步进 → `scene.renderFrame({ alwaysRender: false })`。
- 游戏期连续跑；胜利/暂停时清 interval 停帧省电（同官方 R7 按需渲染思路）。
- 胜利判定：球中心进入终点格 → 停表 → 胜利横幅 + "再来一局"（重新生成迷宫）。

### 4.6 Index — 页面壳与 UI 覆盖层

- `Component3D(this.sceneOpt)` 全屏，上面叠 ArkUI 控件：计时、步数、重新开始、新迷宫按钮、胜利横幅。
- `aboutToDisappear`：`sensor.off` + `scene.destroy()` + 所有 Scene 引用置 null（官方要求）。

---

## 5. 构建 / 签名 / 真机

1. **SDK**：本地 CLT 已含 API 26 全量 SDK（zip 内 7.2GB，当前只解压了 toolchains 和类型声明）。要编译 HAP 需解压完整 SDK（含 `ets/build-tools` 编译器）。
2. **构建**：CLT 含 hvigorw/ohpm；`hvigorw assembleHap` 产出 HAP。需 Node（待确认本机版本）。
3. **签名**：华为 AGC → 我的应用 → 新建应用（包名）→ 配置证书/调试 Profile → `build-profile.json5` 写 `signingConfigs` → 出 signed HAP。
4. **安装/调试**：`hdc install <hap>`；拉起应用 `hdc shell aa start -a EntryAbility -b <bundleName>`（命令实现时确认）。
5. **真机是唯一验证路径**（预览器不支持 Component3D）；**当前阻塞项：手机 USB 调试授权还没点**。
6. **设备 API 版本待确认**：Mate 70 系统版本若 < API 26，`targetSdkVersion` 需下调（HAP 安装校验 targetSdk ≤ 设备 API）。授权后 `hdc shell` 查询。

---

## 6. 双机工作流（公司 Linux + 家里）

- git 仓库（gitee 等）同步代码；公司 Linux 用 hvigorw CLI 构建 + hdc 真机安装；家里机器用 DevEco Studio 打开同一工程（若 Win/Mac）或同样 CLI。
- 签名材料（keystore/密码）**不入库**，两台机器各自配置 signingConfigs。

---

## 7. 里程碑

| 阶段 | 内容 | 验收（真机） |
|---|---|---|
| M1 | 空场景 + 相机 + 光照 + 程序化墙/地板/球 渲染 | 俯瞰 3D 迷宫静态显示 |
| M2 | 传感器接入：倾斜 → 棋盘旋转 + 球物理滚动 | 倾斜手机球往低处滚、碰墙停 |
| M3 | 迷宫生成 + 胜利判定 + UI（计时/重开） | 完整可玩一局 |
| M4 | 打磨：手感参数、阴影/IBL、难度（尺寸/障碍）、按需渲染省电 | 手感好、流畅、省电 |

---

## 8. 开放问题 / 待验证

- 空 Scene 的创建方式（`Scene.load()` 无参 vs 工厂 `createScene()`）。
- 倾斜 → 棋盘旋转四元数的轴/方向/符号（必须真机调）。
- 本机 Node 版本与 hvigorw 构建链路是否通。
- 手机系统/API 版本（授权后查，决定 targetSdkVersion）。
- AGC 账号、包名、签名配置。
- hdc 真机安装/拉起命令的准确形式。
