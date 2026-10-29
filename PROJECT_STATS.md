# Source and test statistics

Snapshot 2026-10-22.

| Category | Count |
|---|---:|
| production_nonblank_noncomment_lines | 1551 |
| domain_nonblank_noncomment_lines | 1313 |
| manual_test_declarations | 32 |
| generated_fixture_tests | 85 |
| test_declarations | 117 |
| cli_cases | 85 |

Production counts exclude dependencies, tests, generated fixtures, examples, documentation and builds. Domain count also excludes shared value infrastructure, explicit trait extensions and the CLI. Test declarations include generated golden cases; running those cases through the CLI does not create new independent requirements. Statistics alone do not establish competition acceptance.
