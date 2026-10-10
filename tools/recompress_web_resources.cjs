// Godot 4.7.2 RSCC/Zstandard container. Only compressed block boundaries change.
// Format reference: core/io/file_access_compressed.cpp at ed1daf0bf.
// Run by recompress_web_resources.py; Node 24+ provides native Zstandard.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const zlib = require('node:zlib');
const assert = require('node:assert/strict');

function decode(data) {
  if (data.length < 24 || data.toString('ascii',0,4)!=='RSCC' || data.readUInt32LE(4)!==2) throw Error('Expected pinned RSCC/ZSTD resource');
  const size=data.readUInt32LE(8), length=data.readUInt32LE(12);
  if (!size || size>1048576 || length>512*1024*1024) throw Error('Invalid compressed resource bounds');
  const count=Math.floor(length/size)+1, chunks=[];
  let offset=16+4*count;
  if(offset>data.length-4)throw Error('Truncated block table');
  for(let i=0;i<count;i++) {
    const bytes=data.readUInt32LE(16+i*4), expected=i===count-1?length%size:size;
    if(!bytes || offset+bytes>data.length-4)throw Error('Truncated compressed block');
    const block=zlib.zstdDecompressSync(data.subarray(offset,offset+bytes),{maxOutputLength:Math.max(1,size)});
    if(block.length!==expected)throw Error('Decoded block length mismatch');
    chunks.push(block); offset+=bytes;
  }
  if(offset!==data.length-4 || data.toString('ascii',offset)!=='RSCC')throw Error('Compressed resource footer mismatch');
  return Buffer.concat(chunks,length);
}
function encode(raw, size=65536) {
  const count=Math.floor(raw.length/size)+1, table=Buffer.alloc(16+count*4), blocks=[];
  table.write('RSCC');table.writeUInt32LE(2,4);table.writeUInt32LE(size,8);table.writeUInt32LE(raw.length,12);
  for(let i=0;i<count;i++) {
    const block=zlib.zstdCompressSync(raw.subarray(i*size,Math.min(raw.length,(i+1)*size)),{
      params:{[zlib.constants.ZSTD_c_compressionLevel]:9}});
    table.writeUInt32LE(block.length,16+i*4);blocks.push(block);
  }
  return Buffer.concat([table,...blocks,Buffer.from('RSCC')]);
}
module.exports={encode,decode};
if(require.main===module) {
  const folder=path.resolve(process.argv[2]), entries=JSON.parse(fs.readFileSync(path.join(folder,'inputs.json'),'utf8'));
  const report=[];
  for(const row of entries) {
    const source=fs.readFileSync(path.join(folder,row.file)), raw=decode(source);
    // Large pose/geometry arrays need a window spanning adjacent poses. Small
    // resources retain 64 KiB blocks to bound random-read/decompression buffers.
    const size=raw.length>=2*1048576?1048576:65536, next=encode(raw,size);
    assert.ok(decode(next).equals(raw),'Recompressed resource payload must be byte-identical');
    const changed=next.length<source.length*.98;
    if(changed)fs.writeFileSync(path.join(folder,row.file),next);
    report.push({resource:row.resource,before:source.length,after:changed?next.length:source.length,
      decoded_bytes:raw.length,decoded_sha256:crypto.createHash('sha256').update(raw).digest('hex'),
      source_block_bytes:source.readUInt32LE(8),block_bytes:changed?size:source.readUInt32LE(8)});
  }
  fs.writeFileSync(path.join(folder,'report.json'),JSON.stringify(report,null,2));
}
