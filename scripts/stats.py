import json,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
production=[p for p in [*ROOT.glob('*.mbt'),*ROOT.glob('cmd/**/*.mbt')] if not p.name.endswith('test.mbt')]
domain=[p for p in production if p.parent==ROOT and p.name not in ['value.mbt','extensions.mbt']]
def lines(paths):return sum(1 for p in paths for s in p.read_text(encoding='utf-8').splitlines() if s.strip() and not s.lstrip().startswith('//'))
manual=sum(len(re.findall(r'^test ',p.read_text(encoding='utf-8'),re.M)) for p in ROOT.glob('*test.mbt') if p.name!='fixtures_wbtest.mbt')
fixtures=len(json.loads((ROOT/'tests/cases.json').read_text(encoding='utf-8')))
result={'production_nonblank_noncomment_lines':lines(production),'domain_nonblank_noncomment_lines':lines(domain),'manual_test_declarations':manual,'generated_fixture_tests':fixtures,'test_declarations':manual+fixtures,'cli_cases':fixtures,'production_files':[str(p.relative_to(ROOT)) for p in production]}
if __name__=='__main__':print(json.dumps(result,indent=2))
