// Generate hvigor signing material + encrypted passwords.
// Replicates the DevEco encryption scheme reverse-engineered from
// hvigor-ohos-plugin/src/utils/decipher-util.js
//
// Expected layout (from decipher-util.js readDirBytes/readFd/readSalt/readWorkMaterial):
//   <materialDir>/fd/{a,b,c}/<one file>   -- each is a DIRECTORY containing exactly 1 file (16 bytes)
//   <materialDir>/ac/<one file>           -- salt, directory containing exactly 1 file
//   <materialDir>/ce/<one file>           -- work material, directory containing exactly 1 file
'use strict';
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const COMPONENT = Buffer.from([49,243,9,115,214,175,91,184,211,190,177,88,101,131,192,119]);

function xor16(...bufs) {
  const out = Buffer.alloc(16);
  for (const b of bufs) for (let i = 0; i < 16; i++) out[i] ^= b[i];
  return out;
}

// Format matches DecipherUtil.decrypt: [4B e][iv][ct][16B tag]
// decrypt: e = (r[0]<<24)|(r[1]<<16)|(r[2]<<8)|r[3]; i = r.length-4-e;
//          iv = r.slice(4, 4+i); tag = r.slice(r.length-16);
//          ct = r.subarray(4+i, r.length-16)
// => first 4 bytes store (totalLen - 4 - ivLen); iv length = r.length-4-e
function encAes128Gcm(key, plaintext) {
  const iv = crypto.randomBytes(12);
  const c = crypto.createCipheriv('aes-128-gcm', key, iv);
  const ct = Buffer.concat([c.update(plaintext, 'utf8'), c.final()]);
  const tag = c.getAuthTag();
  const total = 4 + iv.length + ct.length + 16;
  const header = Buffer.alloc(4);
  header.writeUInt32BE(total - 4 - iv.length, 0); // = ct.length + 16
  return Buffer.concat([header, iv, ct, tag]);
}

const materialDir = path.resolve(__dirname, 'material');
fs.rmSync(materialDir, { recursive: true, force: true });

// fd: 3 subdirs (a,b,c) each containing ONE 16-byte file;
// XOR(fd0,fd1,fd2,COMPONENT) = seed (order-independent)
const seed = crypto.randomBytes(16);
const fd0 = crypto.randomBytes(16);
const fd1 = crypto.randomBytes(16);
const fd2 = xor16(fd0, fd1, COMPONENT, seed);
if (!xor16(fd0, fd1, fd2, COMPONENT).equals(seed)) throw new Error('fd generation failed');
const fdNames = ['a', 'b', 'c'];
const fdData = [fd0, fd1, fd2];
fdNames.forEach((name, idx) => {
  const d = path.join(materialDir, 'fd', name);
  fs.mkdirSync(d, { recursive: true });
  fs.writeFileSync(path.join(d, 'data'), fdData[idx]);
});

// salt (ac): directory containing exactly 1 file
const salt = crypto.randomBytes(16);
fs.mkdirSync(path.join(materialDir, 'ac'), { recursive: true });
fs.writeFileSync(path.join(materialDir, 'ac', 'salt'), salt);

// rootKey = pbkdf2(seed.toString(), salt, 10000, 16, sha256)
// NOTE: Buffer.toString() default utf8 - must match hvigor's _.toString()
const rootKey = crypto.pbkdf2Sync(seed.toString('utf8'), salt, 10000, 16, 'sha256');

// work key (ce): encrypted with rootKey
const workKey = crypto.randomBytes(16);
const workMaterial = encAes128Gcm(rootKey, workKey);
fs.mkdirSync(path.join(materialDir, 'ce'), { recursive: true });
fs.writeFileSync(path.join(materialDir, 'ce', 'work'), workMaterial);

const plainPwd = process.argv[2] || 'mazeball2026mazeball2026mazeball2026';
const encPwd = encAes128Gcm(workKey, plainPwd).toString('hex');

console.log('material written to', materialDir);
console.log('ENCRYPTED_PASSWORD=' + encPwd);
