This document describes the "Basic" C ABI for WebAssembly. As mentioned in
[README](README.md), it's not the only possible C ABI. It is the ABI that the
clang/LLVM WebAssembly backend is currently using, and any other C or C++
compiler wishing to be ABI-compatible with it.


## Data Representation

**Scalar Types**

The ABI for the currently-specifed version of WebAssembly (also known as "wasm32") uses an "ILP32" data model, 
where `int`, `long`, and pointer types are 32 bits. It is expected that the proposed extension to allow memories
larger than 4GB ("wasm64") will use an "LP64" data model, where `int` and `long` are 64 bits.

The following table shows the memory sizes and alignments of C and C++ scalar types, and their
correspondence to types used in the WebAssembly specification:


General type | C Type | `sizeof` | Alignment (bytes) | Wasm Value Type
-|-|-|-|-
 Integer | `_Bool`/`bool` | 1 | 1 | i32
 Integer | `char`, `signed char` | 1 | 1 | i32
 Integer | `unsigned char` | 1 | 1 | i32
 Integer | `short` / `signed short` | 2 | 2 | i32
 Integer | `unsigned short` | 2 | 2 | i32
 Integer | `int` / `signed int` / `enum` | 4 | 4 | i32
 Integer | `unsigned int` | 4 | 4 | i32
 Integer | `long` / `signed long` | 4 | 4 | i32
 Integer | `unsigned long` | 4 | 4 | i32
 Integer | `long long` / `signed long long` | 8 | 8 | i64
 Integer | `unsigned long long` | 8 | 8 | i64
 Pointer | *`any-type *`* / *`any-type (*)()`* | 4 | 4 | i32
 Floating point | `float` | 4 | 4 | f32
 Floating point | `double` | 8 | 8 | f64
 Floating point | `long double` | 16 | 16 | (none)
 
 * `long double` values correspond to 128-bit quad-precision values, but they are represented
 as a pair of f64 values, and operations on these values are currently implemented as calls to
 compiler-rt library functions.
 * A null pointer (for all types) has the value zero
 * The `size_t` type is defined as `unsigned long`.
 
