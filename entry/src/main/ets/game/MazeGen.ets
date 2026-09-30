/**
 * 迷宫生成 - 递归回溯 (DFS) 算法, 在奇数行/列的网格上进行。
 * 网格 cell 坐标: grid[row][col], row 0 是顶部, col 0 是左侧。
 * 通路格子只在奇数坐标 (1,3,5...), 迷宫大小 rows/cols 必须是奇数。
 */
export const CELL_EMPTY: number = 0;
export const CELL_WALL: number = 1;

export interface Maze {
  rows: number;
  cols: number;
  grid: number[][];
  startRow: number;
  startCol: number;
  goalRow: number;
  goalCol: number;
}

class Cell {
  row: number;
  col: number;

  constructor(row: number, col: number) {
    this.row = row;
    this.col = col;
  }
}

// 每次前进 2 格 (跳过中间的墙格), 顺序无关紧要, 随机选取
const DIRS: number[][] = [
  [0, 2],
  [2, 0],
  [0, -2],
  [-2, 0]
];

export function generateMaze(rows: number, cols: number): Maze {
  const grid: number[][] = [];
  for (let r = 0; r < rows; r++) {
    const rowArr: number[] = [];
    for (let c = 0; c < cols; c++) {
      rowArr.push(CELL_WALL);
    }
    grid.push(rowArr);
  }

  grid[1][1] = CELL_EMPTY;
  const stack: Cell[] = [new Cell(1, 1)];

  while (stack.length > 0) {
    const cur: Cell = stack[stack.length - 1];
    const candidates: Cell[] = [];
    for (let i = 0; i < DIRS.length; i++) {
      const nr: number = cur.row + DIRS[i][0];
      const nc: number = cur.col + DIRS[i][1];
      if (nr > 0 && nr < rows - 1 && nc > 0 && nc < cols - 1 && grid[nr][nc] === CELL_WALL) {
        candidates.push(new Cell(nr, nc));
      }
    }
    if (candidates.length === 0) {
      stack.pop();
      continue;
    }
    const chosen: Cell = candidates[Math.floor(Math.random() * candidates.length)];
    const midR: number = Math.floor((cur.row + chosen.row) / 2);
    const midC: number = Math.floor((cur.col + chosen.col) / 2);
    grid[midR][midC] = CELL_EMPTY;
    grid[chosen.row][chosen.col] = CELL_EMPTY;
    stack.push(chosen);
  }

  return {
    rows: rows,
    cols: cols,
    grid: grid,
    startRow: 1,
    startCol: 1,
    goalRow: rows - 2,
    goalCol: cols - 2
  };
}
