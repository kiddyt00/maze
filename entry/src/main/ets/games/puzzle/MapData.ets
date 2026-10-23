/**
 * 地图数据 —— 移植自 kids-games/games/puzzle/data。
 *
 * 原始数据是浏览器脚本 (window.MAP_DATA / window.PROVINCE_PUZZLES), 这里预转换成
 * resources/rawfile/map/*.json, 运行时用 resourceManager 读进内存。
 *
 * 数据集统一形状 (与原 main.js 的 nationalDataset / provinceDataset 一致):
 *   { width, height, items[], outline, nanhai, byRegionCapable, snap, name }
 * 全国与分省只差字段有无, 渲染与拖拽逻辑因此可以完全共用。
 */
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { resourceManager } from '@kit.LocalizationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0001;
const TAG: string = 'KidsPuzzle';

/** 一块拼图 (省 或 地级市) */
export class Piece {
  id: string = '';
  name: string = '';
  /** SVG path, 只含 M/L/Z 命令 */
  path: string = '';
  /** 重心, 用来判定吸附 */
  cx: number = 0;
  cy: number = 0;
  /** [x0, y0, x1, y1] */
  bbox: number[] = [];
  /** 分省拼图的配色索引; 全国拼图用 region 上色 */
  colorIndex: number = 0;
  /** 七大区 (仅全国): 华北/东北/华东/华中/华南/西南/西北 */
  region: string = '';
  /** 拼音 (简单档显示) */
  pinyin: string = '';
  /** 放置完成 */
  placed: boolean = false;
}

/** 南海诸岛装饰图 */
export class NanhaiBox {
  x: number = 0;
  y: number = 0;
  w: number = 0;
  h: number = 0;
  scale: number = 1;
}

export class Dataset {
  width: number = 1000;
  height: number = 820;
  items: Piece[] = [];
  /** 分省时的一条省外框; 全国为 null */
  outline: string = '';
  nanhaiPath: string = '';
  nanhaiBox: NanhaiBox | null = null;
  byRegionCapable: boolean = false;
  snap: number = 30;
  /** 分省时的省名 */
  name: string = '';
}

/** 分省索引 (省份选择网格用) */
export class ProvinceEntry {
  id: string = '';
  name: string = '';
  pieces: number = 0;
}

// ---------- JSON 反序列化的中间形状 (ArkTS 不允许直接 as 到类, 用 interface 接) ----------

interface PieceJson {
  id: string;
  name: string;
  path: string;
  centroid: number[];
  bbox: number[];
  colorIndex: number;
  region: string;
  pinyin: string;
}

interface NanhaiJson {
  path: string;
  box: NanhaiBox;
}

interface NationalJson {
  width: number;
  height: number;
  provinces: PieceJson[];
  nanhai: NanhaiJson;
}

interface ProvinceJson {
  id: string;
  name: string;
  pinyin: string;
  width: number;
  height: number;
  outline: string;
  snapHint: number;
  pieces: PieceJson[];
}

interface IndexJson {
  id: string;
  name: string;
  pieces: number;
}

function toPiece(j: PieceJson): Piece {
  const p: Piece = new Piece();
  p.id = j.id;
  p.name = j.name;
  p.path = j.path;
  p.cx = j.centroid[0];
  p.cy = j.centroid[1];
  p.bbox = j.bbox;
  p.colorIndex = j.colorIndex === undefined ? 0 : j.colorIndex;
  p.region = j.region === undefined ? '' : j.region;
  p.pinyin = j.pinyin === undefined ? '' : j.pinyin;
  return p;
}

export class MapLoader {
  private rm: resourceManager.ResourceManager | null = null;

  init(context: common.UIAbilityContext): void {
    if (this.rm !== null) {
      return;
    }
    this.rm = context.resourceManager;
  }

  /** 读 rawfile 里的 JSON 文本 */
  private readText(file: string): string {
    if (this.rm === null) {
      return '';
    }
    try {
      const bytes: Uint8Array = this.rm.getRawFileContentSync('map/' + file);
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
      return decoder.decodeToString(bytes);
    } catch (e) {
      const err: Error = e as Error;
      hilog.error(DOMAIN, TAG, 'read %{public}s failed: %{public}s', file, err.message);
      return '';
    }
  }

  /** 全国数据集 */
  national(): Dataset | null {
    const txt: string = this.readText('national.json');
    if (txt.length === 0) {
      return null;
    }
    const j: NationalJson = JSON.parse(txt) as NationalJson;
    const d: Dataset = new Dataset();
    d.width = j.width;
    d.height = j.height;
    d.byRegionCapable = true;
    d.outline = '';
    for (let i: number = 0; i < j.provinces.length; i++) {
      d.items.push(toPiece(j.provinces[i]));
    }
    if (j.nanhai !== undefined && j.nanhai !== null) {
      d.nanhaiPath = j.nanhai.path;
      d.nanhaiBox = j.nanhai.box;
    }
    return d;
  }

  /** 某个省的分省数据集 */
  province(adcode: string): Dataset | null {
    const txt: string = this.readText('prov-' + adcode + '.json');
    if (txt.length === 0) {
      return null;
    }
    const j: ProvinceJson = JSON.parse(txt) as ProvinceJson;
    const d: Dataset = new Dataset();
    d.width = j.width;
    d.height = j.height;
    d.byRegionCapable = false;
    d.outline = j.outline;
    d.name = j.name;
    d.snap = j.snapHint;
    for (let i: number = 0; i < j.pieces.length; i++) {
      d.items.push(toPiece(j.pieces[i]));
    }
    return d;
  }

  /** 有分省数据的省列表 */
  provinceIndex(): ProvinceEntry[] {
    const txt: string = this.readText('index.json');
    if (txt.length === 0) {
      return [];
    }
    const arr: IndexJson[] = JSON.parse(txt) as IndexJson[];
    const out: ProvinceEntry[] = [];
    for (let i: number = 0; i < arr.length; i++) {
      const e: ProvinceEntry = new ProvinceEntry();
      e.id = arr[i].id;
      e.name = arr[i].name;
      e.pieces = arr[i].pieces;
      out.push(e);
    }
    return out;
  }
}

/** 七大区 (简单档分关顺序: 由近及远) */
export const REGION_ORDER: string[] = ['东北', '华北', '华东', '华中', '华南', '西南', '西北'];

/** 七大区配色 (放置后按区上色, 顺便认识地理分区) */
export const REGION_COLORS: Map<string, string> = new Map<string, string>([
  ['华北', '#f4b942'],
  ['东北', '#4cc1a1'],
  ['华东', '#5b9be8'],
  ['华中', '#ec7d7d'],
  ['华南', '#b07be0'],
  ['西南', '#f08a4b'],
  ['西北', '#8bc34a']
]);

/** 分省地市块的调色板 */
export const PIECE_PALETTE: string[] = [
  '#f4b942', '#5b9be8', '#ec7d7d', '#4cc1a1', '#b07be0', '#f08a4b',
  '#8bc34a', '#26c6da', '#ff8a80', '#9575cd', '#4db6ac', '#ffb74d'
];

/** 按块取色: 有 region 走七大区, 否则走调色板 */
export function pieceColor(p: Piece): string {
  if (p.region.length > 0) {
    const c: string | undefined = REGION_COLORS.get(p.region);
    return c === undefined ? '#7bc4a4' : c;
  }
  return PIECE_PALETTE[p.colorIndex % PIECE_PALETTE.length];
}
