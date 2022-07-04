#!/usr/bin/env bash
cp target/release/roc ./roc # to be able to exclude "target" later in the tar command
tar -czvf $1 --exclude="target" --exclude="zig-cache" roc LICENSE LEGAL_DETAILS examples/hello-world crates/compiler/builtins/bitcode/src/ crates/roc_std