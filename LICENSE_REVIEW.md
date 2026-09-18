# License and attribution review

Checked on 2026-09-18. Scope: this application's source, test runners, vendored
fixtures, notices and declared non-OTP dependencies.

- All 7 Erlang source/test files have Marc Worrell's 2026 copyright and
  Apache-2.0 headers. The full Apache license and application metadata agree.
  The placeholder text in the Apache license's explanatory appendix is part of
  the standard license, not an unfinished project copyright notice.
- The implementation was written for Zotonic; no Elixir or Java implementation
  source was copied or transliterated. Reference projects and specifications
  are identified in [NOTICE](NOTICE) and [README.md](README.md).
- 2626 regular upstream files were compared byte-for-byte with commit
  `ffdb326121ea89b7b8280e76a5caea923834bcef` from the recorded archive.
  The additional `index.html` alias was verified against its upstream symlink
  target, `manifest.html`. Original notices are preserved.
- Fixture data remains separately licensed. Both W3C license texts are included;
  the BSD option is used for development testing. See
  [fixture provenance](test/data/w3c-jsonld/SOURCE.md).
- Declared dependencies `zotonic_rdf`, `jsxrecord`, `euneus` identify Apache-2.0 in their
  checked-out license files and application metadata. They are dependencies,
  not source copied into this application; this review does not replace their
  notices or audit a future release's complete transitive dependency graph.

When distributing fixtures, include their original notices and accompanying
license/provenance files. Regression results from the local runner are not a
W3C conformance certification or endorsement. No parser behavior was changed
by this review.
