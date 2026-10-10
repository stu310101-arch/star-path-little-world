const test=require('node:test');
const assert=require('node:assert/strict');
const {encode,decode}=require('./recompress_web_resources.cjs');
test('RSCC roundtrips empty, partial, exact-multiple and multiblock payloads',()=>{
  for(const length of [0,1,4096,65535,65536,65537,196608,1048576,1048577]) {
    const data=Buffer.alloc(length);
    for(let i=0;i<length;i++)data[i]=(i*73+(i>>>9))&255;
    const old=encode(data,4096);
    for(const size of [65536,1048576])assert.ok(decode(encode(decode(old),size)).equals(data));
  }
});
test('unknown modes, zero block size and truncated tables/frames/footer are rejected',()=>{
  const valid=encode(Buffer.alloc(10000,17));
  for(const bytes of [valid.subarray(0,20),valid.subarray(0,valid.length-1)])assert.throws(()=>decode(bytes));
  for(const [offset,value] of [[4,1],[8,0],[12,0xffffffff],[16,0xffffffff]]) {
    const bad=Buffer.from(valid);bad.writeUInt32LE(value,offset);assert.throws(()=>decode(bad));
  }
  const footer=Buffer.from(valid);footer[footer.length-1]=0;assert.throws(()=>decode(footer));
});
