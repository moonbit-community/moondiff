#!/bin/env bash

wasmer run ./target/wasm/release/build/tokendiff/cli/cli.wasm --dir "/" -- $@