## Project Rules

- Do not modify the repository root `README.md` unless explicitly instructed by the user.

## Test

```
moon test --target all
```

## CLI E2E Test

### No Behavior Change

```
bash scripts/cli_test.sh && git diff --exit-code cli_test
```

### Expect Behavior Change

```
bash scripts/cli_test.sh
```

## Web E2E Test

### Playground

```
npm run test:playground
```

### Browser Extension

```
npm run test:extension
```
