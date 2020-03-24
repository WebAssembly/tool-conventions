This document describes the Swift ABI for WebAssembly. As mentioned in README, it's not the only possible Swift ABI. It is the ABI that the clang/LLVM WebAssembly backend is currently using, and any other Swift compiler wishing to be ABI-compatible with it.

Most parts of the ABI follow [the Swift ABI document in the official compiler repository](https://github.com/apple/swift/tree/master/docs/ABI)

This document only describes what is necessary to be treated specially on WebAssembly.

## Swift Calling Convention

Swift calling convention (`swiftcc` attribute in LLVM) is based on C calling convention as described [here](https://github.com/apple/swift/blob/master/docs/ABI/CallingConvention.rst)

Swiftcc on WebAssembly is a little deffer from swiftcc on another architectures.

On non WebAssembly arch, swiftcc accepts extra parameters that are attributed with swifterror or swiftself by caller. Even if callee doesn't have these parameters, the invocation succeed ignoring extra parameters.

But WebAssembly strictly checks that [callee and caller signatures are same](https://github.com/WebAssembly/design/blob/master/Semantics.md#calls).
So at WebAssembly level, all swiftcc functions end up extra arguments and all function definitions and invocations explicitly have additional parameters to fill swifterror and swiftself.

For example, Swift global function `func foo(_ value: Int)` is lowered as `func (param i32 i32 i32)` at WebAssembly level.

If you export swiftcc function and call it, you maybe need to pass additional parameters to fill them. It's OK to fill the placeholder with any pointer size value.
