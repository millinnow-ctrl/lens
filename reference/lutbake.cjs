// Stage 2a.1 — bake each stock's COLOR CORE to a 33^3 LUT from the reference
// engine, then PROVE the LUT reproduces the color core on real photos (Node,
// no Mac). The .lut files are what CIColorCube applies in Swift = zero drift.
const { createCanvas, loadImage } = require('@napi-rs/canvas')
const { writeFileSync, mkdirSync } = require('fs')
const path = require('path')
global.HTMLVideoElement=class{};global.HTMLImageElement=class{};global.HTMLCanvasElement=class{}
global.document={createElement:(t)=>{if(t!=='canvas')throw new Error(t);return createCanvas(1,1)}}
const SP=__dirname
const { renderStyled } = require(path.join(SP,'out','engine.js'))
const { CAMERA_STYLES } = require(path.join(SP,'out','styles.js'))
const DIM=33, N=DIM-1
const STOCKS = CAMERA_STYLES.filter(s=>s.id!=='pro-body')

function colorCore(st){
  const c=JSON.parse(JSON.stringify(st)), ch=c.character
  for(const k of ['blur','halation','grainAmp','grainSize','grainChroma','bloom','vignette','dither','clarity']) ch[k]=0
  if(ch.optics) for(const k of Object.keys(ch.optics)) ch.optics[k]=0
  if(ch.lens){ch.lens.dof=0;ch.lens.lightHalation=0;ch.lens.shadowDenoise=0}
  ch.scanlines=0;ch.fringe=0;if(ch.lens){ch.lens.skinGlow=0;ch.lens.flashStrength=0;ch.lens.flashSpecular=0}ch.glow=0;ch.subsurface=0;ch.polaroidFrame=false
  return c
}
function cubeImage(){
  const w=DIM*DIM,h=DIM,cv=createCanvas(w,h),x=cv.getContext('2d'),im=x.createImageData(w,h)
  for(let b=0;b<DIM;b++)for(let g=0;g<DIM;g++)for(let r=0;r<DIM;r++){
    const o=(g*w + b*DIM + r)*4
    im.data[o]=Math.round(r/N*255);im.data[o+1]=Math.round(g/N*255);im.data[o+2]=Math.round(b/N*255);im.data[o+3]=255
  }
  x.putImageData(im,0,0);return cv
}
function bake(st){
  const out=renderStyled(cubeImage(),colorCore(st),{...st.defaults,grain:0},{scene:null,maxSize:4096,watermark:false,frame:false})
  const d=out.getContext('2d').getImageData(0,0,DIM*DIM,DIM).data
  const f=new Float32Array(DIM*DIM*DIM*4);let fi=0
  for(let b=0;b<DIM;b++)for(let g=0;g<DIM;g++)for(let r=0;r<DIM;r++){
    const o=(g*(DIM*DIM)+b*DIM+r)*4
    f[fi++]=d[o]/255;f[fi++]=d[o+1]/255;f[fi++]=d[o+2]/255;f[fi++]=1
  }
  return f
}
function applyLUT(photo,f){
  const w=photo.width,h=photo.height,cv=createCanvas(w,h),x=cv.getContext('2d')
  x.drawImage(photo,0,0);const im=x.getImageData(0,0,w,h),d=im.data
  const s=(ri,gi,bi,ch)=>f[((bi*DIM+gi)*DIM+ri)*4+ch]
  for(let i=0;i<d.length;i+=4){
    const rf=d[i]/255*N,gf=d[i+1]/255*N,bf=d[i+2]/255*N
    const r0=Math.floor(rf),g0=Math.floor(gf),b0=Math.floor(bf),r1=Math.min(r0+1,N),g1=Math.min(g0+1,N),b1=Math.min(b0+1,N)
    const dr=rf-r0,dg=gf-g0,db=bf-b0
    for(let ch=0;ch<3;ch++){
      const c00=s(r0,g0,b0,ch)*(1-dr)+s(r1,g0,b0,ch)*dr,c10=s(r0,g1,b0,ch)*(1-dr)+s(r1,g1,b0,ch)*dr
      const c01=s(r0,g0,b1,ch)*(1-dr)+s(r1,g0,b1,ch)*dr,c11=s(r0,g1,b1,ch)*(1-dr)+s(r1,g1,b1,ch)*dr
      const c0=c00*(1-dg)+c10*dg,c1=c01*(1-dg)+c11*dg
      d[i+ch]=Math.max(0,Math.min(255,(c0*(1-db)+c1*db)*255))
    }
  }
  x.putImageData(im,0,0);return cv
}
async function main(){
  mkdirSync('/home/user/lens/LensMoodApp/Resources/luts',{recursive:true})
  const outDir=path.join('/home/user/lens','LensMoodApp','Resources','luts')
  const photos={};for(const p of ['golden','friends','brunch'])photos[p]=await loadImage(path.join(SP,'photos',`sample-${p}.jpg`))
  let worst=0,worstName='',results=[]
  for(const st of STOCKS){
    const f=bake(st)
    writeFileSync(path.join(outDir,`${st.id}.lut`),Buffer.from(f.buffer))
    let stMax=0
    for(const p of Object.keys(photos)){
      const src=photos[p]
      const ref=renderStyled(src,colorCore(st),{...st.defaults,grain:0},{scene:null,maxSize:600,watermark:false,frame:false})
      const small=createCanvas(ref.width,ref.height);small.getContext('2d').drawImage(src,0,0,ref.width,ref.height)
      const lo=applyLUT(small,f)
      const rd=ref.getContext('2d').getImageData(0,0,ref.width,ref.height).data
      const ld=lo.getContext('2d').getImageData(0,0,ref.width,ref.height).data
      let sum=0,n=0
      for(let i=0;i<rd.length;i+=4){sum+=Math.abs(rd[i]-ld[i])+Math.abs(rd[i+1]-ld[i+1])+Math.abs(rd[i+2]-ld[i+2]);n+=3}
      const mae=sum/n; stMax=Math.max(stMax,mae)
    }
    results.push([st.id,stMax.toFixed(3)])
    if(stMax>worst){worst=stMax;worstName=st.id}
  }
  for(const[id,m]of results)console.log('  '+id.padEnd(16),m)
  console.log(`\nWORST color-core LUT error: ${worst.toFixed(3)}/255 (${worstName})`)
  console.log(worst<1.5?'PASS — LUT reproduces the color core (zero perceptible drift)':'INVESTIGATE — a non-pixel color op leaked')
}
main().catch(e=>{console.error('FAIL:',e.message,e.stack.split('\n').slice(0,3).join('\n'));process.exit(1)})
