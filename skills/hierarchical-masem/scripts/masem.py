#!/usr/bin/env python3
"""Offline hierarchical MASEM entry point. Only setup downloads packages."""
from __future__ import annotations
import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def write_json(path, obj):
    Path(path).write_text(json.dumps(obj, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

def runtime_default():
    lock = ROOT / 'assets/renv.lock'
    version = json.loads(lock.read_text())['R']['Version']
    cache = Path.home() / ('Library/Caches' if sys.platform == 'darwin' else '.cache')
    return cache / 'psych-meta-workbench/hierarchical-masem' / (version + '-' + sha(lock)[:12])

def rcall(action, runtime, *args):
    env = os.environ.copy()
    env.update({'OMP_NUM_THREADS': '1', 'OPENBLAS_NUM_THREADS': '1',
                'VECLIB_MAXIMUM_THREADS': '1', 'RENV_CONFIG_AUTOLOADER_ENABLED': 'FALSE'})
    return subprocess.run(['Rscript', '--vanilla', str(ROOT/'scripts/main.R'),
                           action, str(runtime), str(ROOT), *map(str, args)],
                          capture_output=True, text=True, env=env)

def initialize(project, tutorial=False, example=False, tutorial_data=None):
    if tutorial and example:
        raise ValueError('Choose --tutorial or --example, not both')
    author_data = None
    if tutorial:
        author_data = tutorial_data or ROOT/'assets/tutorial/Flow_and_BigFive.xlsx'
        if not author_data.is_file():
            raise ValueError('Author data are not redistributed. Obtain the XLSX from the article supplement and pass --tutorial-data <file>')
        source = json.loads((ROOT/'assets/tutorial/source.json').read_text())
        expected = next(f['sha256'] for f in source['files'] if f['file']=='Flow_and_BigFive.xlsx')
        if sha(author_data) != expected:
            raise ValueError('Author tutorial XLSX checksum differs from the recorded source; inspect its version before benchmarking')
    if project.exists() and any(project.iterdir()):
        raise ValueError('init requires a new or empty project; existing inputs are never overwritten')
    project.mkdir(parents=True, exist_ok=True)
    for name in ('config.json', 'model.json'):
        src = ROOT/'assets'/('tutorial' if tutorial else 'example' if example else 'templates')/name
        shutil.copy2(src, project/name)
    if tutorial:
        shutil.copy2(author_data, project/'correlations.xlsx')
    elif example:
        shutil.copy2(ROOT/'assets/example/correlations.csv',project/'correlations.csv')
    else:
        (project/'correlations.csv').write_text('study_id,sample_id,var1,var2,r,n,overlap_group\n')
    return {'status': 'initialized', 'project': str(project), 'tutorial': tutorial,
            'data_role': 'synthetic_example' if example else 'author_tutorial' if tutorial else 'user_input_template'}

def run(project, runtime):
    config = json.loads((project/'config.json').read_text())
    data = (project/config['data_file']).resolve()
    model = (project/config.get('model_file', 'model.json')).resolve()
    check = rcall('validate', runtime, project)
    if check.returncode:
        raise ValueError(check.stderr.strip() or check.stdout.strip())
    stamp = dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ')
    out = project/'runs'/stamp
    inputs = out/'inputs'
    inputs.mkdir(parents=True)
    shutil.copy2(data, inputs/('correlations'+data.suffix.lower()))
    shutil.copy2(model, inputs/'model.json')
    normalized = dict(config, data_file='correlations'+data.suffix.lower(), model_file='model.json')
    write_json(inputs/'config.json', normalized)
    shutil.copy2(ROOT/'assets/renv.lock', inputs/'renv.lock')
    # Archive the executable source used for this run, independently of future plugin updates.
    shutil.copytree(ROOT/'scripts', out/'code/scripts', ignore=shutil.ignore_patterns('__pycache__'))
    (out/'code/assets').mkdir(parents=True)
    shutil.copy2(ROOT/'assets/renv.lock', out/'code/assets/renv.lock')
    (out/'REPRODUCE.md').write_text(
        '# Reproduce this saved analysis\n\n'
        'From this run directory, use the archived executable and inputs:\n\n'
        '```\npython3 code/scripts/masem.py setup\n'
        'python3 code/scripts/masem.py run --project inputs\n```\n\n'
        'Skip setup when the locked environment is already available. The rerun creates a new '
        'directory under inputs/runs; it does not overwrite these results. The R version is '
        'pinned in code/assets/renv.lock. Analysis itself is offline.\n',encoding='utf-8')
    completed = rcall('run', runtime, inputs, out)
    (out/'run.log').write_text(completed.stdout + '\n' + completed.stderr)
    if completed.returncode:
        write_json(out/'failure.json', {'status':'failed','message':completed.stderr.strip()})
        raise ValueError(f'Analysis failed; diagnostic record: {out}/failure.json\n{completed.stderr.strip()}')
    result = json.loads((out/'results.json').read_text())
    try:
        from report import write_html_report
        report = write_html_report(out)
    except Exception as exc:
        write_json(out/'failure.json', {'status':'failed','message':'Report generation failed: '+str(exc)})
        raise ValueError(f'Report generation failed; analysis files are retained in {out}: {exc}') from exc
    files = {str(p.relative_to(out)):sha(p) for p in sorted(out.rglob('*')) if p.is_file()}
    write_json(out/'manifest.json', {'schema_version':2,'created_utc':stamp,'runtime':str(runtime),
        'source_inputs': {str(data):sha(data),str(model):sha(model),str(project/'config.json'):sha(project/'config.json')},
        'files':files, 'analysis_status':result['status']})
    return {'status': result['status'], 'run':str(out), 'report_html':str(report)}

def demo(project, runtime):
    """Complete a synthetic example without changing existing project files."""
    ready = rcall('check', runtime)
    if ready.returncode:
        raise ValueError(ready.stderr.strip() or ready.stdout.strip())
    initialize(project, example=True)
    answer = run(project, runtime)
    verify(Path(answer['run']), runtime)
    answer.update(verification='pass', data_role='synthetic_software_example')
    return answer

def verify(out, runtime):
    manifest = json.loads((out/'manifest.json').read_text())
    errors = []
    if manifest.get('schema_version') not in (1, 2):
        errors.append('unsupported run manifest version')
    required = ['results.json','data_checks.json','pooled_correlations.csv','pooled_acov.csv',
                'stage1_models.csv','paths.csv','report.md','sessionInfo.txt','fit_objects.rds']
    if manifest.get('schema_version') == 2:
        required.append('report.html')
    for f in required:
        if f not in manifest['files']:
            errors.append('missing required artifact: '+f)
    for name, expected in manifest['files'].items():
        path = (out/name).resolve()
        if not path.is_relative_to(out.resolve()) or not path.is_file() or sha(path) != expected:
            errors.append('artifact missing or changed: '+name)
    result = json.loads((out/'results.json').read_text())
    check = json.loads((out/'data_checks.json').read_text())
    if result.get('n_total') != check.get('n_total') or result.get('n_studies') != check.get('n_studies'):
        errors.append('sample counts disagree between artifacts')
    if result.get('status') not in ('complete','complete_with_diagnostics'):
        errors.append('analysis is not complete')
    if result.get('stage2',{}).get('status') != 'ok':
        errors.append('primary Stage 2 fit invalid')
    if not errors:
        completed=rcall('verify', runtime, out)
        if completed.returncode:errors.append(completed.stderr.strip() or completed.stdout.strip())
    if errors:
        raise ValueError('; '.join(errors))
    return {'status':'pass','run':str(out),'artifacts_checked':len(manifest['files']),
            'analysis_status':result['status'],'diagnostic_count':len(result.get('diagnostics',[]))}

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('command',choices=['setup','check','init','demo','validate','run','verify','benchmark'])
    p.add_argument('--runtime',type=Path)
    p.add_argument('--project',type=Path)
    p.add_argument('--run',type=Path)
    p.add_argument('--tutorial',action='store_true')
    p.add_argument('--example',action='store_true',help='Initialize an openly redistributable synthetic example')
    p.add_argument('--tutorial-data',type=Path,help='User-supplied original author XLSX; checksum is checked')
    a=p.parse_args(); runtime=(a.runtime or runtime_default()).expanduser().resolve()
    if a.command=='setup':
        completed=subprocess.run(['Rscript','--vanilla',str(ROOT/'scripts/setup.R'),str(runtime),str(ROOT/'assets/renv.lock')],capture_output=True,text=True)
        if completed.returncode:raise ValueError(completed.stdout+'\n'+completed.stderr)
        ans={'status':'ready','runtime':str(runtime),'lock_sha256':sha(ROOT/'assets/renv.lock')}
    elif a.command=='check':
        c=rcall('check',runtime)
        if c.returncode:raise ValueError(c.stderr.strip())
        ans=json.loads(c.stdout)
    elif a.command=='verify':
        if not a.run:raise ValueError('--run is required')
        ans=verify(a.run.resolve(),runtime)
    else:
        if not a.project:raise ValueError('--project is required')
        project=a.project.expanduser().resolve()
        if a.command=='init':ans=initialize(project,a.tutorial,a.example,a.tutorial_data)
        elif a.command=='demo':ans=demo(project,runtime)
        elif a.command=='validate':
            c=rcall('validate',runtime,project)
            if c.returncode:raise ValueError(c.stderr.strip() or c.stdout.strip())
            ans=json.loads(c.stdout)
        elif a.command=='run':ans=run(project,runtime)
        else:
            initialize(project,True,tutorial_data=a.tutorial_data)
            ans=run(project,runtime)
            verify(Path(ans['run']),runtime)
            c=rcall('benchmark',runtime,Path(ans['run']))
            if c.returncode:raise ValueError(c.stderr.strip() or c.stdout.strip())
            ans['benchmark']=json.loads(c.stdout)
    print(json.dumps(ans,ensure_ascii=False,indent=2))

if __name__=='__main__':
    try:main()
    except (ValueError,KeyError,OSError,subprocess.SubprocessError) as e:
        print(json.dumps({'status':'error','message':str(e)},ensure_ascii=False),file=sys.stderr)
        sys.exit(1)
