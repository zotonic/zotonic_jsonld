# W3C JSON-LD test fixtures

Source: https://github.com/w3c/json-ld-api/tree/ffdb326121ea89b7b8280e76a5caea923834bcef/tests
Upstream commit: `ffdb326121ea89b7b8280e76a5caea923834bcef` (recorded in the downloaded archive).
Retrieved: 2026-09-18, from the `main` archive.
Archive SHA-256: `5636f60ef926fab7f8180af808a9fcac23f4590fcf08dd2d6f1d355197e31f10`.

The complete upstream `tests` directory is included with unchanged file
contents, including manifests, fixtures, README, license notice and support
files. The upstream `index.html` symlink to `manifest.html` is materialized as
a regular file containing the same bytes as its target.
This SOURCE.md, LICENSE-W3C-BSD.txt and LICENSE-W3C-TEST-SUITE.txt are
additional local provenance and license files.

The upstream test suite has its own dual W3C Test Suite / W3C 3-clause BSD
licensing, as described in [LICENSE.md](LICENSE.md). Original notices remain
in the upstream README and other files. Full BSD terms are provided in
[LICENSE-W3C-BSD.txt](LICENSE-W3C-BSD.txt). These files are not relicensed under
the enclosing application's Apache-2.0 license.

`jsonld_w3c_tests` runs the applicable JSON-LD 1.1 expansion cases by default.
Other algorithm fixtures are retained for future test coverage; their presence
does not mean those algorithms are implemented or tested. The runner uses only
local fixture files and does not fetch network resources.

## License choice for this integration

Distributed under both the [W3C Test Suite License](LICENSE-W3C-TEST-SUITE.txt)
and the [W3C 3-clause BSD License](LICENSE-W3C-BSD.txt), as offered upstream.
This integration uses the BSD option for software development and regression
testing, in accordance with the [W3C dual-license policy](https://www.w3.org/copyright/test-suites-licenses/).
The local runner is not an authoritative W3C conformance suite; its results do
not certify conformance or imply W3C endorsement.
