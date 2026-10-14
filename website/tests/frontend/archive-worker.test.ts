import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import type { ArchiveWorkerRequest } from '../../src/frontend/archive-worker';
let receive: (event:MessageEvent<ArchiveWorkerRequest>)=>void;
beforeEach(async()=>{
  vi.resetModules();
  vi.spyOn(globalThis,'addEventListener').mockImplementation((name,listener)=>{if(name==='message') receive=listener as typeof receive;});
  vi.stubGlobal('postMessage',vi.fn());
  await import('../../src/frontend/archive-worker');
});
afterEach(()=>{vi.restoreAllMocks();vi.unstubAllGlobals();});
function query(keys:string[],bitmaps:Record<string,Uint8Array>={},generation='a',page=1):void {
  receive(new MessageEvent('message',{data:{id:1,generation,total:8,size:2,query:{groups:[keys],range:[0,8],page},bitmaps,mode:'page'}}));
}
it('reuses received postings across page queries while unknown filters remain empty',()=>{
  query(['topic/a'],{'topic/a':new Uint8Array([85])});
  expect(vi.mocked(postMessage).mock.lastCall![0]).toMatchObject({count:4,ordinals:[0,2]});
  query(['topic/a'],{},'a',2);
  expect(vi.mocked(postMessage).mock.lastCall![0]).toMatchObject({count:4,ordinals:[4,6]});
  query(['missing']); expect(vi.mocked(postMessage).mock.lastCall![0]).toMatchObject({count:0,ordinals:[]});
});
it('supports queries beyond the cache budget and drops postings on generation changes',()=>{
  const keys=Array.from({length:21},(_,i)=>'topic/'+i);
  query(keys,Object.fromEntries(keys.map(key=>[key,new Uint8Array([255])])));
  expect(vi.mocked(postMessage).mock.lastCall![0]).toMatchObject({count:8,ordinals:[0,1]});
  query([keys[0]!]); expect(vi.mocked(postMessage).mock.lastCall![0]).toMatchObject({count:0});
  query([keys[20]!],{},'b'); expect(vi.mocked(postMessage).mock.lastCall![0]).toMatchObject({count:0});
  query([keys[20]!],{[keys[20]!]:new Uint8Array([128])},'b');
  expect(vi.mocked(postMessage).mock.lastCall![0]).toMatchObject({count:1,ordinals:[7]});
});
