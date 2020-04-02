This document describes the Swift ABI for WebAssembly. As mentioned in README, it's not the only possible Swift ABI. It is the ABI that the clang/LLVM WebAssembly backend is currently using, and any other Swift compiler wishing to be ABI-compatible with it.

Most parts of the ABI follow [the Swift ABI document in the official compiler repository](https://github.com/apple/swift/tree/master/docs/ABI)

This document only describes what is necessary to be treated specially on WebAssembly.

## Swift Calling Convention

Swift calling convention (`swiftcc` attribute in LLVM) is based on C calling convention as described [here](https://github.com/apple/swift/blob/master/docs/ABI/CallingConvention.rst)

Swiftcc on WebAssembly is a little different from swiftcc on other architectures.

On non-WebAssembly architectures, swiftcc accepts extra tail parameters that are attributed with swifterror or swiftself by a caller at the LLVM IR level and swifterror is always placed after swiftself. Even if the callee doesn't have these parameters at the LLVM IR level, the invocation succeeds by ignoring extra parameters.

But WebAssembly strictly checks that [callee and caller signatures are the same](https://github.com/WebAssembly/design/blob/master/Semantics.md#calls).
So at WebAssembly level, all swiftcc functions end up with extra arguments and all function definitions and invocations explicitly have additional tail parameters to fill swifterror and swiftself.

For example, Swift global function `func foo(_ value: Int)` is lowered as `func (param i32 i32 i32)` at WebAssembly level.

If you export swiftcc function and call it, you need the tail parameters. If the function did not have swiftself or swifterror at the IR level (and placeholders were added during lowering), then a placeholder may be passed any pointer size value. But if the embedding environment is JS, then missing params will be added as JS undefined and coerced to i32 as 0, so you don't need to fill them. This JS convention rule is documented at https://webassembly.github.io/spec/js-api/index.html
