"""Standard-library presentation and safety checks for the offline report.

Run: python3 -m unittest discover -s skills/hierarchical-masem/tests -p test_report.py
"""
import csv
import hashlib
from html.parser import HTMLParser
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


MODULE_PATH = Path(__file__).resolve().parents[1] / 'scripts/report.py'
SPEC = importlib.util.spec_from_file_location('masem_report', MODULE_PATH)
REPORT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(REPORT)


class Tags(HTMLParser):
    def __init__(self, text):
        super().__init__()
        self.elements = []
        self.feed(text)

    def handle_starttag(self, tag, attrs):
        self.elements.append((tag, dict(attrs)))


class ReportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.out = Path(self.temp.name)
        (self.out / 'inputs').mkdir()
        self.result = dict(status='complete_with_diagnostics', n_studies=6, n_samples=8,
                           n_total=1480, stage1_model='CS_CS', failed_interval_count=0,
                           stage2=dict(status='ok', fit=dict(saturated=True, df=0)))
        self.config = dict(variables=['X', 'Y'], moderation={'mode': 'planned'})
        self.paths = [dict(path='b_x', predictor='X', outcome='Y', estimate='0.123456789',
                           se='0.03', ci_lower='0.023456789', ci_upper='0.223456789', ci_status='ok')]
        self.models = [dict(model='CS_CS', AIC='-24.12345678', BIC='-20.5', parameters='3', status='ok', selected='TRUE')]
        self.save_base()

    def json(self, name, value):
        (self.out / name).write_text(json.dumps(value, ensure_ascii=False), encoding='utf-8')

    def csv(self, name, rows, fields=None):
        fields = fields or list(dict.fromkeys(key for row in rows for key in row))
        with (self.out / name).open('w', encoding='utf-8', newline='') as stream:
            writer = csv.DictWriter(stream, fields)
            writer.writeheader()
            writer.writerows(rows)

    def save_base(self):
        self.json('results.json', self.result)
        self.json('inputs/config.json', self.config)
        self.csv('paths.csv', self.paths)
        self.csv('stage1_models.csv', self.models)

    def render(self):
        path = REPORT.write_html_report(self.out)
        self.assertEqual(path, self.out / 'report.html')
        return path.read_text(encoding='utf-8')

    def test_bilingual_and_print_ready_without_javascript(self):
        text = self.render()
        for label in ('合并路径与不确定性', 'Pooled paths and uncertainty', '中文', 'English',
                      '非显著结果不等于等效', 'Nonsignificant results do not establish equivalence',
                      '不能仅凭本分析作出因果判断', 'this analysis alone does not establish causality'):
            self.assertIn(label, text)
        self.assertIn('#lang-en:checked~.shell .zh', text)
        self.assertIn('@media print', text)
        self.assertIn('lang="zh-Hans"', text)
        self.assertIn('lang="en"', text)
        self.assertFalse(any(tag == 'script' for tag, _ in Tags(text).elements))

    def test_exact_values_preserved_and_no_new_statistics(self):
        text = self.render()
        self.assertIn('title="0.123456789">0.123</span>', text)
        self.assertIn('title="0.023456789">0.023</span>', text)
        self.assertIn('title="-24.12345678">-24.123</span>', text)
        self.assertIn('<strong>1,480</strong>', text)
        self.assertIn('CS / CS', text)
        self.assertIn('0.123456789 [0.023456789, 0.223456789]', text)

    def test_malicious_labels_are_text_never_markup(self):
        attack = '</script><img src=x onerror="alert(1)"> & \' " >'
        self.paths[0].update(path=attack, predictor=attack, outcome=attack)
        self.models[0]['model'] = attack
        self.result['stage1_model'] = attack
        self.save_base()
        self.csv('group_paths.csv', [dict(self.paths[0], group=attack)])
        self.csv('moderator_pairwise.csv', [dict(path=attack, group1=attack, group2=attack,
                  difference='.1', ci_lower='-.1', ci_upper='.3', ci_status='ok',
                  p_raw='.2', p_holm='.4', family=attack, status='ok')])
        self.csv('study_influence.csv', [dict(omitted_study=attack, path=attack, estimate='.1', status='ok')])
        text = self.render()
        self.assertNotIn(attack, text)
        self.assertIn('&lt;img src=x onerror=&quot;alert(1)&quot;&gt;', text)
        for tag, attrs in Tags(text).elements:
            self.assertNotIn(tag, ('img', 'script', 'iframe', 'object'))
            self.assertFalse(any(key.lower().startswith('on') for key in attrs))

    def test_synthetic_data_is_conspicuously_labeled(self):
        self.config['data_role'] = 'synthetic_software_example'
        self.save_base()
        text = self.render()
        self.assertIn('alert demo', text)
        self.assertIn('软件演示 · 合成数据', text)
        self.assertIn('It is not research evidence.', text)

    def test_synthetic_role_prefix_is_case_insensitive_in_either_source(self):
        for container in (self.config, self.result):
            for role in ('synthetic', 'SYNTHETIC_software_tests', 'Synthetic-software-example'):
                with self.subTest(source='config' if container is self.config else 'results', role=role):
                    container['data_role'] = role
                    self.save_base()
                    self.assertIn('alert demo', self.render())
            container.pop('data_role')
        self.config['data_role'] = 'syntheticity_is_not_a_prefix_match'
        self.save_base()
        self.assertNotIn('alert demo', self.render())

    def test_failed_ci_is_not_plotted_as_valid_even_with_numeric_bounds(self):
        self.paths.append(dict(self.paths[0], path='failed_path', predictor='FAILED', ci_status='failed'))
        self.save_base()
        text = self.render()
        self.assertEqual(text.count('class="valid-interval"'), 1)
        self.assertEqual(text.count('class="estimate-dot"'), 1)
        self.assertIn('存在失败或缺失的区间', text)
        self.assertIn('CI failed or missing', text)
        self.assertIn('class="ci-missing"', text)

    def test_missing_nonfinite_reversed_or_outside_bounds_are_not_valid(self):
        for updates in ({'ci_lower': ''}, {'ci_upper': 'NaN'}, {'ci_lower': '.4'},
                        {'estimate': '.5'}, {'status': 'failed'}, {'ci_status': 'unknown'}):
            with self.subTest(updates=updates):
                self.csv('paths.csv', [dict(self.paths[0], **updates)])
                text = self.render()
                self.assertNotIn('class="valid-interval"', text)
                self.assertNotIn('class="estimate-dot"', text)
                self.assertIn('No valid intervals to plot.', text)

    def test_optional_missing_or_empty_tables_and_missing_moderator(self):
        absent = self.render()
        self.assertIn('This run does not include moderator analysis results.', absent)
        for name in ('group_paths', 'moderator_path_tests', 'moderator_pairwise', 'sensitivity', 'study_influence', 'moderator_sensitivity'):
            self.csv(name + '.csv', [], fields=['path', 'status'])
        # Empty files still deserve download links; the analysis content is
        # identical whether an optional table is absent or has only a header.
        self.assertEqual(absent.split('<section id="downloads">')[0],
                         self.render().split('<section id="downloads">')[0])

    def test_empty_primary_results_are_not_called_complete(self):
        self.csv('paths.csv', [], fields=['path', 'estimate', 'ci_lower', 'ci_upper', 'ci_status'])
        text = self.render()
        self.assertIn('Primary path results are incomplete', text)
        self.assertNotIn('class="valid-interval"', text)

    def test_failed_primary_fit_does_not_validate_its_numeric_intervals(self):
        self.result['stage2']['status'] = 'failed'
        self.save_base()
        text = self.render()
        self.assertIn('Primary path results are incomplete', text)
        self.assertNotIn('class="valid-interval"', text)

    def test_raw_holm_roles_families_and_difference_direction(self):
        self.json('moderator_omnibus.json', dict(role='exploratory', omnibus=dict(delta_chi_square='3.25', df=2, p_raw='.196911', status='ok'), groups={'g1': dict(group='A', n_studies=3, n_samples=4, n=700)}))
        row = dict(path='b_x', delta_chi_square='4.02', df=1, p_raw='.0451234', p_holm='.0902468', family='all_requested_path_tests', analysis_role='planned', status='ok')
        self.csv('moderator_path_tests.csv', [row])
        pair = dict(row, group1='A', group2='B', difference='-.12', ci_lower='-.25', ci_upper='.01', ci_status='ok', family='all_requested_pairwise_tests', analysis_role='exploratory')
        self.csv('moderator_pairwise.csv', [pair])
        text = self.render()
        for expected in ('Holm p', 'Raw p', 'Exploratory', 'Planned', 'all_requested_path_tests', 'all_requested_pairwise_tests', 'first group − second group', 'title=".0451234">0.045', 'title=".0902468">0.090', 'they do not verify preregistration', '逐项未校正区间', 'individual, unadjusted intervals', 'does not determine the Holm-adjusted test conclusion'):
            self.assertIn(expected, text)

    def test_sensitivity_values_and_failures_are_visible(self):
        self.csv('sensitivity.csv', [dict(path='b_x', rho='.5', phi='.5', estimate='.18', ci_lower='.05', ci_upper='.3', ci_status='failed', change_from_primary='.056543211', status='ok')])
        self.csv('moderator_sensitivity.csv', [dict(rho='.5', phi='.5', delta_chi_square='8.12345', df=2, p_raw='.01721', status='ok')])
        self.csv('study_influence.csv', [dict(path='b_x', omitted_study='study_9', estimate='.1', change_from_primary='-.023456789', status='failed')])
        text = self.render()
        self.assertIn('title=".056543211">0.057', text)
        self.assertIn('title="8.12345">8.123', text)
        self.assertIn('study_9', text)
        self.assertIn('Not successful', text)
        self.assertIn('Some confidence intervals failed or are missing', text)

    def test_saved_diagnostics_are_visible_escaped_and_not_failures(self):
        attack = '<img src="x" onerror="alert(1)"> & boundary'
        self.result['diagnostics'] = ['Fewer than ten studies.', attack]
        self.save_base()
        text = self.render()
        self.assertIn('href="#run-notes"', text)
        self.assertIn('Analysis notes available', text)
        self.assertIn('本次运行的分析提示', text)
        self.assertIn('Analysis notes for this run', text)
        self.assertIn('<li lang="en">Fewer than ten studies.</li>', text)
        self.assertIn('&lt;img src=&quot;x&quot; onerror=&quot;alert(1)&quot;&gt; &amp; boundary', text)
        self.assertNotIn(attack, text)
        self.assertNotIn('Some confidence intervals failed or are missing', text)
        self.assertNotIn('Not successful', text)
        self.assertEqual(text.count('class="valid-interval"'), 1)
        self.assertFalse(any(tag == 'img' for tag, _ in Tags(text).elements))
        self.result.pop('diagnostics')
        self.save_base()
        text = self.render()
        self.assertNotIn('href="#run-notes"', text)
        self.assertNotIn('id="run-notes"', text)

    def test_no_external_assets_or_dynamic_file_urls(self):
        self.config['data_file'] = 'https://untrusted.example/data.csv'
        self.config['title'] = 'javascript:alert(1)'
        self.save_base()
        (self.out / 'paths.pdf').write_bytes(b'%PDF-test')
        (self.out / 'REPRODUCE.md').write_text('Reproduce')
        text = self.render()
        self.assertNotIn('url(', text)
        self.assertNotIn('https://untrusted.example', text)
        hrefs = []
        for tag, attrs in Tags(text).elements:
            self.assertNotIn(tag, ('script', 'link', 'iframe', 'img'))
            self.assertNotIn('src', attrs)
            if 'href' in attrs:
                hrefs.append(attrs['href'])
                self.assertFalse(attrs['href'].startswith(('http:', 'https:', 'javascript:', '//', '/', 'file:')))
        self.assertIn('paths.pdf', hrefs)
        self.assertIn('REPRODUCE.md', hrefs)
        self.assertNotIn('group_paths.csv', hrefs)
        self.assertIn('<svg', text)
        self.assertIn('<style>', text)

    def test_rendering_is_deterministic_and_preserves_source_files(self):
        hashes = {p: hashlib.sha256(p.read_bytes()).hexdigest() for p in self.out.rglob('*') if p.is_file()}
        first = self.render()
        self.assertEqual(first, self.render())
        for path, checksum in hashes.items():
            self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), checksum)

    def test_missing_required_source_is_an_error_not_an_invented_result(self):
        (self.out / 'results.json').unlink()
        with self.assertRaises(FileNotFoundError):
            self.render()


if __name__ == '__main__':
    unittest.main()
