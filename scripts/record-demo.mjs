import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';

// A single recorder assigns ordinals at invocation and after the observed response.
// The deliberately stale service is a controlled fault, not an external database claim.
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const destination = path.resolve(process.argv[2] ?? '.');
fs.mkdirSync(destination, {recursive:true});
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

async function history(stale) {
  let ordinal = 0, value = 0;
  const operations = [];
  async function observe(id, client, input, run) {
    const item = {id, client, call:++ordinal, input};
    operations.push(item);
    item.output = await run();
    item.return = ++ordinal;
  }
  await observe('committed-write', 'a', {type:'write', value:1}, async () => {
    await sleep(2); value = 1; return 'ok';
  });
  await Promise.all([
    observe('read-one', 'b', {type:'read'}, async () => { await sleep(1); return stale ? 0 : value; }),
    observe('read-two', 'c', {type:'read'}, async () => { await sleep(3); return value; }),
  ]);
  return {model:'register', initial:0, operations};
}

for (const [name, stale, expected] of [['correct',false,'linearizable'],['stale',true,'non_linearizable']]) {
  const request = await history(stale);
  const result = spawnSync(process.execPath, [path.join(root,'_build/js/debug/build/cmd/main/main.js'), '-'], {input:JSON.stringify(request), encoding:'utf8'});
  assert.equal(result.status, stale ? 2 : 0, result.stderr);
  const report = JSON.parse(result.stdout);
  assert.equal(report.verdict, expected);
  fs.writeFileSync(path.join(destination,name+'-history.json'),JSON.stringify(request,null,2)+'\n');
  fs.writeFileSync(path.join(destination,name+'-report.json'),JSON.stringify(report,null,2)+'\n');
}
console.log('Recorder integration: actual async calls, correct and injected stale histories passed');
