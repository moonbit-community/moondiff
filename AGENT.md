## Test

```
moon test span
moon test elab
moon test astdiff
moon test tool
```

## E2E Test

### No Behavior Change

```
bash cli_test.sh && git diff --exit-code cli_test
```

### Expect Behavior Change

```
bash cli_test.sh
```