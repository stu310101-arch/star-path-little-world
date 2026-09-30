// Render the production controller and GLBs in an isolated Godot WebGL stage.
const {chromium}=require('playwright');
const fs=require('node:fs');const path=require('node:path');
const ROOT=path.resolve(__dirname,'..');const OUT=path.join(ROOT,'deliverables/frontflip-refined/studio');
const url='http://127.0.0.1:8766/index.html?qa=1';
(async()=>{
 fs.mkdirSync(OUT,{recursive:true});
 const browser=await chromium.launch({channel:'chrome',headless:true,args:['--enable-unsafe-swiftshader']});
 const page=await browser.newPage({viewport:{width:1100,height:900}});
 const errors=[];const reports=[];
 page.on('pageerror',e=>errors.push(String(e)));
 page.on('console',m=>{if(m.type()==='error'&&!m.text().startsWith('Failed to load resource:'))errors.push(m.text());});
 page.on('response',r=>{if(r.status()>=400&&!r.url().endsWith('/favicon.ico'))errors.push(r.status()+' '+r.url());});
 const state=()=>page.evaluate(()=>window.frontflipQA.state);
 const command=async(action,value)=>{
  const id=await page.evaluate(([a,v])=>window.frontflipQA[a](v),[action,value]);
  await page.waitForFunction(i=>window.frontflipQA?.state.ready&&window.frontflipQA.state.rendered_command>=i&&window.frontflipQA.state.pending_steps===0,id,{timeout:60000});
  const s=await state();if(s.errors.length)throw Error(JSON.stringify(s.errors));return s;
 };
 try{
  await page.goto(url,{timeout:120000});
  await page.waitForFunction(()=>window.frontflipQA?.state.ready,null,{timeout:240000});
  for(const sequence of ['standing','moving']){
   const base=path.join(OUT,sequence);for(const view of ['front','side'])fs.mkdirSync(path.join(base,view),{recursive:true});
   let s=await command('reset',sequence);await command('view','front');
   const frames=[],trace=[],seen=new Set(),counts={front:0,side:0};
   const phaseFor=s=>{
    const phases=[];
    if(s.tick===0)phases.push('01-before-jump');
    if(s.state==='anticipation'&&s.tick>=27)phases.push('02-anticipation');
    if(s.state==='airborne'){
     phases.push('03-takeoff');
     if(s.flip_progress>=.25)phases.push('04-tuck');
     if(s.flip_progress>=.50)phases.push('05-inverted');
     if(s.flip_progress>=.83)phases.push('06-opening');
    }
    if(s.state==='landing'){
     phases.push('07-contact');
     if(s.landing_clock>=.20)phases.push('08-settle-020');
     if(s.landing_clock>=.60)phases.push('09-settle-060');
     if(s.landing_clock>=1.00)phases.push('10-settle-100');
    }
    if(s.tick>24&&s.state==='grounded'&&s.landing_count===1)phases.push('11-recovered');
    const phase=phases.find(p=>!seen.has(p))||'';if(phase)seen.add(phase);return phase;
   };
   const capture=async(view,phase)=>{
    const row=await state();const file=view+'/frame_'+String(counts[view]++).padStart(4,'0')+'.png';
    await page.locator('#canvas').screenshot({path:path.join(base,file),timeout:60000});
    const after=await state();if(after.tick!==row.tick||after.landing_clock!==row.landing_clock)throw Error('Pose moved during capture');
    frames.push({...row,file,view,phase,width:1100,height:900});
   };
   for(let tick=0;tick<=s.total_ticks;tick+=2){
    if(tick>0)s=await command('step',2);else s=await state();
    trace.push(s);const phase=phaseFor(s);
    await capture('front',phase);
    if(phase){await command('view','side');await capture('side',phase);await command('view','front');}
    if(tick%40===0)console.log('WEB_CAPTURE',sequence,tick,s.clip,s.landing_clock.toFixed(2));
   }
   s=await state();const passed=s.passed&&errors.length===0&&seen.has('11-recovered');
   const report={sequence,passed,simulation_fps:60,capture_fps:30,frames,trace,final_state:s,frame_counts:counts,errors,method:'Godot WebGL, exact production script and GLBs; explicit physical stepping, real rendered canvas, frozen screenshot barrier'};
   fs.writeFileSync(path.join(base,'capture.json'),JSON.stringify(report,null,2));
   reports.push({sequence,passed,manifest:sequence+'/capture.json',frame_counts:counts,full_landing_settle:s.maximum_landing_clock>=1.20,walking_recovery_during_cloth_settle:s.walking_recovery_seen});
   if(!passed)throw Error('Capture validation failed '+JSON.stringify(report.final_state));
  }
  fs.writeFileSync(path.join(OUT,'capture.json'),JSON.stringify({passed:true,url,sequences:reports,errors,renderer:'Godot WebGL via Chrome SwiftShader',native_driver_unavailable:true},null,2));
  console.log('REFINED_WEB_CAPTURE_PASSED',JSON.stringify(reports));
 }catch(e){fs.writeFileSync(path.join(OUT,'capture-error.json'),JSON.stringify({error:String(e),errors,reports},null,2));throw e;}
 finally{await browser.close();}
})().catch(e=>{console.error(e);process.exit(1);});
