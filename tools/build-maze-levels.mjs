import fs from 'node:fs';
global.window = undefined;
global.globalThis = globalThis;
new Function('root', fs.readFileSync('js/levels-catalog.js','utf8'))(globalThis);
new Function('root', fs.readFileSync('js/mazes-data.js','utf8'))(globalThis);
const catalog = globalThis.LEVEL_CATALOG;
const data = globalThis.MAZES_DATA;
console.log('levels', catalog.length, 'baked', Object.keys(data).length);
console.log('catalog keys', Object.keys(catalog[0]));
console.log('first 3', JSON.stringify(catalog.slice(0,3)));
const sizes = {};
for (const m of catalog) sizes[m.size] = (sizes[m.size]||0)+1;
console.log('sizes', JSON.stringify(sizes));
const themes = [...new Set(catalog.map(m=>m.theme))];
console.log('themes', themes.join(','));
const withColors = catalog.filter(m=>m.colors);
console.log('with colors', withColors.length, withColors.length? JSON.stringify(withColors[0]) : '');
const out = catalog.map(m => {
  const b = data[m.id];
  return { id:m.id, title:m.title, size:m.size, theme:m.theme, playerEmoji:m.playerEmoji,
           goalEmoji:m.goalEmoji, colors:m.colors||null,
           cells:b.cells, start:b.start, goal:b.goal };
});
fs.writeFileSync('/tmp/maze-levels.json', JSON.stringify(out));
console.log('json bytes', fs.statSync('/tmp/maze-levels.json').size);
