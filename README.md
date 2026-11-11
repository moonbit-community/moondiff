# moondiff

Difftool that aware MoonBit language syntax.

Inspired by [difftastic](https://github.com/Wilfred/difftastic)

Review code with Moondiff Review: https://moondiff.moonbitlang.com/

The root `moon.work` contains only the review-web modules. To check and test the
standalone moondiff module from the repository root, run:

```sh
MOON_WORK=off moon check --target all
MOON_WORK=off moon test --target all
MOON_WORK=off moon fmt
MOON_WORK=off moon info
```

To format all four modules while preserving `moon.work` comments, run
`node scripts/fmt.mjs`.

See [review-web development](review-web/README.md#local-development) for the
published dependency policy and temporary local integration tests.
