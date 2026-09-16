`parser-836b5e03.json.gz` pins the public reproduction from
[moonbitlang/parser PR #183, commit 836b5e03](https://github.com/moonbitlang/parser/pull/183/changes/836b5e037954fee5e8b233aca8e3587621842875).
It contains GitHub file metadata/patches and the corresponding UTF-8 blobs from
commit `836b5e037954fee5e8b233aca8e3587621842875` and its parent
`30f2858607859b0df8dbe59974561e2e9e9ae5d4`. The browser tests use local RPC
responses and never contact GitHub. The ignored reproduction file occupies index
0 for stable selectors. The upstream license is in `parser-LICENSE`.

The JSON shape is `{ sha, base, message, files, sources }`; `sources` keys are
`SHA:path`. Compression uses gzip with mtime 0. `rendering.stress.mjs` uses this
parser fixture and independent synthetic fixtures with configurable file and
declaration counts. Run these separately with `npm run test:e2e:stress` from
`playground`; ordinary rendering regressions remain in `rendering.spec.mjs`.
