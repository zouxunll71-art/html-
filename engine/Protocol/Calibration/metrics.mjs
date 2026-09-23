import { PNG } from 'pngjs';
export const decode = bytes => PNG.sync.read(bytes);
export const encode = image => PNG.sync.write(image);
export function compare(a, b, regions = []) {
  if (a.width !== b.width || a.height !== b.height) throw Error(`Pixel dimensions differ: reference ${a.width}x${a.height}, actual ${b.width}x${b.height}`);
  const measure = ({x=0,y=0,width=a.width,height=a.height}) => {
    if (![x,y,width,height].every(Number.isInteger) || x<0 || y<0 || width<1 || height<1 || x+width>a.width || y+height>a.height) throw Error('Invalid region bounds');
    let changed=0, error=0, maxChannel=0;
    for(let j=y;j<y+height;j++) for(let i=x;i<x+width;i++) {
      let pixel=0;
      for(let k=0;k<4;k++){ const delta=Math.abs(a.data[(j*a.width+i)*4+k]-b.data[(j*a.width+i)*4+k]);pixel+=delta;maxChannel=Math.max(maxChannel,delta); }
      if(pixel) changed++;
      error+=pixel;
    }
    return {changed,error,maxChannel,pixels:width*height,ratio:changed/(width*height)};
  };
  return {full:measure({}),regions:Object.fromEntries(regions.map(r=>[r.id,measure(r)]))};
}
export function improves(next, previous) {
  return next.full.error < previous.full.error && Object.keys(previous.regions).every(id => next.regions[id].error <= previous.regions[id].error);
}
export function visuals(a,b) {
  compare(a,b);
  const diff=new PNG({width:a.width,height:a.height});
  const overlay=new PNG({width:a.width,height:a.height});
  const side=new PNG({width:a.width*2,height:a.height});
  for(let y=0;y<a.height;y++)for(let x=0;x<a.width;x++) {
    const p=(y*a.width+x)*4;
    for(let k=0;k<4;k++){
      diff.data[p+k]=k===3?255:Math.max(Math.abs(a.data[p+k]-b.data[p+k]),Math.abs(a.data[p+3]-b.data[p+3]));
      overlay.data[p+k]=k===3?255:Math.round((a.data[p+k]+b.data[p+k])/2);
      side.data[(y*a.width*2+x)*4+k]=a.data[p+k];
      side.data[(y*a.width*2+x+a.width)*4+k]=b.data[p+k];
    }
  }
  return {'difference.png':encode(diff),'overlay.png':encode(overlay),'side-by-side.png':encode(side)};
}
