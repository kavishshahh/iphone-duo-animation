import * as THREE from './vendor/three.module.min.js';
import { defaults, presets, clamp, smooth } from './fold-math.mjs';

const vertexShader = `
varying vec2 screenUV;
void main() {
  screenUV = vec2(uv.x, 1.0-uv.y);
  gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0);
}`;
const fragmentShader = `
uniform sampler2D picture;
uniform float angle;
uniform float workingAngle;
uniform float perspective;
uniform float frost;
uniform float shade;
uniform float effect;
varying vec2 screenUV;
void main() {
  vec2 uv=screenUV;
  float degrees=clamp(angle,0.0,workingAngle);
  float p=clamp((workingAngle-degrees)/(workingAngle-18.0),0.0,1.0)*effect;
  float a=radians(mix(workingAngle,degrees,effect)), w=radians(workingAngle);
  vec3 eye=vec3(0.0,2.3,2.6);
  vec3 point=vec3((uv.x-.5)*1.6,(1.0-uv.y)*sin(a),(1.0-uv.y)*cos(a));
  vec3 normal=vec3(0.0,cos(w),-sin(w));
  float den=dot(normal,point-eye);
  float ray=abs(den)>.00001 ? -dot(normal,eye)/den : -1.0;
  vec3 ref=eye+ray*(point-eye);
  vec2 projected=vec2(ref.x/1.6+.5,1.0-dot(ref,vec3(0.0,sin(w),cos(w))));
  float easing=smoothstep(0.0,7.0,workingAngle-degrees)*effect;
  vec2 source=mix(uv,projected,perspective*easing);
  float inside=step(0.0,source.x)*step(source.x,1.0)*step(0.0,source.y)*step(source.y,1.0)*step(0.0,ray);
  float edgeDistance=min(min(source.x,1.0-source.x),min(source.y,1.0-source.y));
  float feather=mix(1.0,smoothstep(0.0,.009,edgeDistance),easing);
  float blur=frost*smoothstep(.05,.9,p)*(1.5+4.8*(1.0-uv.y));
  vec3 col=textureLod(picture,vec2(source.x,1.0-source.y),blur).rgb;
  col*=1.0-shade*p*(.25+.60*pow(1.0-uv.y,2.0));
  col=mix(col,vec3(.64,.76,.94),frost*p*.035);
  float fade=mix(1.0,smoothstep(18.0,30.0,degrees),effect);
  col*=inside*feather*fade;
  // Rounded display mask.
  vec2 q=abs(uv-.5)-vec2(.483,.474);
  if(length(max(q,0.0))+min(max(q.x,q.y),0.0)>.018) discard;
  gl_FragColor=vec4(col,1.0);
  #include <tonemapping_fragment>
  #include <colorspace_fragment>
}`;

function roundedShape(width,height,radius) {
  const x=-width/2,y=-height/2,r=radius,s=new THREE.Shape();
  s.moveTo(x+r,y);s.lineTo(x+width-r,y);s.quadraticCurveTo(x+width,y,x+width,y+r);
  s.lineTo(x+width,y+height-r);s.quadraticCurveTo(x+width,y+height,x+width-r,y+height);
  s.lineTo(x+r,y+height);s.quadraticCurveTo(x,y+height,x,y+height-r);
  s.lineTo(x,y+r);s.quadraticCurveTo(x,y,x+r,y);return s;
}
function plate(width,height,depth,radius,material) {
  const geometry=new THREE.ExtrudeGeometry(roundedShape(width,height,radius),{
    depth,bevelEnabled:true,bevelThickness:.008,bevelSize:.008,bevelSegments:2,steps:1,curveSegments:12
  });
  geometry.translate(0,0,-depth/2);
  return new THREE.Mesh(geometry,material);
}
function createLaptop(screenMaterial) {
  const group=new THREE.Group();
  const aluminum=new THREE.MeshStandardMaterial({color:0xb8bcc3,metalness:.55,roughness:.34});
  const dark=new THREE.MeshStandardMaterial({color:0x090b10,metalness:.12,roughness:.6});
  const deck=plate(3.4,2.14,.07,.09,aluminum);
  deck.rotation.x=-Math.PI/2;deck.position.set(0,0,.48);deck.castShadow=true;deck.receiveShadow=true;group.add(deck);
  const keyboard=new THREE.Mesh(new THREE.BoxGeometry(2.78,.012,1.02),dark);
  keyboard.position.set(0,.047,.05);group.add(keyboard);
  const keyGeometry=new THREE.BoxGeometry(.169,.016,.126);
  const keyMaterial=new THREE.MeshStandardMaterial({color:0x24262d,roughness:.67,metalness:.07});
  const keys=new THREE.InstancedMesh(keyGeometry,keyMaterial,70);
  const matrix=new THREE.Matrix4();
  for(let row=0;row<5;row++) for(let col=0;col<14;col++) {
    matrix.makeTranslation((col-6.5)*.195,.061,-.355+row*.171);
    keys.setMatrixAt(row*14+col,matrix);
  }
  keys.instanceMatrix.needsUpdate=true;group.add(keys);
  const space=new THREE.Mesh(new THREE.BoxGeometry(1.14,.016,.12),keyMaterial);
  space.position.set(0,.061,.484);group.add(space);
  const trackpad=plate(1.25,.62,.002,.025,new THREE.MeshStandardMaterial({color:0xa9adb5,metalness:.35,roughness:.44}));
  trackpad.rotation.x=-Math.PI/2;trackpad.position.set(0,.043,1.09);group.add(trackpad);
  const notch=new THREE.Mesh(new THREE.BoxGeometry(.48,.009,.018),new THREE.MeshStandardMaterial({color:0x6d7078}));
  notch.position.set(0,.048,1.552);group.add(notch);
  const hinge=new THREE.Mesh(new THREE.CylinderGeometry(.043,.043,2.72,16),dark);
  hinge.rotation.z=Math.PI/2;hinge.position.set(0,.045,-.545);group.add(hinge);
  const lid=new THREE.Group();lid.position.set(0,.075,-.545);group.add(lid);
  const housing=plate(3.36,2.13,.04,.09,aluminum);
  housing.position.y=1.075;housing.castShadow=true;lid.add(housing);
  const bezel=new THREE.Mesh(new THREE.ShapeGeometry(roundedShape(3.28,2.045,.075)),dark);
  bezel.position.set(0,1.075,.031);lid.add(bezel);
  const screen=new THREE.Mesh(new THREE.PlaneGeometry(3.14,1.9625),screenMaterial);
  screen.position.set(0,1.075,.034);lid.add(screen);
  const cameraDot=new THREE.Mesh(new THREE.CircleGeometry(.012,12),new THREE.MeshBasicMaterial({color:0x1c2330}));
  cameraDot.position.set(0,2.091,.037);lid.add(cameraDot);
  return {group,lid};
}
async function desktopTexture() {
  const image=new Image();image.src='./assets/wallpaper.png';await image.decode();
  const canvas=document.createElement('canvas');canvas.width=1600;canvas.height=1000;
  const ctx=canvas.getContext('2d');
  if(!ctx) throw new Error('The desktop preview could not start.');
  ctx.drawImage(image,0,0,1600,1000);
  ctx.fillStyle='rgba(255,255,255,.90)';ctx.textAlign='center';
  ctx.font='500 28px -apple-system, BlinkMacSystemFont, sans-serif';
  ctx.fillText('A moment of Still',800,139);
  ctx.font='600 142px -apple-system, BlinkMacSystemFont, sans-serif';
  ctx.fillText('9:41',800,285);
  const texture=new THREE.CanvasTexture(canvas);
  texture.colorSpace=THREE.SRGBColorSpace;
  texture.minFilter=THREE.LinearMipmapLinearFilter;
  texture.magFilter=THREE.LinearFilter;
  texture.generateMipmaps=true;
  return texture;
}

export async function createFoldDemo(canvas,{onAngle=()=>{},onPlayback=()=>{},onError=()=>{}}={}) {
  const renderer=new THREE.WebGLRenderer({canvas,alpha:true,antialias:true,powerPreference:'low-power'});
  renderer.setPixelRatio(Math.min(window.devicePixelRatio||1,1.75));
  renderer.outputColorSpace=THREE.SRGBColorSpace;
  renderer.toneMapping=THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure=1.13;
  renderer.shadowMap.enabled=true;renderer.shadowMap.type=THREE.PCFSoftShadowMap;
  renderer.setClearColor(0x000000,0);
  let failed=false;
  renderer.debug.onShaderError=()=>{ failed=true;onError('The 3D preview could not render in this browser. The Mac source is still available below.'); };
  const scene=new THREE.Scene();
  scene.add(new THREE.HemisphereLight(0xffffff,0x757d99,2.3));
  const key=new THREE.DirectionalLight(0xffffff,4.0);key.position.set(-3,6,4);key.castShadow=true;
  key.shadow.mapSize.set(1024,1024);key.shadow.camera.left=-4;key.shadow.camera.right=4;
  key.shadow.camera.top=4;key.shadow.camera.bottom=-4;key.shadow.normalBias=.02;scene.add(key);
  const fill=new THREE.DirectionalLight(0xcbdcff,2.6);fill.position.set(4,3,-2);scene.add(fill);
  const floor=new THREE.Mesh(new THREE.PlaneGeometry(30,30),new THREE.ShadowMaterial({opacity:.13}));
  floor.rotation.x=-Math.PI/2;floor.position.y=-.052;floor.receiveShadow=true;scene.add(floor);
  const texture=await desktopTexture();
  const uniforms={picture:{value:texture},angle:{value:105},workingAngle:{value:105},perspective:{value:.8},
    frost:{value:.55},shade:{value:.35},effect:{value:1}};
  const material=new THREE.ShaderMaterial({uniforms,vertexShader,fragmentShader,side:THREE.FrontSide});
  const laptop=createLaptop(material);scene.add(laptop.group);
  const camera=new THREE.PerspectiveCamera(32,1,.1,60);
  const defaultCamera=new THREE.Vector3(3.1,2.75,4.8);
  const frontCamera=new THREE.Vector3(0,4.65,4.8);
  camera.position.copy(defaultCamera);camera.lookAt(0,.76,.25);
  let targetAngle=105,currentAngle=105,playing=false,phase=0,last=0,frame=0,visible=true,disposed=false;
  let selectedStyle='Frost',effect=true,view='desk',lastReported=-1;
  const reduced=window.matchMedia('(prefers-reduced-motion: reduce)');
  const resize=()=>{
    const box=canvas.parentElement.getBoundingClientRect();
    renderer.setSize(Math.max(1,box.width),Math.max(1,box.height),false);
    camera.aspect=box.width/Math.max(1,box.height);
    // Keep the full laptop in view on a portrait screen.
    camera.fov=box.width<600 ? 44 : 32;
    camera.updateProjectionMatrix();requestDraw();
  };
  function tick(time) {
    frame=0;if(disposed||failed||!visible||document.hidden)return;
    const dt=last?Math.min((time-last)/1000,.1):1/60;last=time;
    if(playing) {phase+=dt;targetAngle=105-75*(.5-.5*Math.cos(phase/5.8*Math.PI*2));}
    currentAngle=reduced.matches?targetAngle:smooth(currentAngle,targetAngle,dt);
    laptop.lid.rotation.x=THREE.MathUtils.degToRad(90-currentAngle);
    uniforms.angle.value=currentAngle;
    renderer.render(scene,camera);
    const rounded=Math.round(currentAngle);
    if(rounded!==lastReported){lastReported=rounded;onAngle(rounded);}
    if(playing||Math.abs(targetAngle-currentAngle)>.015)requestDraw();
  }
  function requestDraw() {if(!frame&&!disposed&&visible&&!document.hidden)frame=requestAnimationFrame(tick);}
  function setPlaying(value) {
    playing=Boolean(value);
    if(playing) phase=Math.acos(clamp(1-2*(105-currentAngle)/75,-1,1))/Math.PI/2*5.8;
    onPlayback(playing);last=0;requestDraw();
  }
  function setAngle(value) {
    setPlaying(false);targetAngle=clamp(Number(value),18,105,105);requestDraw();
  }
  function setPreset(value) {
    if(!presets[value])return;
    selectedStyle=value;
    for(const [key,value] of Object.entries(presets[value]))uniforms[key].value=value;
    requestDraw();
  }
  function setEffect(value) {effect=Boolean(value);uniforms.effect.value=effect?1:0;requestDraw();}
  function setView(value) {
    view=value==='front'?'front':'desk';
    camera.position.copy(view==='front'?frontCamera:defaultCamera);camera.lookAt(0,.76,.25);requestDraw();
  }
  const observer=new ResizeObserver(resize);observer.observe(canvas.parentElement);
  const intersection=new IntersectionObserver(([entry])=>{visible=entry.isIntersecting;last=0;if(visible)requestDraw();},{threshold:0});
  intersection.observe(canvas);
  const visibility=()=>{last=0;if(!document.hidden)requestDraw();};
  document.addEventListener('visibilitychange',visibility);
  const reduce=()=>{if(reduced.matches)setPlaying(false);requestDraw();};reduced.addEventListener('change',reduce);
  canvas.addEventListener('webglcontextlost',event=>{
    event.preventDefault();setPlaying(false);failed=true;
    onError('The 3D preview was interrupted. Reload this page to try again.');
  });
  let drag=null;
  canvas.addEventListener('pointerdown',event=>{
    if(event.pointerType==='mouse'&&event.button!==0)return;
    drag={y:event.clientY,x:event.clientX,angle:currentAngle};setPlaying(false);canvas.setPointerCapture(event.pointerId);
  });
  canvas.addEventListener('pointermove',event=>{
    if(!drag)return;
    setAngle(drag.angle+(drag.y-event.clientY)*.28+(event.clientX-drag.x)*.09);
  });
  const endDrag=()=>{drag=null;};
  canvas.addEventListener('pointerup',endDrag);canvas.addEventListener('pointercancel',endDrag);
  resize();requestDraw();
  return {
    setAngle,setPlaying,setPreset,setEffect,setView,
    getState:()=>({angle:Math.round(currentAngle),preset:selectedStyle,effect,view,playing}),
    dispose() {
      disposed=true;cancelAnimationFrame(frame);observer.disconnect();intersection.disconnect();
      document.removeEventListener('visibilitychange',visibility);reduced.removeEventListener('change',reduce);
      scene.traverse(object=>{object.geometry?.dispose();if(object.material)for(const m of [object.material].flat())m.dispose();});
      texture.dispose();renderer.dispose();
    }
  };
}
