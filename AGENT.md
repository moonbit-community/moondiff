## Test

```
moon test --target all
```

## E2E Test

### No Behavior Change

```
bash scripts/cli_test.sh && git diff --exit-code cli_test
```

### Expect Behavior Change

```
bash scripts/cli_test.sh
```