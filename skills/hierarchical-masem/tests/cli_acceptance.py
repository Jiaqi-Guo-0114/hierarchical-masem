"""python3 cli_acceptance.py <skill> <tutorial-run> <work-dir> <report.json>."""
import csv
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

root, baseline, scratch, report = map(Path, sys.argv[1:])
scratch.mkdir(parents=True, exist_ok=True)
results = {}
cli = root / 'scripts/masem.py'
env = os.environ.copy()
env.update({k: 'http://127.0.0.1:9' for k in ('http_proxy','https_proxy','HTTP_PROXY','HTTPS_PROXY')})

def call(script, *args, success=True):
    p = subprocess.run([sys.executable, str(script), *map(str,args)], capture_output=True, text=True, env=env)
    if success and p.returncode:
        raise AssertionError(p.stdout+'\n'+p.stderr)
    if not success and p.returncode == 0:
        raise AssertionError('Invalid operation unexpectedly succeeded')
    return json.loads(p.stdout if success else p.stderr)

def test(name, fn):
    try:
        detail = fn()
        results[name] = dict(status='pass', detail=detail)
    except Exception as e:
        results[name] = dict(status='fail', message=str(e))
    print(name, results[name]['status'], flush=True)

def table(path):
    with path.open() as f:
        return list(csv.DictReader(f))

def repeat():
    project = scratch / 'repeat-inputs'
    shutil.copytree(baseline/'inputs', project)
    # Replay from archived code: no dependency on a later plugin source update.
    archived = baseline/'code/scripts/masem.py'
    call(archived, 'check')
    r = call(archived, 'run', '--project', project)
    rerun = Path(r['run'])
    call(archived, 'verify', '--run', rerun)
    maximum = 0.0
    for name, fields in {
        'stage1_models.csv': ['AIC','BIC'], 'paths.csv': ['estimate','se','ci_lower','ci_upper'],
        'sensitivity.csv': ['estimate','ci_lower','ci_upper'],
        'group_paths.csv': ['estimate','se','ci_lower','ci_upper'],
        'moderator_path_tests.csv': ['delta_chi_square','p_raw','p_holm'],
        'moderator_pairwise.csv': ['difference','ci_lower','ci_upper','delta_chi_square','p_raw','p_holm'],
        'moderator_sensitivity.csv': ['delta_chi_square','p_raw'],
    }.items():
        a, b = table(baseline/name), table(rerun/name)
        assert len(a) == len(b)
        for ra, rb in zip(a,b):
            for field in fields:
                maximum = max(maximum, abs(float(ra[field])-float(rb[field])))
            if 'ci_status' in ra:
                assert ra['ci_status'] == rb['ci_status']
    assert maximum < 1e-7, maximum
    return dict(max_absolute_difference=maximum, run=str(rerun))

def tamper():
    target = scratch/'tampered-copy'
    shutil.copytree(baseline, target)
    with (target/'paths.csv').open('a') as f: f.write('\nchanged\n')
    e = call(cli,'verify','--run',target,success=False)
    assert 'changed: paths.csv' in e['message']
    return 'Modified result rejected by SHA-256 verification'

def alternate():
    project = scratch/'synthetic-three-variable'
    call(cli,'init','--project',project)
    c=json.loads((project/'config.json').read_text())
    c.update(variables=['x','middle','end'],sample_independence='confirmed_independent',
             sensitivity={'settings':[[0,0]],'leave_one_study_out':False})
    m=dict(variables=c['variables'],A=[[0,0,0],['0.1*a',0,0],[0,'0.1*b',0]],
           S=[[1,0,0],[0,'0.8*v2',0],[0,0,'0.8*v3']])
    for name,obj in [('config.json',c),('model.json',m)]:
        (project/name).write_text(json.dumps(obj))
    with (project/'correlations.csv').open('w') as f:
        w=csv.writer(f);w.writerow(['study_id','sample_id','var1','var2','r','n','overlap_group'])
        for i,study in enumerate(['s1','s1','s2','s3','s3','s4','s5','s6']):
            a=.20+i*.02;b=.30+(i%4)*.04
            for v1,v2,r in [('middle','x',a),('end','x',a*b+.025),('end','middle',b)]:
                w.writerow([study,f'sample{i}',v1,v2,r,150+i*10,''])
    call(cli,'validate','--project',project)
    r=call(cli,'run','--project',project);call(cli,'verify','--run',r['run'])
    x=json.loads((Path(r['run'])/'results.json').read_text())
    assert x['n_studies']==6 and x['n_samples']==8 and x['stage2']['fit']['df']==1
    assert len(table(Path(r['run'])/'stage1_models.csv'))==4
    return dict(data_role='synthetic test fixture only',run=r['run'],model=x['stage1_model'])

def failure_record():
    project=scratch/'underidentified'
    shutil.copytree(baseline/'inputs',project)
    m=json.loads((project/'model.json').read_text())
    y=len(m['variables'])-1
    m['S'][0][y]=m['S'][y][0]='0*extra_cov'
    (project/'model.json').write_text(json.dumps(m))
    e=call(cli,'run','--project',project,success=False)
    runs=list((project/'runs').iterdir());assert len(runs)==1
    assert (runs[0]/'failure.json').is_file() and not (runs[0]/'manifest.json').exists()
    assert any(s in e['message'] for s in ['underidentified','optimization failed'])
    return 'Invalid SEM retained failure.json and no success manifest'

test('offline_archived_code_reproduction', repeat)
test('artifact_tampering_rejected', tamper)
test('different_data_and_model_end_to_end', alternate)
test('failed_analysis_has_no_success_manifest', failure_record)
ok=all(t['status']=='pass' for t in results.values())
report.write_text(json.dumps(dict(status='pass' if ok else 'fail',tests=results),indent=2)+'\n')
sys.exit(0 if ok else 1)
