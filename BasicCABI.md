This document describes the "Basic” C ABI for WebAssembly. As mentioned in README.md, it's not the only possible C ABI. It is the ABI that the clang/LLVM WebAssembly backend is currently using, and any other C or C++ compiler wishing to be ABI-compatible with it.

wasm32 is ILP32 and wasm64 is LP64. `float` and `double` map to wasm’s `f32` and `f64` respectively. Varargs is lowered to passing a pointer to an explicitly-allocated buffer. Single-element struct return values are returned by a normal wasm return value. TODO: Spell this all out in much more detail.

This is just an initial sketch of some content. Obviously, it would
be desirable to go into a lot more detail.

Eventually, some content from the design repo’s CAndC++.md should also be moved here.
