export const defaults = Object.freeze({ workingAngle: 105, fadeAngle: 18, perspective: .8, frost: .55, shade: .35, response: .72 });
export const presets = Object.freeze({
  Clear: { perspective: .8, frost: 0, shade: .12 },
  Frost: { perspective: .8, frost: .55, shade: .35 },
  Soft: { perspective: .55, frost: .9, shade: .15 }
});
export function clamp(value, lo, hi, fallback = lo) { return Number.isFinite(value) ? Math.min(hi, Math.max(lo, value)) : fallback; }
export function progress(angle, t = defaults) { return clamp((t.workingAngle-angle)/(t.workingAngle-t.fadeAngle), 0, 1); }
export function smooth(current, target, dt, response = .72) {
  return current + (target-current) * (1-Math.exp(-(12+clamp(response,0,1)*34)*clamp(dt,0,.1)));
}
export function sourceUV(u,v,angle,workingAngle=105,aspect=1.6,eyeHeight=2.3,eyeDistance=2.6) {
  if (![u,v,angle,workingAngle,aspect,eyeHeight,eyeDistance].every(Number.isFinite) || aspect<=0) return null;
  const a=angle*Math.PI/180, w=workingAngle*Math.PI/180;
  const point=[(u-.5)*aspect, (1-v)*Math.sin(a), (1-v)*Math.cos(a)];
  const denominator=Math.cos(w)*(point[1]-eyeHeight)-Math.sin(w)*(point[2]-eyeDistance);
  if (Math.abs(denominator)<.00001) return null;
  const ray=-(Math.cos(w)*eyeHeight-Math.sin(w)*eyeDistance)/denominator;
  if(ray<=0) return null;
  const reference=[ray*point[0],eyeHeight+ray*(point[1]-eyeHeight),eyeDistance+ray*(point[2]-eyeDistance)];
  return [reference[0]/aspect+.5, 1-reference[1]*Math.sin(w)-reference[2]*Math.cos(w)];
}
