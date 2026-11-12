# moondiff

Difftool that aware MoonBit language syntax.

Inspired by [difftastic](https://github.com/Wilfred/difftastic)

Review code with Moondiff Review: https://moondiff.moonbitlang.com/

The review app workspace is defined in `review-web/moon.work`. To check and test
the standalone moondiff module from the repository root, run:

```sh
moon check --target all
moon test --target all
moon fmt
moon info
```

To format all four modules while preserving `moon.work` comments, run
`node scripts/fmt.mjs`.

See [review-web development](review-web/README.md#local-development) for the
published dependency policy and temporary local integration tests.
