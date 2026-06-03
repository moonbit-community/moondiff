## Test

```
bash scripts/regular_test.sh
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