"""Check the public example, reports, input validation and offline replay."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

root=Path(__file__).resolve().parents[1]
skill=root/'skills/hierarchical-masem'
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--workdir',type=Path,default=Path('test-output'))
p.add_argument('--setup',action='store_true',help='Authorize restoring the isolated package environment')
a=p.parse_args();scratch=a.workdir.resolve()
if scratch.exists() and any(scratch.iterdir()):p.error('--workdir must be new or empty')
scratch.mkdir(parents=True,exist_ok=True)
env=os.environ.copy()
env.update({'OMP_NUM_THREADS':'1','OPENBLAS_NUM_THREADS':'1','VECLIB_MAXIMUM_THREADS':'1'})
def call(name,command):
    z=subprocess.run(command,capture_output=True,text=True,env=env)
    (scratch/(name+'.log')).write_text(z.stdout+'\n'+z.stderr)
    if z.returncode:raise RuntimeError(name+' failed; see '+str(scratch/(name+'.log')))
    return z.stdout
try:
    call('package',[sys.executable,str(root/'tools/validate_package.py')])
    cli=[sys.executable,str(skill/'scripts/masem.py')]
    if a.setup:call('setup',cli+['setup'])
    runtime=json.loads(call('runtime',cli+['check']))['runtime']
    call('html-report',[sys.executable,'-m','unittest','discover','-s',str(skill/'tests'),'-p','test_report.py','-v'])
    call('report-wording',['Rscript','--vanilla',str(skill/'tests/report_wording.R'),str(skill)])
    call('options',['Rscript','--vanilla',str(skill/'tests/options_validation.R'),str(skill),runtime,str(scratch/'options.json')])
    project=scratch/'example'
    demo=json.loads(call('demo',cli+['demo','--project',str(project)]))
    if demo['verification']!='pass' or not Path(demo['report_html']).is_file():
        raise AssertionError('Demo did not return a verified browser report')
    run=demo['run']
    call('numerical',['Rscript','--vanilla',str(skill/'tests/example_acceptance.R'),str(skill),runtime,run,str(scratch/'numerical.json')])
    call('offline-cli',[sys.executable,str(skill/'tests/cli_acceptance.py'),str(skill),run,str(scratch/'cli'),str(scratch/'cli.json')])
    reports={name:json.loads((scratch/(name+'.json')).read_text()) for name in ['numerical','cli','options']}
    result={'status':'pass','data_role':'synthetic_software_tests','run':run,'reports':reports,'html_report_tests':'pass','report_wording_tests':'pass'}
except Exception as e:
    result={'status':'fail','message':str(e)}
(scratch/'checks.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({'status':result['status'],'record':str(scratch/'checks.json')},indent=2))
sys.exit(result['status']!='pass')
