/**
 * 跟读训练内容库 (v0.1 静态版)。
 *
 * 设计要点 (详见 docs/跟读游戏交互设计.md):
 *  - 面向还不识字的小朋友: 每条都配一个 emoji 图形, 文字只作为家长辅助;
 *  - 中文给拼音提示, 英文给音标提示;
 *  - 目前是静态内容, 后续可由端侧 LLM 按孩子兴趣动态出题。
 */

export const LANG_ZH: string = 'zh-CN';
export const LANG_EN: string = 'en-US';

export interface ReadItem {
  /** 跟读目标 (汉字 / 英文单词 / 诗句) */
  text: string;
  /** 拼音或音标提示 */
  hint: string;
  /** 图形提示, 给孩子看 */
  emoji: string;
  /** 朗读与识别语言 */
  lang: string;
}

export interface ReadModule {
  key: string;
  name: string;
  emoji: string;
  color: string;
  items: ReadItem[];
}

export interface ReadHall {
  key: string;
  name: string;
  emoji: string;
  color: string;
  modules: ReadModule[];
}

function zh(text: string, hint: string, emoji: string): ReadItem {
  return { text: text, hint: hint, emoji: emoji, lang: LANG_ZH };
}

function en(text: string, hint: string, emoji: string): ReadItem {
  return { text: text, hint: hint, emoji: emoji, lang: LANG_EN };
}

function mod(key: string, name: string, emoji: string, color: string, items: ReadItem[]): ReadModule {
  return { key: key, name: name, emoji: emoji, color: color, items: items };
}

function hall(key: string, name: string, emoji: string, color: string, modules: ReadModule[]): ReadHall {
  return { key: key, name: name, emoji: emoji, color: color, modules: modules };
}

export function buildHalls(): ReadHall[] {
  const zhHall: ReadHall = hall('zh', '中文馆', '📕', '#7A3B5E', [
    mod('zh-color', '颜色', '🎨', '#6E3350', [
      zh('红', 'hóng', '🔴'),
      zh('黄', 'huáng', '🟡'),
      zh('蓝', 'lán', '🔵'),
      zh('绿', 'lǜ', '🟢'),
      zh('白', 'bái', '⚪'),
      zh('黑', 'hēi', '⚫')
    ]),
    mod('zh-animal', '动物', '🐼', '#2F5D50', [
      zh('猫', 'māo', '🐱'),
      zh('狗', 'gǒu', '🐶'),
      zh('兔', 'tù', '🐰'),
      zh('鱼', 'yú', '🐟'),
      zh('鸟', 'niǎo', '🐦'),
      zh('象', 'xiàng', '🐘')
    ]),
    mod('zh-object', '简单物体', '🧸', '#4A4A7A', [
      zh('球', 'qiú', '⚽'),
      zh('书', 'shū', '📖'),
      zh('杯', 'bēi', '🥤'),
      zh('车', 'chē', '🚗'),
      zh('伞', 'sǎn', '☂️'),
      zh('花', 'huā', '🌸')
    ]),
    mod('zh-number', '数字', '🔢', '#7A5A2F', [
      zh('一', 'yī', '1️⃣'),
      zh('二', 'èr', '2️⃣'),
      zh('三', 'sān', '3️⃣'),
      zh('四', 'sì', '4️⃣'),
      zh('五', 'wǔ', '5️⃣')
    ]),
    mod('zh-poem', '古诗词', '📜', '#5A3A6E', [
      zh('床前明月光', 'chuáng qián míng yuè guāng', '🌕'),
      zh('疑是地上霜', 'yí shì dì shàng shuāng', '❄️'),
      zh('举头望明月', 'jǔ tóu wàng míng yuè', '🙌'),
      zh('低头思故乡', 'dī tóu sī gù xiāng', '🏠'),
      zh('鹅鹅鹅', 'é é é', '🦢'),
      zh('曲项向天歌', 'qū xiàng xiàng tiān gē', '🎶'),
      zh('白毛浮绿水', 'bái máo fú lǜ shuǐ', '💚'),
      zh('红掌拨清波', 'hóng zhǎng bō qīng bō', '🌊')
    ]),
    mod('zh-char', '认字启蒙', '✏️', '#2F4A6E', [
      zh('日', 'rì', '☀️'),
      zh('月', 'yuè', '🌙'),
      zh('山', 'shān', '⛰️'),
      zh('水', 'shuǐ', '💧'),
      zh('火', 'huǒ', '🔥'),
      zh('木', 'mù', '🌳'),
      zh('人', 'rén', '🧍'),
      zh('口', 'kǒu', '👄')
    ])
  ]);

  const enHall: ReadHall = hall('en', 'English', '📘', '#2F4E7A', [
    mod('en-color', 'Colors', '🎨', '#2F4E7A', [
      en('red', '/red/', '🔴'),
      en('blue', '/bluː/', '🔵'),
      en('green', '/ɡriːn/', '🟢'),
      en('yellow', '/ˈjeloʊ/', '🟡'),
      en('black', '/blæk/', '⚫'),
      en('white', '/waɪt/', '⚪')
    ]),
    mod('en-animal', 'Animals', '🐾', '#2F5D50', [
      en('cat', '/kæt/', '🐱'),
      en('dog', '/dɔːɡ/', '🐶'),
      en('rabbit', '/ˈræbɪt/', '🐰'),
      en('fish', '/fɪʃ/', '🐟'),
      en('bird', '/bɜːrd/', '🐦'),
      en('elephant', '/ˈelɪfənt/', '🐘')
    ]),
    mod('en-object', 'Objects', '🧸', '#4A4A7A', [
      en('ball', '/bɔːl/', '⚽'),
      en('book', '/bʊk/', '📖'),
      en('cup', '/kʌp/', '🥤'),
      en('car', '/kɑːr/', '🚗'),
      en('star', '/stɑːr/', '⭐'),
      en('flower', '/ˈflaʊər/', '🌸')
    ]),
    mod('en-number', 'Numbers', '🔢', '#7A5A2F', [
      en('one', '/wʌn/', '1️⃣'),
      en('two', '/tuː/', '2️⃣'),
      en('three', '/θriː/', '3️⃣'),
      en('four', '/fɔːr/', '4️⃣'),
      en('five', '/faɪv/', '5️⃣')
    ]),
    mod('en-abc', 'Letters', '🔤', '#3A3A6E', [
      en('A', '/eɪ/  apple', '🍎'),
      en('B', '/biː/  ball', '⚽'),
      en('C', '/siː/  cat', '🐱'),
      en('D', '/diː/  dog', '🐶'),
      en('E', '/iː/  egg', '🥚')
    ])
  ]);

  return [zhHall, enHall];
}
