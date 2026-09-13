#!/usr/bin/env python3
import json, os, pathlib, subprocess, tempfile
ROOT=pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as value:
    root=pathlib.Path(value); binary=root/'bin'; binary.mkdir()
    ssh=binary/'ssh'; ssh.write_text('''#!/bin/sh
case "$*" in
  *ccusage-pi*) printf '%s\\n' '{"daily":[{"date":"2021-01-01","modelBreakdowns":[{"modelName":"model-a","inputTokens":3,"outputTokens":4,"cost":0.2}]}]}' ;;
  *) printf '%s\\n' '{"daily":[{"date":"2021-01-01","modelBreakdowns":[{"modelName":"claude-x","inputTokens":2,"cost":0.1}]}]}' ;;
esac
'''); ssh.chmod(0o755)
    env=dict(os.environ,PATH=str(binary)+os.pathsep+os.environ['PATH'])
    command=['node',str(ROOT/'scripts/modelusage'),'--hosts','fixture','--since','2021-01-01','--until','2021-01-01']
    result=subprocess.run(command+['--format','json'],env=env,text=True,capture_output=True); assert result.returncode==0,result.stderr
    rows=json.loads(result.stdout); assert [(r['source'],r['model']) for r in rows]==[('claude-code','[cc] claude-x'),('pi','model-a')]; assert abs(sum(r['cost_usd'] for r in rows)-0.3)<1e-9
    for output in ['csv','markdown','box']:
        result=subprocess.run(command+['--format',output],env=env,text=True,capture_output=True); assert result.returncode==0,result.stderr; assert '2021-01-01' in result.stdout
    assert subprocess.run(command+['--timeout','0'],env=env,capture_output=True).returncode==2
print('PASS Python-free modelusage collection and output contracts')
