"""Validate distributable structure, local links, syntax and excluded materials."""
import json
from pathlib import Path
import re
import sys

root=Path(__file__).resolve().parents[1]
errors=[]
required=['README.md','README.zh-CN.md','LICENSE','THIRD_PARTY_NOTICES.md','CITATION.cff',
          '.codex-plugin/plugin.json','.agents/plugins/marketplace.json',
          'skills/hierarchical-masem/SKILL.md','skills/hierarchical-masem/assets/renv.lock']
for name in required:
    if not (root/name).is_file():errors.append('Missing '+name)
for p in root.rglob('*'):
    if not p.is_file() or '.git' in p.parts or '__pycache__' in p.parts:continue
    rel=str(p.relative_to(root))
    if p.name in ('Flow_and_BigFive.xlsx','code-original.R') or p.suffix in ('.pdf','.rds','.RData'):
        errors.append('Excluded third-party/runtime artifact: '+rel)
    try:text=p.read_text(encoding='utf-8')
    except UnicodeDecodeError:
        errors.append('Unexpected binary: '+rel);continue
    if re.search('/'+'Users/[^/\\s]+/',text):errors.append('Personal absolute path: '+rel)
    if re.search(r'view_only=[A-Za-z0-9]+',text):errors.append('Read-only access token: '+rel)
    if re.search(r'(?:ghp_|github_pat_)[A-Za-z0-9_]{20,}',text):errors.append('Credential: '+rel)
    if p.suffix=='.py':
        try:compile(text,str(p),'exec')
        except SyntaxError as e:errors.append(str(e))
    if p.suffix=='.json':
        try:json.loads(text)
        except ValueError as e:errors.append(rel+': '+str(e))
    if p.suffix=='.md':
        for link in re.findall(r'\]\(([^)]+)\)',text):
            if '://' in link or link.startswith('#') or '<' in link:continue
            target=link.split('#')[0]
            if target and not (p.parent/target).exists():errors.append(rel+': missing link '+target)
manifest=json.loads((root/'.codex-plugin/plugin.json').read_text())
if manifest['name']!='hierarchical-masem' or manifest['license']!='MIT':errors.append('Manifest identity/license mismatch')
skill=(root/'skills/hierarchical-masem/SKILL.md').read_text()
if not skill.startswith('---\nname: hierarchical-masem\n') or 'description:' not in skill.split('---')[1]:errors.append('Invalid skill frontmatter')
lock=json.loads((root/'skills/hierarchical-masem/assets/renv.lock').read_text())
if lock['R']['Version']!='4.6.0' or len(lock['Packages'])!=46:errors.append('Lockfile differs from verified environment')
print(json.dumps({'status':'fail' if errors else 'pass','errors':errors},indent=2))
sys.exit(bool(errors))
