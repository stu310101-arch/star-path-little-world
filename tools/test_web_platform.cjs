const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const source=fs.readFileSync(__dirname+'/web_platform.js','utf8');
function choose(url,phone,etc2){
  let destination=null;
  const gl={COMPRESSED_TEXTURE_FORMATS:1,getParameter:()=>etc2?[0x9278]:[],getExtension:()=>null};
  const context={URL,window:{},navigator:{userAgent:phone?'iPhone':'Desktop',platform:'',maxTouchPoints:phone?1:0},
    location:{href:url,replace:to=>{destination=to;}},document:{createElement:()=>({getContext:()=>gl})},setTimeout};
  vm.runInNewContext(source,context);return {destination,redirecting:context.window.LittleWorldRedirecting};
}
test('phone with ETC2 selects mobile while preserving query and fragment',()=>{
  assert.deepEqual(choose('https://example.com/game/?performance#map',true,true),{destination:'https://example.com/game/mobile/index.html?performance#map',redirecting:true});
});
test('phone without ETC2 never selects incompatible textures',()=>{
  assert.equal(choose('https://example.com/game/',true,false).redirecting,false);
  assert.equal(choose('https://example.com/game/mobile/index.html?performance',true,false).destination,'https://example.com/game/index.html?performance');
});
test('desktop and explicit desktop renderer keep existing delivery',()=>{
  assert.equal(choose('https://example.com/game/',false,true).redirecting,false);
  assert.equal(choose('https://example.com/game/?renderer=desktop',true,true).redirecting,false);
});
test('mobile selection stabilizes without a redirect loop',()=>{
  assert.equal(choose('https://example.com/game/mobile/index.html',true,true).redirecting,false);
});
