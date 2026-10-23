/**
 * 随机数 —— 游戏里所有"抽一下"都走这里, 方便以后换成可复现的种子随机。
 * 原 kids-learning-games 直接用 Phaser.Math.FloatBetween / Math.random。
 */
export function genRandom(): number {
  return Math.random();
}

/** [lo, hi) 之间的浮点 */
export function randBetween(lo: number, hi: number): number {
  return lo + Math.random() * (hi - lo);
}
