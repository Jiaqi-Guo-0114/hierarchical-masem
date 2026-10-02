"""Render saved MASEM results as an offline, bilingual HTML report.

This module presents existing results; it does not estimate models, test
hypotheses, or repair missing results. All data-derived text is HTML escaped.
"""
from __future__ import annotations

import csv
import html
import json
import math
from pathlib import Path
import re


def _e(value):
    return html.escape(str(value if value is not None else ""), quote=True)


def _bi(zh, en):
    return '<span class="zh" lang="zh-Hans">' + _e(zh) + '</span><span class="en" lang="en">' + _e(en) + '</span>'


def _number(value):
    try:
        value = float(value)
        return value if math.isfinite(value) else None
    except (TypeError, ValueError):
        return None


def _value(value, digits=3, p=False):
    number = _number(value)
    if number is None:
        return '<span class="muted">—</span>'
    shown = '<0.001' if p and 0 <= number < .001 else f'{number:.{digits}f}'
    return '<span class="number" title="' + _e(value) + '">' + _e(shown) + '</span>'


def _integer(value):
    number = _number(value)
    return _e(f'{int(number):,}') if number is not None and number.is_integer() else '—'


def _read_json(path, required=False):
    if not path.is_file() and not required:
        return {}
    value = json.loads(path.read_text(encoding='utf-8'))
    if not isinstance(value, dict):
        raise ValueError(f'{path.name} must contain a JSON object')
    return value


def _read_csv(path, required=False):
    if not path.is_file() and not required:
        return []
    with path.open(encoding='utf-8-sig', newline='') as stream:
        return list(csv.DictReader(stream))


def _status(value):
    if value in ('ok', 'pass', 'complete', 'complete_with_diagnostics'):
        return '<span class="badge good">' + _bi('完成', 'Complete') + '</span>'
    if value in (None, ''):
        return '<span class="badge caution">' + _bi('未报告', 'Not reported') + '</span>'
    return '<span class="badge caution">' + _bi('未通过', 'Not successful') + '</span> <small>' + _e(value) + '</small>'


def _role(value):
    return {'planned': _bi('预设', 'Planned'), 'exploratory': _bi('探索性', 'Exploratory')}.get(value, _bi('未声明', 'Not declared'))


def _valid_ci(row, estimate='estimate'):
    values = [_number(row.get(k)) for k in (estimate, 'ci_lower', 'ci_upper')]
    return (row.get('ci_status') == 'ok' and row.get('status', 'ok') == 'ok'
            and all(x is not None for x in values) and values[1] <= values[0] <= values[2])


def _ci(row, estimate='estimate'):
    if not _valid_ci(row, estimate):
        return '<span class="badge caution">' + _bi('区间失败或缺失', 'CI failed or missing') + '</span>'
    return '[' + _value(row['ci_lower']) + ', ' + _value(row['ci_upper']) + ']'


def _path(row):
    if row.get('predictor') and row.get('outcome'):
        return _e(row['predictor']) + ' <span aria-hidden="true">→</span> ' + _e(row['outcome']) + '<small class="sub">' + _e(row.get('path', '')) + '</small>'
    return _e(row.get('path', ''))


def _table(rows, columns):
    if not rows:
        return '<p class="empty">' + _bi('本次运行没有此项结果。', 'No results for this section in this run.') + '</p>'
    head = ''.join('<th scope="col">' + _bi(zh, en) + '</th>' for zh, en, _ in columns)
    body = ''.join('<tr>' + ''.join('<td>' + formatter(row) + '</td>' for _, _, formatter in columns) + '</tr>' for row in rows)
    return '<div class="table-scroll"><table><thead><tr>' + head + '</tr></thead><tbody>' + body + '</tbody></table></div>'


def _path_table(rows, grouped=False):
    columns = [('路径', 'Path', _path), ('估计值', 'Estimate', lambda r: _value(r.get('estimate'))),
               ('95% 区间', '95% CI', _ci), ('标准误', 'SE', lambda r: _value(r.get('se')))]
    if grouped:
        columns.insert(0, ('组别', 'Group', lambda r: _e(r.get('group'))))
    return _table(rows, columns)


def _forest(rows):
    valid = [r for r in rows if _valid_ci(r)]
    if not valid:
        return '<p class="empty">' + _bi('没有可绘制的有效区间。请查看下表的区间状态。', 'No valid intervals to plot. See interval status in the table below.') + '</p>'
    # Coordinate transforms only: plotted values come directly from the CSV.
    numbers = [float(r[k]) for r in valid for k in ('ci_lower', 'ci_upper')]
    scale = max(1.0, *(abs(v) for v in numbers))
    lo, hi = min(0.0, min(numbers) / scale), max(0.0, max(numbers) / scale)
    if hi == lo:
        lo, hi = -.5, .5
    left, width, top, step = 240, 580, 32, 47
    height = top + step * len(rows) + 42
    position = lambda value: left + ((float(value) / scale - lo) / (hi - lo)) * width
    parts = [f'<svg class="forest" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 960 {height}" role="img" aria-labelledby="forest-title forest-description">',
             '<title id="forest-title">路径估计与 95% 区间 / Path estimates and 95% confidence intervals</title>',
             '<desc id="forest-description">只有状态有效的区间被绘制；完整数值见下表。 Only valid intervals are plotted; full values are in the following table.</desc>']
    for i in range(5):
        tick = lo + (hi - lo) * i / 4
        x = left + width * i / 4
        parts.append(f'<line class="grid" x1="{x:.2f}" x2="{x:.2f}" y1="14" y2="{height - 42}"/><text class="axis" x="{x:.2f}" y="{height - 16}" text-anchor="middle">{_e(f"{tick * scale:.2f}")}</text>')
    zero = position(0)
    parts.append(f'<line class="zero" x1="{zero:.2f}" x2="{zero:.2f}" y1="14" y2="{height - 42}"/>')
    for i, row in enumerate(rows):
        y = top + i * step
        label = f"{row['predictor']} → {row['outcome']}" if row.get('predictor') and row.get('outcome') else row.get('path', '')
        short = label if len(label) <= 28 else label[:27] + '…'
        parts.append(f'<text class="path-label" x="8" y="{y + 5}"><title>{_e(label)}</title>{_e(short)}</text>')
        if _valid_ci(row):
            a, b, center = (position(row[k]) for k in ('ci_lower', 'ci_upper', 'estimate'))
            parts.append(f'<g class="valid-interval"><title>{_e(label)}: {_e(row["estimate"])} [{_e(row["ci_lower"])}, {_e(row["ci_upper"])}]</title><line class="ci-whisker" x1="{a:.2f}" x2="{b:.2f}" y1="{y}" y2="{y}"/><line class="ci-cap" x1="{a:.2f}" x2="{a:.2f}" y1="{y - 5}" y2="{y + 5}"/><line class="ci-cap" x1="{b:.2f}" x2="{b:.2f}" y1="{y - 5}" y2="{y + 5}"/><circle class="estimate-dot" cx="{center:.2f}" cy="{y}" r="5"/></g>')
            shown = f"{float(row['estimate']):.3f}"
            parts.append(f'<text class="axis" x="850" y="{y + 5}">{_e(shown)}</text>')
        else:
            parts.append(f'<text class="ci-missing" x="{left}" y="{y + 5}">区间缺失 / CI unavailable</text>')
    parts.append('</svg>')
    return '<div class="figure-scroll">' + ''.join(parts) + '</div>'


def _section(identifier, eyebrow, zh, en, content):
    return '<section id="' + identifier + '"><div class="section-heading"><span class="eyebrow">' + _e(eyebrow) + '</span><h2>' + _bi(zh, en) + '</h2></div>' + content + '</section>'


_STYLE = """
:root{color-scheme:light;--ink:#173e3a;--text:#263a3a;--muted:#607371;--line:#dce5e1;--paper:#fff;--bg:#f4f6f2;--gold:#9c6d22;--pale:#faf1df}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:15px/1.65 -apple-system,BlinkMacSystemFont,"Segoe UI","PingFang SC","Microsoft YaHei",sans-serif}.shell{max-width:1120px;margin:0 auto;padding:32px 34px 48px}.lang-radio{position:absolute;left:-10000px}.language{display:flex;gap:4px;border:1px solid var(--line);border-radius:24px;padding:4px;flex-shrink:0}.language label{padding:4px 15px;cursor:pointer;border-radius:18px;font-size:13px}.en{display:none}#lang-en:checked~.shell .zh{display:none}#lang-en:checked~.shell .en{display:revert}#lang-zh:checked~.shell label[for=lang-zh],#lang-en:checked~.shell label[for=lang-en]{color:white;background:var(--ink)}.lang-radio:focus-visible~.shell .language{outline:2px solid var(--gold);outline-offset:3px}.topline{display:flex;justify-content:space-between;align-items:center;gap:20px}.brand{font-size:13px;letter-spacing:.09em;font-weight:700;color:var(--ink)}.hero{padding:34px 0 28px}h1{font-size:clamp(29px,4vw,42px);line-height:1.22;letter-spacing:-.025em;color:var(--ink);margin:0 0 16px}h2{font-size:23px;line-height:1.35;margin:0;color:var(--ink)}h3{font-size:17px;color:var(--ink);margin:26px 0 10px}.lead{max-width:780px;margin:0 0 16px;color:var(--muted);font-size:16px}.badge{display:inline-block;padding:2px 9px;font-size:12px;border-radius:6px;font-weight:600;white-space:normal}.good{background:#e5f0e8;color:#21513d}.caution{background:var(--pale);color:#805614}.alert{padding:17px 21px;border-left:4px solid var(--gold);background:var(--pale);border-radius:0 10px 10px 0;margin:18px 0}.alert strong{display:block;margin-bottom:5px}.demo{background:#e8eef8;border-color:#516f97;color:#324a6a}.summary{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin:8px 0 30px}.metric{background:var(--paper);border:1px solid var(--line);border-radius:12px;padding:20px}.metric strong{font-size:30px;line-height:1.25;color:var(--ink);display:block;font-variant-numeric:tabular-nums}.metric small{color:var(--muted);display:block;margin-top:6px}.nav{display:flex;flex-wrap:wrap;gap:18px;border-top:1px solid var(--line);padding:15px 0;font-size:13px}a{color:#216158;text-underline-offset:3px}section{background:var(--paper);border:1px solid var(--line);border-radius:14px;padding:28px;margin:20px 0;scroll-margin-top:20px}.section-heading{display:flex;align-items:baseline;gap:14px;margin-bottom:17px}.eyebrow{font-size:12px;font-weight:700;color:var(--gold);letter-spacing:.08em}.note{color:var(--muted);font-size:13px;margin:10px 0 18px}.table-scroll,.figure-scroll{overflow-x:auto}table{border-collapse:collapse;width:100%;font-size:13px;text-align:left}th{font-size:12px;color:var(--muted);font-weight:600;border-bottom:1px solid var(--line);padding:11px 12px;vertical-align:bottom;white-space:nowrap}td{padding:12px;border-bottom:1px solid #edf1ee;vertical-align:top}tbody tr:last-child td{border:0}tbody tr:hover{background:#f7faf7}.number{font-variant-numeric:tabular-nums;white-space:nowrap}.sub{display:block;color:var(--muted);font-size:11px;max-width:260px;overflow-wrap:anywhere}.muted,.empty{color:var(--muted)}.empty{padding:16px 0}.forest{display:block;width:100%;min-width:680px;margin:12px 0 8px;font-family:inherit}.grid{stroke:#edf1ee;stroke-width:1}.zero{stroke:#9aaa9f;stroke-dasharray:4 4}.ci-whisker,.ci-cap{stroke:#318675;stroke-width:2.5}.estimate-dot{fill:#174c42}.axis{fill:#607371;font-size:13px}.path-label{fill:#263a3a;font-size:14px}.ci-missing{fill:#916315;font-size:13px}.boundaries{padding-left:21px;margin:0}.boundaries li{padding:5px 0}.downloads{display:flex;flex-wrap:wrap;gap:10px}.downloads a{border:1px solid var(--line);border-radius:8px;padding:9px 13px;text-decoration:none;font-size:13px;background:#f9fbf8}.downloads a:hover{border-color:#318675}details{margin-top:18px}summary{cursor:pointer;font-weight:600;color:var(--ink);padding:8px 0}.footer{font-size:12px;color:var(--muted);padding:18px 0 0}.family{font-size:11px;color:var(--muted);overflow-wrap:anywhere}.selected{font-weight:700;color:var(--ink)}
.run-notes-link{margin-left:8px;background:#edf2f1;text-decoration:none}#run-notes{scroll-margin-top:20px}.run-diagnostics{padding-left:21px;font-size:13px;overflow-wrap:anywhere}.run-diagnostics li{margin:8px 0}
@media(max-width:700px){.shell{padding:22px 16px}.summary{grid-template-columns:repeat(2,1fr)}.metric{padding:17px}.metric strong{font-size:26px}section{padding:20px 15px}.topline{align-items:flex-start}.brand{max-width:180px}.nav{gap:14px}.section-heading{gap:10px}}
@media print{body{background:white;font-size:10pt}.shell{max-width:none;padding:0}.language,.nav{display:none}.hero{padding:20px 0 10px}h1{font-size:26pt}.summary{gap:8px;margin-bottom:14px}.metric{padding:12px}.metric strong{font-size:20pt}section{padding:18px 0;border:0;border-top:1px solid var(--line);border-radius:0;margin:12px 0;break-inside:auto}h2,h3,.section-heading{break-after:avoid}.table-scroll,.figure-scroll{overflow:visible}table{font-size:8pt}th,td{padding:7px 5px}tr{break-inside:avoid}.forest{min-width:0}.alert{break-inside:avoid}.downloads a{padding:5px 8px}details>summary{display:none}details>div{display:block!important}.footer{font-size:8pt}a{text-decoration:none;color:inherit}@page{margin:16mm}}
@media print{#run-notes>summary{display:block}}
"""


def write_html_report(out: Path) -> Path:
    """Write ``out/report.html`` using only the saved run's result files.

    Required: results.json, inputs/config.json, paths.csv, stage1_models.csv.
    Optional tables may be absent or empty. The returned standalone file embeds
    its styles and plot; sibling artifact links are optional conveniences.
    """
    out = Path(out)
    result = _read_json(out / 'results.json', required=True)
    config = _read_json(out / 'inputs/config.json', required=True)
    paths = _read_csv(out / 'paths.csv', required=True)
    models = _read_csv(out / 'stage1_models.csv', required=True)
    tables = {name: _read_csv(out / (name + '.csv')) for name in ('group_paths', 'moderator_path_tests', 'moderator_pairwise', 'sensitivity', 'study_influence', 'moderator_sensitivity')}
    moderator = _read_json(out / 'moderator_omnibus.json')
    default_role = moderator.get('role') or (config.get('moderation') or {}).get('mode')
    selected = result.get('stage1_model', '')
    stage2 = result.get('stage2') or {}
    fit = stage2.get('fit') or {}
    diagnostics = result.get('diagnostics') or []
    if isinstance(diagnostics, str):
        diagnostics = [diagnostics]
    notes_link = (' <a class="badge run-notes-link" href="#run-notes">'
                  + _bi('有分析提示', 'Analysis notes available') + '</a>') if diagnostics else ''
    if stage2.get('status') != 'ok':
        # Retain reported estimates but never portray intervals from a failed
        # primary fit as validated intervals.
        paths = [dict(row, status='failed') for row in paths]
    parts = ['<!doctype html><html lang="zh-Hans"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light"><title>层级 MASEM 结果 · Hierarchical MASEM Results</title><style>' + _STYLE + '</style></head><body>',
             '<input class="lang-radio" type="radio" name="language" id="lang-zh" checked aria-label="中文"><input class="lang-radio" type="radio" name="language" id="lang-en" aria-label="English"><main class="shell"><header><div class="topline"><div class="brand">HIERARCHICAL MASEM<br>' + _bi('研究结果报告', 'RESEARCH RESULTS') + '</div><div class="language" aria-label="Language / 语言"><label for="lang-zh">中文</label><label for="lang-en">English</label></div></div>',
             '<div class="hero"><h1>' + _bi('从多项研究，理解变量之间的路径', 'Understand pathways across studies') + '</h1><p class="lead">' + _bi('查看合并路径、区间估计、组间直接比较与稳健性结果。此报告展示本次运行已保存的分析结果。', 'Explore pooled paths, confidence intervals, direct group comparisons, and sensitivity results from this saved analysis.') + '</p>' + _status(result.get('status')) + notes_link + '</div>']
    if any(re.match(r'^synthetic([_-]|$)', str(role), flags=re.IGNORECASE)
           for role in (config.get('data_role', ''), result.get('data_role', ''))):
        parts.append('<aside class="alert demo"><strong>' + _bi('软件演示 · 合成数据', 'Software demonstration · Synthetic data') + '</strong>' + _bi('本报告使用合成示例数据展示软件功能，不构成研究证据。', 'This report uses synthetic example data to demonstrate the software. It is not research evidence.') + '</aside>')
    ci_rows = paths + tables['group_paths'] + tables['sensitivity']
    failures = sum(not _valid_ci(row) for row in ci_rows) + sum(not _valid_ci(row, 'difference') for row in tables['moderator_pairwise'])
    reported_failures = _number(result.get('failed_interval_count')) or 0
    if max(failures, reported_failures) > 0:
        parts.append('<aside class="alert"><strong>' + _bi('存在失败或缺失的区间', 'Some confidence intervals failed or are missing') + '</strong>' + _bi('相关结果已明确标注。未通过的区间不会绘制为有效区间，也不能据此判断效应是否存在。', 'Affected results are marked below. Unsuccessful intervals are not plotted as valid intervals and cannot support conclusions about the presence of an effect.') + '</aside>')
    if stage2.get('status') != 'ok' or not paths:
        parts.append('<aside class="alert"><strong>' + _bi('主路径结果尚不完整', 'Primary path results are incomplete') + '</strong>' + _bi('请先处理分析状态与缺失结果，再解释路径。', 'Resolve the analysis status and missing results before interpreting paths.') + '</aside>')
    metrics = [(result.get('n_studies'), '研究', 'Studies'), (result.get('n_samples'), '独立样本', 'Independent samples'), (result.get('n_total'), '参与者', 'Participants')]
    parts.append('<div class="summary">' + ''.join('<div class="metric"><strong>' + _integer(value) + '</strong><small>' + _bi(zh, en) + '</small></div>' for value, zh, en in metrics) + '<div class="metric"><strong>' + _e(selected.replace('_', ' / ')) + '</strong><small>' + _bi('所选层级结构', 'Selected structure') + '</small></div></div><nav class="nav" aria-label="Sections">' + ''.join('<a href="#' + link + '">' + _bi(zh, en) + '</a>' for link, zh, en in [('paths', '路径结果', 'Paths'), ('models', '模型比较', 'Model comparison'), ('moderation', '组间比较', 'Group comparisons'), ('sensitivity', '敏感性分析', 'Sensitivity'), ('downloads', '结果文件', 'Files')]) + '</nav></header>')

    content = '<p class="note">' + _bi('路径系数及其 95% likelihood-based 区间。森林图展示有效区间；精确值可在表格单元格提示或 CSV 中查看。', 'Path coefficients and 95% likelihood-based intervals. The forest plot shows valid intervals; exact values are available in table-cell tooltips or CSV files.') + '</p>' + _forest(paths) + _path_table(paths)
    if fit.get('saturated') is True or _number(fit.get('df')) == 0:
        content += '<p class="alert">' + _bi('本模型为饱和模型（df = 0）。整体拟合不能用于支持理论；请依据路径、区间与研究设计解释结果。', 'This model is saturated (df = 0). Overall fit cannot support the theory; interpret the paths, uncertainty, and study design.') + '</p>'
    elif fit:
        content += '<p class="note">χ² = ' + _value(fit.get('chi_square')) + ' · df = ' + _integer(fit.get('df')) + ' · p = ' + _value(fit.get('p'), p=True) + ' · RMSEA = ' + _value(fit.get('RMSEA')) + ' · CFI = ' + _value(fit.get('CFI')) + '</p>'
    parts.append(_section('paths', '01', '合并路径与不确定性', 'Pooled paths and uncertainty', content))
    content = '<p class="note">' + _bi('在合格的候选模型中按 AIC 选择；BIC 作为补充。CS 表示共同方差结构，HCS 允许方差异质。顺序为效应层 / 研究层。', 'Selection uses AIC among eligible candidate models, with BIC shown for context. CS uses a common variance structure; HCS allows heterogeneous variances. Order: effect level / study level.') + '</p>'
    content += _table(models, [('结构', 'Structure', lambda r: '<span class="' + ('selected' if r.get('model') == selected else '') + '">' + _e(r.get('model', '').replace('_', ' / ')) + '</span>'), ('AIC', 'AIC', lambda r: _value(r.get('AIC'))), ('BIC', 'BIC', lambda r: _value(r.get('BIC'))), ('参数数', 'Parameters', lambda r: _integer(r.get('parameters'))), ('拟合状态', 'Fit status', lambda r: _status(r.get('status'))), ('选择', 'Selection', lambda r: _bi('所选模型', 'Selected') if r.get('model') == selected else '—')])
    parts.append(_section('models', '02', '第一阶段模型比较', 'Stage 1 model comparison', content))

    content = '<p class="note">' + _bi('使用组间直接检验评估路径差异；不能以“一组显著、另一组不显著”代替组间检验。', 'Use direct tests to assess group differences. A significant path in one group and a nonsignificant path in another is not a test of their difference.') + '</p>'
    omni = moderator.get('omnibus') or result.get('moderation') or {}
    if omni:
        content += '<h3>' + _bi('整体路径差异', 'Overall path differences') + '</h3>'
        content += _table([omni], [('Δχ²', 'Δχ²', lambda r: _value(r.get('delta_chi_square'))), ('df', 'df', lambda r: _integer(r.get('df'))), ('原始 p', 'Raw p', lambda r: _value(r.get('p_raw'), p=True)), ('分析角色', 'Analysis role', lambda r: _role(default_role)), ('状态', 'Status', lambda r: _status(r.get('status')))])
    groups = moderator.get('groups', {})
    if isinstance(groups, dict) and groups:
        content += '<h3>' + _bi('各组证据量', 'Evidence by group') + '</h3>' + _table(list(groups.values()), [('组别', 'Group', lambda r: _e(r.get('group'))), ('研究', 'Studies', lambda r: _integer(r.get('n_studies'))), ('独立样本', 'Independent samples', lambda r: _integer(r.get('n_samples'))), ('参与者', 'Participants', lambda r: _integer(r.get('n')))])
    if tables['group_paths']:
        content += '<details open><summary>' + _bi('各组路径与区间', 'Group paths and intervals') + '</summary><div>' + _path_table(tables['group_paths'], grouped=True) + '</div></details>'
    tests = tables['moderator_path_tests']
    pairs = tables['moderator_pairwise']
    if tests or pairs:
        content += '<p class="note">' + _bi('Holm 校正在各表所示的检验族内实施；原始 p 与校正后 p 均予保留。分析角色来自运行配置，不代表注册状态已获验证。', 'Holm adjustment is applied within the test family shown in each table. Both raw and adjusted p values are retained. Analysis roles come from the run configuration; they do not verify preregistration.') + '</p>'
    common = [('Δχ²', 'Δχ²', lambda r: _value(r.get('delta_chi_square'))), ('df', 'df', lambda r: _integer(r.get('df'))), ('原始 p', 'Raw p', lambda r: _value(r.get('p_raw'), p=True)), ('Holm p', 'Holm p', lambda r: _value(r.get('p_holm'), p=True)), ('角色 / 检验族', 'Role / test family', lambda r: _role(r.get('analysis_role') or default_role) + '<div class="family">' + _e(r.get('family', '')) + '</div>'), ('状态', 'Status', lambda r: _status(r.get('status')))]
    if tests:
        content += '<h3>' + _bi('逐路径组间检验', 'Direct tests for each path') + '</h3>' + _table(tests, [('路径', 'Path', _path)] + common)
    if pairs:
        content += '<h3>' + _bi('两两组间差异', 'Pairwise group differences') + '</h3><p class="note">' + _bi('差值方向：第一组 − 第二组。95% 区间为逐项未校正区间，p 值另经 Holm 校正；不能根据区间是否跨零判断 Holm 校正后的检验结论。', 'Difference direction: first group − second group. The 95% intervals are individual, unadjusted intervals; p values are separately adjusted with Holm. Whether an interval includes zero does not determine the Holm-adjusted test conclusion.') + '</p>' + _table(pairs, [('路径 / 比较', 'Path / comparison', lambda r: _path(r) + '<small class="sub">' + _e(r.get('group1')) + ' − ' + _e(r.get('group2')) + '</small>'), ('差值', 'Difference', lambda r: _value(r.get('difference'))), ('95% 区间', '95% CI', lambda r: _ci(r, 'difference'))] + common)
    if not (omni or tables['group_paths'] or tests or pairs):
        content += '<p class="empty">' + _bi('本次运行未包含调节分析结果。', 'This run does not include moderator analysis results.') + '</p>'
    parts.append(_section('moderation', '03', '分类调节与组间比较', 'Categorical moderators and group comparisons', content))

    content = '<p class="note">' + _bi('查看改变工作相关设定后路径估计的变化。所有数值直接读取已保存的敏感性分析结果。', 'Inspect changes in path estimates under different working-correlation settings. All values are read from the saved sensitivity analysis.') + '</p>'
    content += _table(tables['sensitivity'], [('ρ / φ', 'ρ / φ', lambda r: _value(r.get('rho'), 2) + ' / ' + _value(r.get('phi'), 2)), ('路径', 'Path', _path), ('估计值', 'Estimate', lambda r: _value(r.get('estimate'))), ('95% 区间', '95% CI', _ci), ('较主分析变化', 'Change from primary', lambda r: _value(r.get('change_from_primary'))), ('状态', 'Status', lambda r: _status(r.get('status')))])
    if tables['moderator_sensitivity']:
        content += '<h3>' + _bi('整体调节检验的敏感性', 'Sensitivity of the overall moderator test') + '</h3>' + _table(tables['moderator_sensitivity'], [('ρ / φ', 'ρ / φ', lambda r: _value(r.get('rho'), 2) + ' / ' + _value(r.get('phi'), 2)), ('Δχ²', 'Δχ²', lambda r: _value(r.get('delta_chi_square'))), ('df', 'df', lambda r: _integer(r.get('df'))), ('原始 p', 'Raw p', lambda r: _value(r.get('p_raw'), p=True)), ('状态', 'Status', lambda r: _status(r.get('status')))])
    if tables['study_influence']:
        content += '<details><summary>' + _bi('逐研究剔除结果', 'Leave-one-study-out results') + '</summary><div>' + _table(tables['study_influence'], [('剔除研究', 'Omitted study', lambda r: _e(r.get('omitted_study'))), ('路径', 'Path', _path), ('估计值', 'Estimate', lambda r: _value(r.get('estimate'))), ('较主分析变化', 'Change from primary', lambda r: _value(r.get('change_from_primary'))), ('状态', 'Status', lambda r: _status(r.get('status')))]) + '</div></details>'
    parts.append(_section('sensitivity', '04', '结果对分析设定有多敏感', 'How sensitive are the results?', content))
    boundaries = [('路径反映相关性结构，不能仅凭本分析作出因果判断。', 'Paths describe association structures; this analysis alone does not establish causality.'), ('非显著结果不等于等效或“没有差异”；应结合估计值、区间和研究设计。', 'Nonsignificant results do not establish equivalence or “no difference”; consider estimates, intervals, and study design.'), ('完整流程尚缺系统模拟验证；实际推断仍取决于独立样本、完整相关矩阵及模型假设。', 'The full workflow lacks comprehensive simulation validation; inference depends on independent samples, complete correlation matrices, and model assumptions.')]
    content = '<ul class="boundaries">' + ''.join('<li>' + _bi(zh, en) + '</li>' for zh, en in boundaries) + '</ul>'
    if diagnostics:
        content += '<details id="run-notes" open><summary>' + _bi('本次运行的分析提示', 'Analysis notes for this run') + '</summary><div><p class="note">' + _bi('以下为本次分析保存的原始提示，帮助判断结果的适用范围；提示本身不代表分析失败。', 'These original notes were saved with this analysis and help define the scope of interpretation. Their presence alone does not mean the analysis failed.') + '</p><ul class="run-diagnostics">' + ''.join('<li lang="en">' + _e(item) + '</li>' for item in diagnostics) + '</ul></div></details>'
    parts.append(_section('interpretation', '05', '如何使用这些结果', 'Using these results', content))
    links = [('paths.csv', '路径结果 CSV', 'Path results CSV'), ('pooled_correlations.csv', '合并相关矩阵', 'Pooled correlation matrix'), ('stage1_models.csv', '模型比较 CSV', 'Model comparison CSV'), ('group_paths.csv', '分组路径 CSV', 'Group paths CSV'), ('moderator_path_tests.csv', '逐路径检验 CSV', 'Path tests CSV'), ('moderator_pairwise.csv', '两两比较 CSV', 'Pairwise tests CSV'), ('sensitivity.csv', '敏感性结果 CSV', 'Sensitivity CSV'), ('paths.pdf', '路径图 PDF', 'Path plot PDF'), ('REPRODUCE.md', '复现说明', 'Reproduction guide'), ('manifest.json', '运行记录与校验值', 'Run record and checksums'), ('sessionInfo.txt', '运行环境', 'Runtime environment')]
    content = '<p class="note">' + _bi('报告正文与森林图可独立离线阅读。以下链接需要保留同一运行文件夹中的对应文件；浏览器打印可另存为 PDF。', 'The report and forest plot work offline as a standalone file. Links below require the corresponding files in the same run folder. Use browser printing to save a PDF.') + '</p><div class="downloads">' + ''.join('<a download href="' + name + '">' + _bi(zh, en) + '</a>' for name, zh, en in links if (out / name).is_file() or name == 'manifest.json') + '</div>'
    parts.append(_section('downloads', '06', '带走结果，保留复现依据', 'Take your results with you', content))
    parts.append('<footer class="footer">Hierarchical MASEM · ' + _bi('由保存的结果生成。本报告不重新估计模型。', 'Generated from saved results. This report does not refit models.') + '</footer></main></body></html>')
    target = out / 'report.html'
    target.write_text('\n'.join(parts), encoding='utf-8')
    return target
