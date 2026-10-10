/**
 * 跟读评分 —— 把"识别到的文字"变成"小朋友看得懂的正向反馈"。
 *
 * 现实约束: 端侧 SDK 没有音素级发音评测接口 (只有整句文字识别结果),
 * 所以这里用三层启发式做近似评分:
 *   完整度 coverage = 目标有多少被读出来   (加权 40%)
 *   正确度 accuracy = 读出来的有多少是对的 (加权 40%)
 *   流利度 fluency  = 语速是否接近自然语速 (加权 20%)
 *
 * 两个关键设计:
 *  1) 同音字容错 —— 孩子把"四"读成"是"、把"兔"读成"图", ASR 会给出同音字,
 *     靠 HOMO 同音组把它们算成"基本读对", 否则评分会冤枉小朋友。
 *  2) 永不失败 —— 无论多低的分都落到正向档位 (tier 0 也有鼓励话术),
 *     真正的"要复习"只变成一个内部标记, 不呈现给孩子。
 */
import { LANG_ZH } from './Content';

/** 同音字/近音字分组: 同一组内的字互相认作"读对了"。 */
const HOMO_GROUPS: string[] = [
  '红洪宏虹鸿弘轰哄',
  '黄皇煌凰蝗簧王',
  '蓝兰篮栏拦澜婪',
  '绿律率虑滤旅吕铝驴露录陆路鹿鲁',
  '白百摆败拜柏',
  '黑嘿嗨',
  '猫毛矛茅冒帽茂贸',
  '狗够构购沟钩勾苟',
  '兔图突途涂土吐徒屠',
  '鱼于余与雨语玉育遇预宇羽娱渔愉逾愚',
  '鸟尿溺',
  '象像向相香想响箱乡项详享',
  '球求秋丘邱囚酋',
  '书树数输舒叔属束述术竖蔬殊梳熟',
  '杯背北被倍备悲碑贝辈',
  '车扯撤彻澈',
  '伞三散衫',
  '花话画华化划滑哗',
  '一衣医依姨移疑已以意易益艺义议椅蚁遗',
  '二儿而耳尔饵',
  '床窗创疮闯',
  '前钱千签浅潜迁牵铅歉欠',
  '明名鸣命铭',
  '月乐越阅跃岳悦',
  '光广逛',
  '是事时十使世市试式士示视室食识实石师失施湿诗尸拾驶始',
  '地低的第弟底抵帝滴敌递',
  '上伤商尚赏裳',
  '霜双爽',
  '举句局橘菊巨具据距聚居拘',
  '头投偷透',
  '望王忘网往亡旺汪',
  '思四死丝司私斯撕寺饲',
  '故古谷骨鼓股顾姑孤菇雇',
  '鹅饿恶额俄娥蛾',
  '曲去区取趣娶屈驱趋',
  '歌哥个各格割搁戈鸽胳',
  '浮服福副幅富夫扶肤符府腐妇附复负',
  '水睡税谁',
  '掌长张章涨帐账丈障',
  '拨波播玻剥博伯泊勃脖',
  '清青轻情请晴亲氢倾',
  '山扇闪善单衫',
  '火或活货伙获惑霍',
  '木目母幕墓慕牧亩拇',
  '人认任忍仁韧',
  '口扣抠叩寇',
  '日',
  '木'
];

const HOMO: Map<string, number> = buildHomoMap();

function buildHomoMap(): Map<string, number> {
  const map: Map<string, number> = new Map<string, number>();
  for (let g: number = 0; g < HOMO_GROUPS.length; g++) {
    const group: string = HOMO_GROUPS[g];
    for (let i: number = 0; i < group.length; i++) {
      map.set(group.charAt(i), g);
    }
  }
  return map;
}

export interface ReadScore {
  /** 0..100, 仅用于内部排序与家长报告 */
  score: number;
  /** 1..3 星 */
  stars: number;
  /** 0..3, 越高越好, 4 档全部是正向文案 */
  tier: number;
  /** 给孩子听/看的肯定话术 */
  verdict: string;
  /** 交给 TTS 说的鼓励句 */
  praiseVoice: string;
  coverage: number;
  accuracy: number;
  fluency: number;
  /** 识别到的原文 (家长可见) */
  heard: string;
  /** 建议复习的字 (内部标记, 不呈现给孩子) */
  weak: string[];
  /** 英文等无法可靠识别的语种: false 表示只按"敢开口"给正向反馈 */
  scored: boolean;
}

const NO_SPEECH: ReadScore = {
  score: 0, stars: 1, tier: 0,
  verdict: '我没听清，我们再试一次好不好？',
  praiseVoice: '没关系，我们一起再读一遍。',
  coverage: 0, accuracy: 0, fluency: 0, heard: '', weak: [], scored: false
};

export function noSpeechScore(): ReadScore {
  return NO_SPEECH;
}

/** 去掉空白与标点, 英文转小写。 */
export function normalizeText(text: string): string {
  let out: string = '';
  for (let i: number = 0; i < text.length; i++) {
    const c: string = text.charAt(i);
    if (isSkip(c)) {
      continue;
    }
    out += c;
  }
  return out;
}

function isSkip(c: string): boolean {
  if (c === ' ' || c === '\t' || c === '\n' || c === '\r') {
    return true;
  }
  const code: number = c.charCodeAt(0);
  // 半角标点
  if (code >= 0x21 && code <= 0x2F) {
    return true;
  }
  if (code >= 0x3A && code <= 0x40) {
    return true;
  }
  if (code >= 0x5B && code <= 0x60) {
    return true;
  }
  if (code >= 0x7B && code <= 0x7E) {
    return true;
  }
  // 全角标点 / 常见中文标点
  if (code >= 0x3000 && code <= 0x303F) {
    return true;
  }
  if (code === 0xFF01 || code === 0xFF0C || code === 0xFF1A || code === 0xFF1B || code === 0xFF1F) {
    return true;
  }
  return false;
}

function toUnits(text: string, lang: string): string[] {
  const n: string = normalizeText(text);
  const units: string[] = [];
  if (lang === LANG_ZH) {
    for (let i: number = 0; i < n.length; i++) {
      units.push(n.charAt(i).toLowerCase());
    }
    return units;
  }
  let cur: string = '';
  for (let i: number = 0; i < n.length; i++) {
    const c: string = n.charAt(i).toLowerCase();
    if (c === ' ') {
      if (cur.length > 0) {
        units.push(cur);
        cur = '';
      }
    } else {
      cur += c;
    }
  }
  if (cur.length > 0) {
    units.push(cur);
  }
  // 英文单字也拆成字母做兜底匹配 ("apple" vs "appl")
  return units;
}

/** 两个单元是否算"读对"。 */
function isMatch(a: string, b: string, lang: string): boolean {
  if (a === b) {
    return true;
  }
  if (lang === LANG_ZH) {
    const ga: number | undefined = HOMO.get(a);
    const gb: number | undefined = HOMO.get(b);
    return ga !== undefined && gb !== undefined && ga === gb;
  }
  // 英文: 允许一个字母以内的听写误差
  if (Math.abs(a.length - b.length) > 1) {
    return false;
  }
  return editDistance(a, b) <= 1;
}

function editDistance(a: string, b: string): number {
  const n: number = b.length;
  let prev: number[] = [];
  for (let j: number = 0; j <= n; j++) {
    prev.push(j);
  }
  for (let i: number = 1; i <= a.length; i++) {
    const cur: number[] = [i];
    for (let j: number = 1; j <= n; j++) {
      const cost: number = a.charAt(i - 1) === b.charAt(j - 1) ? 0 : 1;
      const del: number = prev[j] + 1;
      const ins: number = cur[j - 1] + 1;
      const sub: number = prev[j - 1] + cost;
      let m: number = del < ins ? del : ins;
      if (sub < m) {
        m = sub;
      }
      cur.push(m);
    }
    prev = cur;
  }
  return prev[n];
}

interface LcsResult {
  len: number;
  hit: boolean[];
}

/** 模糊最长公共子序列, 同时回填目标里哪些单元被读到了。 */
function lcsFuzzy(target: string[], heard: string[], lang: string): LcsResult {
  const n: number = target.length;
  const m: number = heard.length;
  const dp: number[][] = [];
  for (let i: number = 0; i <= n; i++) {
    const row: number[] = [];
    for (let j: number = 0; j <= m; j++) {
      row.push(0);
    }
    dp.push(row);
  }
  for (let i: number = 1; i <= n; i++) {
    for (let j: number = 1; j <= m; j++) {
      if (isMatch(target[i - 1], heard[j - 1], lang)) {
        dp[i][j] = dp[i - 1][j - 1] + 1;
      } else {
        dp[i][j] = dp[i - 1][j] > dp[i][j - 1] ? dp[i - 1][j] : dp[i][j - 1];
      }
    }
  }
  const hit: boolean[] = [];
  for (let i: number = 0; i < n; i++) {
    hit.push(false);
  }
  let i: number = n;
  let j: number = m;
  while (i > 0 && j > 0) {
    if (isMatch(target[i - 1], heard[j - 1], lang) && dp[i][j] === dp[i - 1][j - 1] + 1) {
      hit[i - 1] = true;
      i--;
      j--;
    } else if (dp[i - 1][j] >= dp[i][j - 1]) {
      i--;
    } else {
      j--;
    }
  }
  return { len: dp[n][m], hit: hit };
}

function clamp01(v: number): number {
  if (v < 0) {
    return 0;
  }
  return v > 1 ? 1 : v;
}

/**
 * 给一次跟读打分。
 * @param target 目标文本
 * @param heard  ASR 识别到的文本
 * @param speechMs 有效发音时长 (毫秒)
 * @param lang 语种
 */
export function scoreRead(target: string, heard: string, speechMs: number, lang: string): ReadScore {
  const targetUnits: string[] = toUnits(target, lang);
  const heardUnits: string[] = toUnits(heard, lang);
  if (targetUnits.length === 0) {
    return NO_SPEECH;
  }
  if (heardUnits.length === 0) {
    return NO_SPEECH;
  }

  const lcs: LcsResult = lcsFuzzy(targetUnits, heardUnits, lang);
  const coverage: number = clamp01(lcs.len / targetUnits.length);
  const denom: number = targetUnits.length > heardUnits.length ? targetUnits.length : heardUnits.length;
  const accuracy: number = clamp01(lcs.len / denom);

  // 流利度: 语速越接近自然语速越高, 但下限 0.3, 不让孩子因为"读得慢"丢分太多。
  const perUnit: number = lang === LANG_ZH ? 400 : 550;
  const expected: number = targetUnits.length * perUnit;
  let fluency: number = 1 - Math.abs(speechMs - expected) / (expected * 1.5);
  fluency = clamp01(fluency);
  if (fluency < 0.3) {
    fluency = 0.3;
  }

  const scored: boolean = lang === LANG_ZH;
  let score: number;
  if (scored) {
    score = Math.round(coverage * 40 + accuracy * 40 + fluency * 20);
  } else {
    // 离线引擎只认中文, 英文不做"正确度"断言: 敢开口 + 读完整就算完成。
    score = Math.round(40 + coverage * 30 + fluency * 20);
  }

  const weak: string[] = [];
  for (let i: number = 0; i < targetUnits.length; i++) {
    if (!lcs.hit[i]) {
      weak.push(targetUnits[i]);
    }
  }

  let tier: number;
  let stars: number;
  let verdict: string;
  let praiseVoice: string;
  if (!scored) {
    tier = 3;
    stars = 3;
    verdict = '读完啦！真棒！';
    praiseVoice = '读完啦，真棒！我们再来一个好不好？';
  } else if (score >= 90) {
    tier = 3;
    stars = 3;
    verdict = '太棒了！又准又流利！';
    praiseVoice = '太棒了，读得又准又流利！';
  } else if (score >= 70) {
    tier = 2;
    stars = 2;
    verdict = '很好！已经很接近标准音啦！';
    praiseVoice = '很好，已经很接近标准音啦！';
  } else if (score >= 50) {
    tier = 1;
    stars = 1;
    verdict = '快对了！再来一遍就更好了～';
    praiseVoice = '快对了，再来一遍就更好了。';
  } else {
    tier = 0;
    stars = 1;
    verdict = '没关系，跟着我慢慢读～';
    praiseVoice = '没关系，跟着我慢慢读。';
  }

  return {
    score: score,
    stars: stars,
    tier: tier,
    verdict: verdict,
    praiseVoice: praiseVoice,
    coverage: coverage,
    accuracy: accuracy,
    fluency: fluency,
    heard: heard,
    weak: weak,
    scored: scored
  };
}

/** 递进式脚手架: 第几轮该给什么提示 (绝不卡关)。 */
export function scaffoldOf(round: number): string {
  if (round <= 0) {
    return '先听一遍标准音，然后大声读出来';
  }
  if (round === 1) {
    return '放慢一点，一个字一个字读给我听';
  }
  if (round === 2) {
    return '跟着我把每个字拆开读一遍';
  }
  return '我们一起读最后一遍，读完就过关！';
}
