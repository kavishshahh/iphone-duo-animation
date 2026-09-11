import { createFoldDemo } from './demo.mjs';
const angle=document.querySelector('#angle');
const output=document.querySelector('#angle-value');
const play=document.querySelector('#play');
const icon=document.querySelector('#play-icon');
const effect=document.querySelector('#effect');
let demo;
function showError(message){
  document.querySelector('#demo-loading').hidden=true;
  document.querySelector('#fold-canvas').hidden=true;
  document.querySelector('#demo-fallback').hidden=false;
  document.querySelector('#demo-error').textContent=message;
  for(const control of [angle,play,effect])control.disabled=true;
}
try {
  demo=await createFoldDemo(document.querySelector('#fold-canvas'),{
    onAngle:value=>{angle.value=value;output.textContent=value;angle.setAttribute('aria-valuetext',value+' degrees');},
    onPlayback:playing=>{
      play.setAttribute('aria-pressed',String(playing));play.setAttribute('aria-label',playing?'Pause folding animation':'Play folding animation');
      icon.setAttribute('d',playing?'M5 4h3v12H5zM12 4h3v12h-3z':'m7 4 9 6-9 6Z');
    },
    onError:showError
  });
  document.querySelector('#demo-loading').hidden=true;
  for(const control of [angle,play,effect])control.disabled=false;
  angle.addEventListener('input',()=>demo.setAngle(Number(angle.value)));
  play.addEventListener('click',()=>demo.setPlaying(!demo.getState().playing));
  effect.addEventListener('change',()=>demo.setEffect(effect.checked));
  document.querySelectorAll('[data-view]').forEach(button=>button.addEventListener('click',()=>{
    demo.setView(button.dataset.view);
    document.querySelectorAll('[data-view]').forEach(item=>item.setAttribute('aria-pressed',String(item===button)));
  }));
} catch(error) {
  console.error('Still preview:',error);
  showError('This browser could not start the interactive preview. You can still download the Mac prototype.');
}
window.addEventListener('pagehide',()=>demo?.dispose(),{once:true});
