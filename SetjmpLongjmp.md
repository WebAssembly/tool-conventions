# C setjmp/longjmp in WebAssembly

## Overview

This document describes a convention to implement C setjmp/longjmp via
[WebAssembly exception-handling proposal].

This document also briefly mentions another convention based on JavaScript
exceptions.

[WebAssembly exception-handling proposal]: https://github.com/WebAssembly/exception-handling

## Runtime ABI

### Linear memory structures

This convention uses a few structures on the WebAssembly linear memory.

#### Reserved area in jmp_buf

The first 6 words of C jmp_buf is reserved for the use by the runtime.
("words" here are C pointer types specified in the [C ABI].)
It should have large enough alignment to store C pointers.
The actual contents of this area are private to the runtime implementation.

[C ABI]: BasicCABI.md

##### Notes about the size of reserved area in jmp_buf

Emscripten has been using 6 `unsigned long`s. (`unsigned long [6]`)

GCC and Clang uses `intptr_t [5]` for their [setjmp/longjmp builtins].
It isn't relevant right now though, because LLVM's WebAssembly target
doesn't provide these builtins.

[setjmp/longjmp builtins]: https://gcc.gnu.org/onlinedocs/gcc/Nonlocal-Gotos.html

#### __WasmLongjmpArgs

An equivalent of the following structure is used to associate necessary
data to the WebAssembly exception.

```c
struct __WasmLongjmpArgs {
  void *env; // a pointer to jmp_buf
  int val;
};
```

The lifetime of this structure is rather short. It lives only during a
single longjmp execution.
A runtime can use a part of `jmp_buf` for this structure. It's also ok to use
a separate thread-local storage to place this structure. A runtime without
multi-threading support can simply place this structure in a global variable.

### Exception tag

This convention uses a WebAssembly exception to perform a non-local jump
for C `longjmp`.

The exception is created with an exception tag named `__c_longjmp`.
The name is used for both of [static linking](Linking.md) and
[dynamic linking](DynamicLinking.md).
The type of exception tag is `(param i32)`. (Or, `(param i64)` for [memory64])
The parameter is the address of the `__WasmLongjmpArgs` structure on the
linear memory.

[memory64]: https://github.com/WebAssembly/memory64

### Functions

```c
void __wasm_setjmp(jmp_buf env, uint32_t label, void *func_invocation_id);
uint32_t __wasm_setjmp_test(jmp_buf env, void *func_invocation_id);
void __wasm_longjmp(jmp_buf env, int val);
```

`__wasm_setjmp` records the necessary data in the `env` so that it can be
used by `__wasm_longjmp` later.
`label` is a non-zero identifier to distinguish setjmp call-sites within
the function. Note that a C function can contain multiple setjmp() calls.
`func_invocation_id` is the identifier to distinguish invocations of this
C function. Note that, when a C function which calls setjmp() is invoked
recursively, setjmp/longjmp needs to distinguish them.

`__wasm_setjmp_test` tests if the longjmp target belongs to the current
function invocation. if it does, this function returns the `label` value
saved by `__wasm_setjmp`. Otherwise, it returns 0.

`__wasm_longjmp` is similar to C `longjmp`.
If `val` is 0, it's `__wasm_longjmp`'s responsibility to convert it to 1.
It performs a long jump by filling a `__WasmLongjmpArgs` structure and
throwing an exception with its address. The exception is created with
the `__c_longjmp` exception tag.

## Code conversion

The C compiler detects `setjmp` and `longjmp` calls in a program and
converts them into the corresponding WebAssembly exception-handling
instructions and calls to the above mentioned runtime ABI.

### Functions calling setjmp()

On the function entry, the compiler would generate the logic to create
the identifier of this function invocation, typically by performing an
equivalent of `alloca(1)`. Note that the alloca size is not important
because the pointer is merely used as an identifier and never be dereferenced.

Also, the compiler converts C `setjmp` calls to `__wasm_setjmp` calls.

For each setjmp callsite, the compiler allocates non-zero identifier called
"label". The label value passed to `__wasm_setjmp` is recorded by the
runtime and returned by later `__wasm_setjmp_test` when processing a longjmp
to the corresponding jmp_buf.

Also, for code blocks which possibly call `longjmp` directly or indirectly,
the compiler generates instructions to catch and process exceptions with
the `__c_longjmp` exception tag accordingly.

When catching the exception, the compiler-generated logic calls
`__wasm_setjmp_test` to see if the exception is for this invocation
of this function.
If it is, `__wasm_setjmp_test` returns the non-zero label value recorded by
the last `__wasm_setjmp` call for the jmp_buf. The compiler-generated logic
can use the label value to pretend a return from the corresponding setjmp.
Otherwise, `__wasm_setjmp_test` returns 0. In that case, the
compiler-generated logic should rethrow the exception by calling
`__wasm_longjmp` so that it can be eventually caught by the right function.

For an example, a C function like this would be converted like
the following pseudo code.
```c
void f(void) {
  jmp_buf env;
  if (!setjmp(env)) {
    might_call_longjmp(env);
  }
}
```

```wat
  $func_invocation_id = alloca(1)

  ;; 100 is a label generated by the compiler
  call $__wasm_setjmp($env, 100, $func_invocation_id)

  block
    block (result i32)
      try_table (catch $__c_longjmp 0)
        call $might_call_longjmp
      end
      ;; might_call_longjmp didn't call longjmp
      br 1
    end
    ;; might_call_longjmp called longjmp
    pop __WasmLongjmpArgs pointer from the operand stack
    $env = __WasmLongjmpArgs.env
    $val = __WasmLongjmpArgs.val
    $label = $__wasm_setjmp_test($env, $func_invocation_id)
    if ($label == 0) {
      ;; not for us. rethrow.
      call $__wasm_longjmp($env, $val)
    }
    ;; ours.
    ;; somehow jump to the block corresponding to the $label
    ...
    ...
  end
```

### Longjmp calls

The compiler converts C `longjmp` calls to `__wasm_longjmp` calls.

## Dynamic-linking consideration

In case of [dynamic-linking], it's the dynamic linker's responsibility
to provide the exception tag for this convention with the name
"env.__c_longjmp". Modules should import the tag so that cross-module
longjmp works.

[dynamic-linking]: DynamicLinking.md

## Emscripten JavaScript-based exceptions

Emscripten has a mode to use JavaScript-based exceptions instead of
WebAssembly exceptions. In that mode, `emscripten_longjmp` function,
which throws a JavaScript exception, is used instead of `__wasm_longjmp`.

```c
void emscripten_longjmp(uintptr_t env, int val);
```

The compiler translates C function calls which possibly ends up with
calling `longjmp` to indirect calls via a JavaScript wrapper which
catches the JavaScript exception.

## Implementations

* LLVM (19 and later) has a pass ([WebAssemblyLowerEmscriptenEHSjLj.cpp])
  to perform the convertion mentioned above.  It can be enabled with the
  `-mllvm -wasm-enable-sjlj` option.

  Note: as of writing this, LLVM produces a bit older version of
  exception-handling instructions. (`try`, `delegate`, etc)
  binaryen has a conversion from the old instructions to the latest
  instructions. (`try_table` etc.)

* Emscripten (3.1.57 or later) has the runtime support ([emscripten_setjmp.c])
  for the convention documented above.

* wasi-libc has the runtime support ([wasi-libc rt.c]) for the convention
  documented above.

[WebAssemblyLowerEmscriptenEHSjLj.cpp]: https://github.com/llvm/llvm-project/blob/70deb7bfe90af91c68454b70683fbe98feaea87d/llvm/lib/Target/WebAssembly/WebAssemblyLowerEmscriptenEHSjLj.cpp

[emscripten_setjmp.c]: https://github.com/emscripten-core/emscripten/blob/7d66497d96cdcffa394ad67d87f7118137edf9ab/system/lib/compiler-rt/emscripten_setjmp.c

[wasi-libc rt.c]: https://github.com/WebAssembly/wasi-libc/blob/d03829489904d38c624f6de9983190f1e5e7c9c5/libc-top-half/musl/src/setjmp/wasm32/rt.c

## Future directions

* `__WasmLongjmpArgs` can be replaced with WebAssembly multivalue.

* Or, alternatively, we can make `__wasm_setjmp_test` take the
  `__WasmLongjmpArgs` pointer so that we can drop the `__WasmLongjmpArgs`
  structure layout from the ABI.

* It might be simpler for the complier-generated catching logic to rethrow
  the exception with the `rethrow`/`throw_ref` instruction instead of
  calling `__wasm_longjmp`. Or, it might be simpler to make
  `__wasm_setjmp_test` rethow the exception internally.

* If/When WebAssembly exception gets more ubiquitous, we might want to move
  the runtime to compiler-rt.
