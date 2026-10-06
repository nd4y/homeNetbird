// Recolor the official NetBird SVG geometry; rasterize at each native tray size.
const fs = require('fs');
const path = require('path');
const sharp = require('sharp');
const out = path.join(__dirname, 'icons');
fs.mkdirSync(out, {recursive:true});
const palettes = {
  Connected:['#38F5DD','#06B6D4','#598CFF','#864CFF','#36DDF5','#C55CFF'],
  Degraded:['#FFECA4','#FFAD3E','#FF9A61','#F34D8A','#FFE18A','#FC669F'],
  Disconnected:['#91A4C2','#5D7197','#667FAD','#454D79','#9D749E','#EF718F'],
  Unavailable:['#9EAFC5','#687C99','#7488A5','#455773','#8C9FB7','#617790']
};
function svg(p) {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 32 32">
  <defs>
    <linearGradient id="left" x1="0" y1="0" x2="1" y2="1"><stop stop-color="${p[0]}"/><stop offset="1" stop-color="${p[1]}"/></linearGradient>
    <linearGradient id="right" x1="0" y1="0" x2=".7" y2="1"><stop stop-color="${p[2]}"/><stop offset="1" stop-color="${p[3]}"/></linearGradient>
    <linearGradient id="fold" x1="0" y1="0" x2=".6" y2="1"><stop stop-color="${p[4]}"/><stop offset="1" stop-color="${p[5]}"/></linearGradient>
  </defs>
  <g transform="translate(.85 4.5)">
    <path d="M21.4631 .523438C17.8173 .857913 16.0028 2.95675 15.3171 4.01871L4.66406 22.4734H17.5163L30.1929 .523438H21.4631Z" fill="url(#right)"/>
    <path d="M17.5265 22.4737L0 3.88525C0 3.88525 19.8177 -1.44128 21.7493 15.1738L17.5265 22.4737Z" fill="url(#left)"/>
    <path d="M14.9236 4.70563L9.54688 14.0208L17.5158 22.4747L21.7385 15.158C21.0696 9.44682 18.2851 6.32784 14.9236 4.69727" fill="url(#fold)"/>
  </g></svg>`;
}
function dib(rgba,n) {
  const stride=Math.ceil(n/32)*4;
  const b=Buffer.alloc(40+n*n*4+stride*n);
  b.writeUInt32LE(40,0); b.writeInt32LE(n,4); b.writeInt32LE(n*2,8);
  b.writeUInt16LE(1,12); b.writeUInt16LE(32,14); b.writeUInt32LE(n*n*4,20);
  for(let y=0;y<n;y++)for(let x=0;x<n;x++){
    const src=(y*n+x)*4, dest=40+((n-1-y)*n+x)*4;
    b[dest]=rgba[src+2]; b[dest+1]=rgba[src+1]; b[dest+2]=rgba[src]; b[dest+3]=rgba[src+3];
    if(rgba[src+3]===0)b[40+n*n*4+(n-1-y)*stride+(x>>3)]|=0x80>>(x%8);
  }
  return b;
}
(async()=>{
  for(const [name,palette] of Object.entries(palettes)){
    const source=svg(palette);
    fs.writeFileSync(path.join(out,`home-${name.toLowerCase()}.svg`),source);
    await sharp(Buffer.from(source)).png().toFile(path.join(out,`home-${name.toLowerCase()}.png`));
    const sizes=[16,20,24,32,48,64];
    const frames=[];
    for(const n of sizes)frames.push(dib(await sharp(Buffer.from(source)).resize(n,n).ensureAlpha().raw().toBuffer(),n));
    const head=Buffer.alloc(6+sizes.length*16); head.writeUInt16LE(1,2); head.writeUInt16LE(sizes.length,4);
    let offset=head.length;
    sizes.forEach((n,i)=>{const e=6+i*16; head[e]=n;head[e+1]=n;head.writeUInt16LE(1,e+4);head.writeUInt16LE(32,e+6);head.writeUInt32LE(frames[i].length,e+8);head.writeUInt32LE(offset,e+12);offset+=frames[i].length;});
    fs.writeFileSync(path.join(out,`home-${name.toLowerCase()}.ico`),Buffer.concat([head,...frames]));
  }
  const background=Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="800" height="300"><rect width="800" height="300" rx="22" fill="#11151e"/><text x="36" y="42" fill="#E8EFFA" font-family="Segoe UI, sans-serif" font-size="21">HOME / NETBIRD</text><text x="36" y="272" fill="#9BAAC1" font-family="Segoe UI, sans-serif" font-size="15">AURORA</text><text x="570" y="76" fill="#9BAAC1" font-family="Segoe UI, sans-serif" font-size="15">TRAY 16 / 24 / 32</text></svg>`);
  const composites=[{input:await sharp(path.join(out,'home-connected.svg')).resize(210,210).png().toBuffer(),left:40,top:48}];
  for(const [i,name] of ['connected','degraded','disconnected'].entries()){
    composites.push({input:await sharp(path.join(out,`home-${name}.svg`)).resize(90,90).png().toBuffer(),left:280+i*92,top:108});
  }
  for(const [i,n] of [16,24,32].entries())composites.push({input:await sharp(path.join(out,'home-connected.svg')).resize(n,n).png().toBuffer(),left:590+i*52,top:120});
  await sharp(background).composite(composites).png().toFile(path.join(out,'home-preview.png'));
  console.log('Created four SVG/PNG/multiresolution ICO states and preview.');
})().catch(e=>{console.error(e);process.exit(1)});
