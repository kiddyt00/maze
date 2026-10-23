import fs from 'node:fs';
import path from 'node:path';

const SRC = '/home/kiddyt00/GolandProjects/TrailStory/.tmp-kids-games/games/puzzle/data';
const OUT = '/home/kiddyt00/GolandProjects/TrailStory/harmonyos-maze/entry/src/main/resources/rawfile/map';
fs.mkdirSync(OUT, { recursive: true });

global.window = {};
new Function('window', fs.readFileSync(path.join(SRC, 'provinces.js'), 'utf8'))(global.window);
const d = global.window.MAP_DATA;

// 精简: 只保留渲染/放置需要的字段
const provinces = d.provinces.map(p => ({
  id: p.id,
  name: p.name,
  pinyin: p.pinyin,
  region: p.region,
  path: p.path,
  centroid: p.centroid,
  bbox: p.bbox.map(v => Math.round(v * 100) / 100)
}));

const nanhai = {
  path: d.nanhai.path,
  box: d.nanhai.box
};

const national = { width: d.width, height: d.height, provinces, nanhai };
fs.writeFileSync(path.join(OUT, 'national.json'), JSON.stringify(national));

// 分省: 每个省一份, 只保留运行时字段
const idx = [];
for (const f of fs.readdirSync(path.join(SRC, 'puzzles'))) {
  new Function('window', fs.readFileSync(path.join(SRC, 'puzzles', f), 'utf8'))(global.window);
  const adcode = f.replace(/\.js$/, '');
  const pz = global.window.PROVINCE_PUZZLES[adcode];
  const slim = {
    id: pz.id,
    name: pz.name,
    pinyin: pz.pinyin,
    width: pz.width,
    height: pz.height,
    outline: pz.outline,
    snapHint: pz.snapHint,
    pieces: pz.pieces.map(p => ({
      id: p.id,
      name: p.name,
      path: p.path,
      centroid: p.centroid,
      bbox: p.bbox.map(v => Math.round(v * 100) / 100),
      colorIndex: p.colorIndex
    }))
  };
  fs.writeFileSync(path.join(OUT, 'prov-' + adcode + '.json'), JSON.stringify(slim));
  idx.push({ id: pz.id, name: pz.name, pieces: pz.pieces.length });
}
fs.writeFileSync(path.join(OUT, 'index.json'), JSON.stringify(idx));

let total = 0;
for (const f of fs.readdirSync(OUT)) total += fs.statSync(path.join(OUT, f)).size;
console.log('files', fs.readdirSync(OUT).length, 'total MB', (total / 1024 / 1024).toFixed(2));
console.log('national MB', (fs.statSync(path.join(OUT, 'national.json')).size / 1024 / 1024).toFixed(2));
console.log('sample', JSON.stringify(idx.slice(0, 3)));
