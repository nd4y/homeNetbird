// Compile repo-native Aurora SVGs with the exact official Windows badge masks.
const fs=require('fs'),path=require('path');
const sharp=require('sharp');
const dir=path.join(__dirname,'icons');
const base=fs.readFileSync(path.join(dir,'home-base.svg'),'utf8')
  .replace('viewBox="0 0 32 32"','viewBox="0 0 256 256"')
  .replace('translate(.85 4.5)','translate(0 30.56) scale(8.479)');
const states={connected:'connected-dark',connecting:'connecting-dark',disconnected:'disconnected',degraded:'error-dark',unavailable:'error-dark','update-connected':'update-connected-dark','update-disconnected':'update-disconnected-dark'};
function badge(r,g,b){return (r>220&&g>220&&b>220)||(g>150&&g>r*1.3&&g>b*1.05)||(b>160&&g>130&&r<100)||(r>200&&b>70&&g<110);}
function dib(rgba,n){
  const stride=Math.ceil(n/32)*4,b=Buffer.alloc(40+n*n*4+stride*n);
  b.writeUInt32LE(40,0);b.writeInt32LE(n,4);b.writeInt32LE(n*2,8);b.writeUInt16LE(1,12);b.writeUInt16LE(32,14);b.writeUInt32LE(n*n*4,20);
  for(let y=0;y<n;y++)for(let x=0;x<n;x++){
    const s=(y*n+x)*4,d=40+((n-1-y)*n+x)*4;
    b[d]=rgba[s+2];b[d+1]=rgba[s+1];b[d+2]=rgba[s];b[d+3]=rgba[s+3];
    if(!rgba[s+3])b[40+n*n*4+(n-1-y)*stride+(x>>3)]|=0x80>>(x%8);
  }return b;
}
(async()=>{
  for(const [state,template] of Object.entries(states)){
    const png=fs.readFileSync(path.join(dir,'templates',template+'.png'));
    const {data,info}=await sharp(png).ensureAlpha().raw().toBuffer({resolveWithObject:true});
    if(info.width!==256||info.height!==256)throw Error('Unexpected official icon size');
    // Trace each badge row into SVG rectangles; badge colors/alpha are upstream.
    const rows=[];
    for(let y=0;y<256;y++)for(let x=0;x<256;){
      const i=(y*256+x)*4,r=data[i],g=data[i+1],b=data[i+2],a=data[i+3];
      if(!a||!badge(r,g,b)){x++;continue;}
      let end=x+1;
      while(end<256){const j=(y*256+end)*4;if(data[j]!==r||data[j+1]!==g||data[j+2]!==b||data[j+3]!==a)break;end++;}
      rows.push(`<path d="M${x} ${y}h${end-x}v1H${x}z" fill="rgb(${r},${g},${b})" opacity="${a/255}"/>`);x=end;
    }
    const defs=base.match(/<defs>([\s\S]*?)<\/defs>/)[1];
    const bird=base.match(/<g transform=[\s\S]*?<\/g>/)[0];
    const svg=`<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256"><defs>${defs}<filter id="alpha"><feColorMatrix type="matrix" values="0 0 0 0 1 0 0 0 0 1 0 0 0 0 1 0 0 0 1 0"/></filter><mask id="silhouette" maskUnits="userSpaceOnUse" x="0" y="0" width="256" height="256"><image href="data:image/png;base64,${png.toString('base64')}" width="256" height="256" filter="url(#alpha)"/></mask></defs><g mask="url(#silhouette)">${bird}</g>${rows.join('')}</svg>`;
    fs.writeFileSync(path.join(dir,`home-${state}.svg`),svg);
    await sharp(Buffer.from(svg)).png().toFile(path.join(dir,`home-${state}.png`));
    const sizes=[16,20,24,32,48,64],frames=[];
    for(const n of sizes)frames.push(dib(await sharp(Buffer.from(svg)).resize(n,n).ensureAlpha().raw().toBuffer(),n));
    const header=Buffer.alloc(6+16*sizes.length);header.writeUInt16LE(1,2);header.writeUInt16LE(sizes.length,4);let offset=header.length;
    sizes.forEach((n,i)=>{const e=6+16*i;header[e]=n;header[e+1]=n;header.writeUInt16LE(1,e+4);header.writeUInt16LE(32,e+6);header.writeUInt32LE(frames[i].length,e+8);header.writeUInt32LE(offset,e+12);offset+=frames[i].length;});
    fs.writeFileSync(path.join(dir,`home-${state}.ico`),Buffer.concat([header,...frames]));
  }
  const labels=['connected','connecting','disconnected','unavailable','update-connected'];
  const background=Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="800" height="210"><rect width="800" height="210" rx="16" fill="#11151e"/>${labels.map((s,i)=>`<text x="${20+i*158}" y="184" fill="#D5DFEF" font-family="Segoe UI" font-size="13">${s}</text>`).join('')}</svg>`);
  const images=[];for(let i=0;i<labels.length;i++)images.push({input:await sharp(path.join(dir,`home-${labels[i]}.png`)).resize(120,120).png().toBuffer(),left:20+158*i,top:26});
  await sharp(background).composite(images).png().toFile(path.join(dir,'home-status-preview.png'));
  console.log('Built official-style badges for 7 states, each with 6 ICO sizes. Original home-preview.png retained.');
})().catch(e=>{console.error(e);process.exit(1)});
