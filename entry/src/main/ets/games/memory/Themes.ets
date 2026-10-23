/**
 * 翻翻乐主题数据 —— 移植自 kids-games/games/memory/{themes,flags,data/provinces-capitals}.js。
 *
 * 主题统一形状 { id, name, match, pairs }:
 *   identical   每对只写一面 card, 两张牌面相同 (认物);
 *   association 每对写 a/b 两面, 牌面不同但关联 (语文 / 英语 / 百科)。
 * say 是配对成功时读出的词, 供 TTS 用。
 *
 * 每个主题至少 15 对, 保证最高档 (🐉 15 对) 每局抽到的都不一样。
 */

/** 一张牌面: emoji / 文字 / 国旗三选一 */
export class Face {
  /** 'emoji' | 'text' | 'flag' */
  type: string = 'text';
  emoji: string = '';
  text: string = '';
  /** 国旗主题的国家代码, 见 flags.ets */
  code: string = '';

  static emojiFace(e: string): Face {
    const f: Face = new Face();
    f.type = 'emoji';
    f.emoji = e;
    return f;
  }

  static textFace(t: string): Face {
    const f: Face = new Face();
    f.type = 'text';
    f.text = t;
    return f;
  }

  static flagFace(code: string): Face {
    const f: Face = new Face();
    f.type = 'flag';
    f.code = code;
    return f;
  }
}

/** 一对卡 */
export class Pair {
  /** identical 主题只看 card; association 看 a/b */
  card: Face = new Face();
  a: Face = new Face();
  b: Face = new Face();
  say: string = '';
}

export class Theme {
  id: string = '';
  name: string = '';
  /** 'identical' | 'association' */
  match: string = 'identical';
  /** 'zero' 认物 | 'chinese' 语文 | 'english' 英语 | 'world' 百科 */
  category: string = 'zero';
  /** 朗读语言, 英文主题用 en-US */
  sayLang: string = 'zh-CN';
  pairs: Pair[] = [];

  constructor(id: string, name: string, match: string, category: string) {
    this.id = id;
    this.name = name;
    this.match = match;
    this.category = category;
  }

  /** 卡片图标: 第一对的一面 (主题卡上展示) */
  icon(): string {
    const p: Pair = this.pairs[0];
    const f: Face = this.match === 'identical' ? p.card : p.a;
    if (f.type === 'emoji') {
      return f.emoji;
    }
    if (f.type === 'flag') {
      return '🏳️';
    }
    return '🔤';
  }

  matchLabel(): string {
    return this.match === 'identical' ? '找相同' : '找关联';
  }

  categoryLabel(): string {
    if (this.category === 'zero') {
      return '认物';
    }
    if (this.category === 'chinese') {
      return '语文';
    }
    if (this.category === 'english') {
      return '英语';
    }
    return '百科';
  }
}

/** 一行的简易构造: identical 主题 */
function emojiPair(emoji: string, say: string): Pair {
  const p: Pair = new Pair();
  p.card = Face.emojiFace(emoji);
  p.say = say;
  return p;
}

/** association 主题: 文字 ↔ 文字 */
function textPair(a: string, b: string, say: string): Pair {
  const p: Pair = new Pair();
  p.a = Face.textFace(a);
  p.b = Face.textFace(b);
  p.say = say;
  return p;
}

function animalPairs(): Pair[] {
  return [
    emojiPair('🐶', '小狗'), emojiPair('🐱', '小猫'), emojiPair('🐰', '兔子'),
    emojiPair('🐼', '熊猫'), emojiPair('🦊', '狐狸'), emojiPair('🐯', '老虎'),
    emojiPair('🦁', '狮子'), emojiPair('🐮', '奶牛'), emojiPair('🐷', '小猪'),
    emojiPair('🐸', '青蛙'), emojiPair('🐵', '猴子'), emojiPair('🐔', '公鸡'),
    emojiPair('🐧', '企鹅'), emojiPair('🐢', '乌龟'), emojiPair('🐬', '海豚'),
    emojiPair('🐳', '鲸鱼'), emojiPair('🦋', '蝴蝶'), emojiPair('🐝', '蜜蜂'),
    emojiPair('🐘', '大象'), emojiPair('🦒', '长颈鹿')
  ];
}

function fruitPairs(): Pair[] {
  return [
    emojiPair('🍎', '苹果'), emojiPair('🍌', '香蕉'), emojiPair('🍊', '橙子'),
    emojiPair('🍇', '葡萄'), emojiPair('🍉', '西瓜'), emojiPair('🍓', '草莓'),
    emojiPair('🍑', '桃子'), emojiPair('🍒', '樱桃'), emojiPair('🥝', '猕猴桃'),
    emojiPair('🍍', '菠萝'), emojiPair('🥥', '椰子'), emojiPair('🥭', '芒果'),
    emojiPair('🍐', '梨'), emojiPair('🍋', '柠檬'), emojiPair('🫐', '蓝莓'),
    emojiPair('🍈', '甜瓜'), emojiPair('🍅', '西红柿')
  ];
}

function hanziPinyinPairs(): Pair[] {
  return [
    textPair('山', 'shān', '山'), textPair('水', 'shuǐ', '水'), textPair('日', 'rì', '日'),
    textPair('月', 'yuè', '月'), textPair('火', 'huǒ', '火'), textPair('土', 'tǔ', '土'),
    textPair('木', 'mù', '木'), textPair('金', 'jīn', '金'), textPair('石', 'shí', '石'),
    textPair('田', 'tián', '田'), textPair('人', 'rén', '人'), textPair('口', 'kǒu', '口'),
    textPair('手', 'shǒu', '手'), textPair('目', 'mù', '目'), textPair('耳', 'ěr', '耳'),
    textPair('云', 'yún', '云'), textPair('雨', 'yǔ', '雨'), textPair('风', 'fēng', '风'),
    textPair('花', 'huā', '花'), textPair('鸟', 'niǎo', '鸟')
  ];
}

function antonymPairs(): Pair[] {
  return [
    textPair('冷', '热', '冷对热'), textPair('大', '小', '大对小'), textPair('高', '矮', '高对矮'),
    textPair('上', '下', '上对下'), textPair('左', '右', '左对右'), textPair('前', '后', '前对后'),
    textPair('快', '慢', '快对慢'), textPair('多', '少', '多对少'), textPair('黑', '白', '黑对白'),
    textPair('新', '旧', '新对旧'), textPair('远', '近', '远对近'), textPair('开', '关', '开对关'),
    textPair('胖', '瘦', '胖对瘦'), textPair('长', '短', '长对短'), textPair('明', '暗', '明对暗'),
    textPair('早', '晚', '早对晚')
  ];
}

/** 英文单词 ↔ emoji 图 */
function wordEmojiPairs(): Pair[] {
  const raw: string[][] = [
    ['apple', '🍎'], ['banana', '🍌'], ['cat', '🐱'], ['dog', '🐶'],
    ['sun', '☀️'], ['star', '⭐'], ['car', '🚗'], ['fish', '🐟'],
    ['bird', '🐦'], ['tree', '🌳'], ['ball', '⚽'], ['book', '📕'],
    ['cake', '🍰'], ['flower', '🌸'], ['moon', '🌙'], ['house', '🏠']
  ];
  const out: Pair[] = [];
  for (let i: number = 0; i < raw.length; i++) {
    const p: Pair = new Pair();
    p.a = Face.textFace(raw[i][0]);
    p.b = Face.emojiFace(raw[i][1]);
    p.say = raw[i][0];
    out.push(p);
  }
  return out;
}

/** 大写 ↔ 小写, 26 个字母全都在 */
function letterCasePairs(): Pair[] {
  const out: Pair[] = [];
  for (let i: number = 0; i < 26; i++) {
    const up: string = String.fromCharCode('A'.charCodeAt(0) + i);
    const lo: string = up.toLowerCase();
    out.push(textPair(up, lo, up));
  }
  return out;
}

/** 国旗 ↔ 国名 */
function flagPairs(): Pair[] {
  const raw: string[][] = [
    ['CN', '中国'], ['JP', '日本'], ['FR', '法国'], ['IT', '意大利'],
    ['DE', '德国'], ['RU', '俄罗斯'], ['NL', '荷兰'], ['BE', '比利时'],
    ['IE', '爱尔兰'], ['RO', '罗马尼亚'], ['AT', '奥地利'], ['SE', '瑞典'],
    ['CH', '瑞士'], ['PL', '波兰'], ['UA', '乌克兰']
  ];
  const out: Pair[] = [];
  for (let i: number = 0; i < raw.length; i++) {
    const p: Pair = new Pair();
    p.a = Face.flagFace(raw[i][0]);
    p.b = Face.textFace(raw[i][1]);
    p.say = raw[i][1];
    out.push(p);
  }
  return out;
}

/** 省份 ↔ 省会, 34 个省级行政区 */
function provinceCapitalPairs(): Pair[] {
  const raw: string[][] = [
    ['北京', '北京'], ['天津', '天津'], ['河北', '石家庄'], ['山西', '太原'],
    ['内蒙古', '呼和浩特'], ['辽宁', '沈阳'], ['吉林', '长春'], ['黑龙江', '哈尔滨'],
    ['上海', '上海'], ['江苏', '南京'], ['浙江', '杭州'], ['安徽', '合肥'],
    ['福建', '福州'], ['江西', '南昌'], ['山东', '济南'], ['河南', '郑州'],
    ['湖北', '武汉'], ['湖南', '长沙'], ['广东', '广州'], ['广西', '南宁'],
    ['海南', '海口'], ['重庆', '重庆'], ['四川', '成都'], ['贵州', '贵阳'],
    ['云南', '昆明'], ['西藏', '拉萨'], ['陕西', '西安'], ['甘肃', '兰州'],
    ['青海', '西宁'], ['宁夏', '银川'], ['新疆', '乌鲁木齐'], ['台湾', '台北'],
    ['香港', '香港'], ['澳门', '澳门']
  ];
  const out: Pair[] = [];
  for (let i: number = 0; i < raw.length; i++) {
    out.push(textPair(raw[i][0], raw[i][1], raw[i][0] + '，' + raw[i][1]));
  }
  return out;
}

/** 八个主题, 顺序由易到难: 认物 → 语文 → 英语 → 百科 */
export function buildThemes(): Theme[] {
  const animals: Theme = new Theme('animals', '动物配对', 'identical', 'zero');
  animals.pairs = animalPairs();

  const fruits: Theme = new Theme('fruits', '水果配对', 'identical', 'zero');
  fruits.pairs = fruitPairs();

  const hanzi: Theme = new Theme('hanzi-pinyin', '汉字配拼音', 'association', 'chinese');
  hanzi.pairs = hanziPinyinPairs();

  const antonyms: Theme = new Theme('antonyms', '反义词配对', 'association', 'chinese');
  antonyms.pairs = antonymPairs();

  const wordEmoji: Theme = new Theme('word-emoji', '单词配图', 'association', 'english');
  wordEmoji.sayLang = 'en-US';
  wordEmoji.pairs = wordEmojiPairs();

  const letters: Theme = new Theme('letter-case', '大写配小写', 'association', 'english');
  letters.sayLang = 'en-US';
  letters.pairs = letterCasePairs();

  const flags: Theme = new Theme('flags', '国旗配国名', 'association', 'world');
  flags.pairs = flagPairs();

  const provCap: Theme = new Theme('prov-cap', '省份配省会', 'association', 'world');
  provCap.pairs = provinceCapitalPairs();

  return [animals, fruits, hanzi, antonyms, wordEmoji, letters, flags, provCap];
}
