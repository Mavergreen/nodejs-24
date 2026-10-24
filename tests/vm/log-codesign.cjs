const cp = require('node:child_process');
const original = cp.spawnSync;
cp.spawnSync = function(file, args, options) {
  const result = Reflect.apply(original, this, arguments);
  if (file === '/usr/bin/codesign') {
    console.error('codesign status:', result.status, 'signal:', result.signal);
    if (result.error) console.error(result.error);
    if (result.stdout) console.error('codesign stdout:', result.stdout.toString());
    if (result.stderr) console.error('codesign stderr:', result.stderr.toString());
  }
  return result;
};
