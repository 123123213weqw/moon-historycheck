# Source and test statistics

Snapshot 2026-10-22.

| Category | Count |
|---|---:|
| production_nonblank_noncomment_lines | 1456 |
| domain_nonblank_noncomment_lines | 1218 |
| manual_test_declarations | 28 |
| generated_fixture_tests | 71 |
| test_declarations | 99 |
| cli_cases | 71 |

Production counts exclude dependencies, tests, generated fixtures, examples, documentation and builds. Domain count also excludes shared value infrastructure, explicit trait extensions and the CLI. Test declarations include generated golden cases; running those cases through the CLI does not create new independent requirements. Statistics alone do not establish competition acceptance.
