# WebAssembly Exception Handling Scheme

This document describes the plans for a new exception handling scheme for
WebAssembly, and what each tool components does and how they interact with each
other to implement the scheme.

The exception handling support implemented in [WebAssembly upstream
backend](https://github.com/llvm-mirror/llvm/tree/master/lib/Target/WebAssembly)
and other tools ([binaryen](https://github.com/WebAssembly/binaryen/) and
[emscripten](https://github.com/kripken/emscripten)) as for Sep 2017 uses
library functions in asm.js, which is slow because there are many foreign
function calls between WebAssembly and JavaScript involved. A new, low-cost
WebAssembly exception support for WebAssembly has been
[proposed](https://github.com/WebAssembly/exception-handling/blob/master/proposals/Exceptions.md)
and is currently being implemented in V8 JavaScript engine.

Here we propose a new exception handling scheme for WebAssembly (hereafer called
Wasm exception handling scheme) for toolchain side to generate compatible Wasm
binary files to match the aforementioned [WebAssembly exception handling
proposal](https://github.com/WebAssembly/excption-handling/blob/master/proposals/Exceptions.md).

**The prototype implementation work is in progress, and is currently only
targeting C+.**


## Background

### WebAssembly try and catch Blocks

WebAssembly's `try` and `catch` instructions are structured as follows:
```
try
  instruction*
catch (C++ tag)
  instruction*
catch (Another language's tag)
  instruction*
...
catch_all
  instruction*
try_end
```
A `catch` instruction in WebAssembly does not correspond to a C++ `catch`
clause. **In WebAssembly, there is a single `catch` instruction for all C++
exceptions.** `catch` instruction for other languages ane `catch_all`
instructions are not generated for the current version of implementation. **All
`catch` clauses for various C++ types go into this big `catch (C++ tag)`
block.** Each language will have a tag number assigned to it, so you can think
C++ tag as a fixed integer here. So the simplified form will look like
```
try
  instruction*
catch (C++ tag)
  instruction*
try_end
```

So for example, if we have this C++ code:
```
try {
  foo(); // may throw
} catch (int n) {
  printf("int caught");
} catch (float f) {
  printf("float caught");
}
```

The resulting grouping of Wasm instructions will be, in pseudocode, like this:
```
try
  foo();
catch (C++ tag)
  if thrown exception is int
    printf("int caught");
  else if thrown exception is float
    printf("float caught");
  else
    throw exception to the caller
try_end
```

When a
[`throw`](https://github.com/WebAssembly/exception-handling/blob/master/proposals/Exceptions.md#throws)
instruction throws an exception within a `try` block or callees of it, the
control flow is transferred to `catch (C++)` instruction, after which the thrown
exception object is placed on top of Wasm value stack. This means, from user
code's point of view, `catch` instruction returns the thrown exception object.
For more information, refer to [Try and catch
blocks](https://github.com/WebAssembly/exception-handling/blob/master/proposals/Exceptions.md#try-and-catch-blocks)
section in the exception proposal.


### C++ Libraries

Here we only discuss C++ libraries because currenly we only support C++
exceptions , but every language that supports exceptions should have some kind
of libraries that play similar roles, which we can extend to support Wasm
exceptions once we add support for that language.

Two C++ runtime libraries participate in exception handling: [C++ ABI
library](https://clang.llvm.org/docs/Toolchain.html#c-abi-library) and [Unwind
library](https://clang.llvm.org/docs/Toolchain.html#unwind-library).

The C++ ABI library provides an implementation of the library portion of the
Itanium C++ ABI, covering both the [support functionality in the main Itanium
C++ ABI document](http://itanium-cxx-abi.github.io/cxx-abi/abi.html) and [Level
II of the exception handling
support](http://itanium-cxx-abi.github.io/cxx-abi/abi-eh.html#cxx-abi).
References to the functions and objects in this library are implicitly generated
by Clang when compiling C++ code. Broadly used implementations of this spec
include LLVM's [libc++abi](https://github.com/llvm-mirror/libcxxabi) and GNU
GCC's
[libsupc++](https://github.com/gcc-mirror/gcc/tree/master/libstdc%2B%2B-v3/libsupc%2B%2B).

The Unwind library provides a family of `_Unwind_*` functions implementing the
language-neutral stack unwinding portion of the Itanium C++ ABI ([Level
I](http://itanium-cxx-abi.github.io/cxx-abi/abi-eh.html#base-abi)). It is a
dependency of the C++ ABI library, and sometimes is a dependency of other
runtimes. GNU GCC's
[libgcc_s](https://github.com/gcc-mirror/gcc/tree/master/libgcc) has an
integrated unwinder. libunwind has a separate library for the unwinder and there
are several implementations including [LLVM's
libunwind](https://github.com/llvm-mirror/libunwind).

Our prototype implementation will be based on LLVM's
[libc++abi](https://github.com/llvm-mirror/libcxxabi) (also written as
libcxxabi) and [libunwind](https://github.com/llvm-mirror/libunwind). Although
libcxxabi and libunwind are specific implementations of [Itanium C++ exception
handling ABI](https://itanium-cxx-abi.github.io/cxx-abi/abi-eh.html), in this
document we will use them to denote C++ ABI library and Unwind library in
general, and the Wasm EH scheme can be also implemented in other library
implementations as well.


## Why New Exception Handing Scheme?

Currently there are several exception handling schemes supported by major
compilers such as GCC or LLVM. LLVM supports four kinds of EH schemes: Dwarf
CFI, SjLj, ARM, and WinEH. Then why do we need the support for a new EH scheme
in a compiler as well as libraries supporting C++ ABI?

The most different aspect about Wasm EH handling that necessiates a new EH
scheme is the way it unwinds stack. Because of security concerns, Wasm code is
not allowed to touch its execution stack by itself. When an exception is thrown,
the stack is unwound by not libunwind bug a JavaScript engine. This affects
various components of Wasm EH that will be discussed in detail hereafter in this
document.

The definition of an exception scheme can be different from a compiler's point
of view and that of libraries (libcxxabi / libunwind). LLVM currently supports
four EH schemes: Dwarf CFI, SjLj, ARMEH, and WinEH, among which all of them use
Itanium C++ ABI with an exception of WinEH. ARMEH resembles Dwarf CFI in many
ways other than a few architectural differences. Unwind libraries also implement
different unwinding mechanism for many architectures, each of which can be
considered as a separate scheme. In this document we mostly describe Wasm EH
scheme using comparisons with with two Itanium-based schemes: Dwarf CFI and
SjLj. Even though the unwinding process itself is very different, code
transformation required by compiler and the way libcxxabi and libunwind
communicates in part resemble that of SjLj exception handling scheme.


## Active Personality Function Call

### WebAssembly Stack Unwinding and Personality Function

For other schemes, stack unwinding is performed by libunwind: for example, DWARF
CFI scheme uses call frame information stored in DWARF format to access callers'
frames, whereas SjLj scheme traverses in-memory chain of structures recorded for
every `try` clause to find a matching one. And while these EH schemes examine
every possible call frame that can catch an exception, i.e., a call frame with
`try`-`catch` clauses, they call the _personality function_ in libcxxabi to
check if we need to stop at the current fall frame, in which case there is a
matching `catch` clause or cleanup actions to perform.

On the other hand, from Wasm code's point of view, after a
[`throw`](https://github.com/WebAssembly/exception-handling/blob/master/proposals/Exceptions.md#throws)
instruction within a try block throws an exception, the control flow is
magically transferred to a matching `catch` block, which returns an exception
object. So the unwinding process is completely hidden from Wasm code. That means
it's not possible to call the personality function from libunwind anymore.
**Unlike this process, Wasm unwinding process is performed by a JS engine, and
it stops at every call frame that has `catch (C++ tag)` instruction.**

For other EH schemes, after the personality functinon figures out which frame to
stop, it does three things:
* Sets IP to the start of a matching landing pad block.
* Gives the address of the thrown exception object.
* Gives the _selector value_ corresponding to the type of exception thrown.

Can Wasm EH get all this information without calling a personality function?
Program control flow is transferred to `catch (C++ tag)` by the unwinder in JS
engine automatically. (Wasm code cannot touch IP by itself anyway.) Wasm `catch`
instruction's result is the address of a thrown object. **But we cannot get a
selector without calling a personality function.**

So we need to call the personality function _actively_ from the Wasm code to
compute a selector value. To do that, Wasm compiler inserts a call to the
personality function at the start of each landing pad.


### Code Transformation

In other EH schemes based on Itanium C++ ABI, C++'s `throw` keyword is compiled
into a call to
[`__cxa_throw`](https://github.com/llvm-mirror/libcxxabi/blob/master/src/cxa_exception.cpp#L207)
function, which calls
[`_Unwind_RaiseException`](https://github.com/llvm-mirror/libunwind/blob/master/src/UnwindLevel1.c#L341)
(in Dwarf CFI scheme) or
[`_Unwind_SjLj_RaiseException`](https://github.com/llvm-mirror/libunwind/blob/master/src/Unwind-sjlj.c#L279)
(in SjLj scheme) to start an unwinding process. These
[`_Unwind_RaiseException`](https://github.com/llvm-mirror/libunwind/blob/master/src/UnwindLevel1.c#L341)
 /
 [`_Unwind_SjLj_RaiseException`](https://github.com/llvm-mirror/libunwind/blob/master/src/Unwind-sjlj.c#L279)
functions performs the actual stack unwinding process and calls the personality
function for each eligible call frame. You can see libcxxabi's personality
function implementation
[here](https://github.com/llvm-mirror/libcxxabi/blob/caa78daf9285dada17e3e6b8aebcf7d128427f83/src/cxa_personality.cpp#L936).
As discussed above Wasm does not do
unwinding by itself, the compiler inserts a call to a personality function,
more precisely, a _wrapper_ to the personality function after Wasm `catch`
instruction, passing the thrown exception object returned from the `catch`
instruction. The wrapper function lives in libunwind, and its signature will be
```
_Unwind_Reason_Code _Unwind_CallPersonality(void *exception_ptr);
```

Even though the signature looks simple, we use an auxiliary struct to pass more
information to the personality and retrieve a selector computed after it
returns. It is used as a communication channel: we set input parameters within
the structure before calling the wrapper function, and reads output parameters
after the personality function returns. This structure lives in libunwind and
this is how it looks like:
```
struct _Unwind_LandingPadContext {
  // Input information to personality function
  uintptr_t lpad_index;
  __personality_routine personality;
  uintptr_t lsda;

  // Output information computed by personality function
  uintptr_t selector;
};

// Communication channel between Wasm code and personality function
struct _Unwind_LandingPadContext __wasm_landingpad_context = ...;

// Personality function wrapper
_Unwind_Reason_Code _Unwind_CallPersonality(void *exception_ptr) {
 struct _Unwind_Exception *exception_obj =
     (struct _Unwind_Exception *) exception_ptr;
 _Unwind_Reason_Code ret =
     (*__wasm_lpad_context->personality)(1, _UA_CLEANUP_PHASE,
                                         exception_obj->exception_class,
                                         exception_obj,
                                         (struct _Unwind_Context *)
                                         __wasm_lpad_context);
 return ret;
}
```

As you can see in the code above, here's the list of input and output parameters
communicated by `__wasm_landingpad_context`:
* Input parameters
  * Landing pad index
  * Personality function address
  * LSDA (exception handling table) address
* Output parameters
  * Selector value

These three input parameters are not directly passed to the personality function
as arguments, but are read from it using various `_Unwind_Get***` functions
exported by libunwind. The output parameter, a selector value is also not
directly returned by the personality function but will be set using
`_Unwind_SetGR` function. (`SetGR` here means setting a general register, and it
does set a physical register in Dwarf CFI. But for SjLj and Wasm schemes it sets
some field in a struct instead. Same for `_Unwind_GetGR`.)

When looking for a matching catch clause in each call frame, what a personality
function does is querying the call site table within the current function's LSDA
(Language Specipic Data Area), also known as exception handling table or
`gcc_except_table`, with a call site information. For example, the table answers
queries such as "If an exception is thrown at this call site, which action table
entry should I check?" In Dwarf CFI scheme, the offset of actual callsite
relative to function start is used as callsite information. In SjLj scheme, each
callsite that can throw has an index starting from 0, and the index serves as
callsite information to query the action table. In Wasm EH scheme, because a
call to the personality function wrapper is inserted at the position of each
landing pad, we give each landing pad an index starting from 0 and use this as
callsite information.  We also need to pass the address of the personality
function associated with the current function so that the wrapper can call it.
The address of LSDA for the current function is also required because the
personality function examines the tables there to look for a matching `catch`
clause.

Putting it all together, the compiler inserts this code snippet at the beginning
of each landing pad. (This is C-style pseudocode; the real code inserted will
be in some IR or assembly level.)
```
// Gets a thrown exception object
void *exn = catch(0); // Wasm catch instruction

// Set input parameters
__wasm_landingpad_context.lpad_index = index;
__wasm_landingpad_context.personality = __gxx_personality_v0;
__wasm_landingpad_context.lsda = &GCC_except_table0; // LSDA address of function

// Call personality wrapper function
_Unwind_CallPersonality(exn);

// Retrieve output parameter
int selector = __wasm.landingpad_context.selector;

// use exn and selector hereafter
```

### You Shouldn't Prune Unreachable Resumes

Suppose you have this code:
```
try {
  foo(); // may throw
} catch (int n) {
  ...
}

some code...
```
In this code, when the type of a thrown exception is not int, the exception is
rethrown to the caller. The possible CFG structure for this code is
```
try:
  foo();
  if exception occured go to lpad, or else go to try.cont

lpad: // landing pad block
  if type of exception is int go to catch, or else go to eh.resume

catch:
  catch int type exception

eh.resume: // resume block!
  rethrow exception to caller

cont:
  some code...
```

Some compilers, such as LLVM,
[prunes](https://github.com/llvm-mirror/llvm/blob/c1e866c7f106668016372d945e397d2b003c6c84/lib/CodeGen/DwarfEHPrepare.cpp#L132)
basic blocks like `eh.resume` in the code above, considering it unreachable,
which holds true in other EH schemes, because if there is neither matching
`catch` clause nor cleanup actions (such as calling destructors to
stack-allocated objects) to do, the unwinder does not even stops at this call
frame. But as we mentioned earlier, Wasm unwinding is done by JS engine and it
stops at every call frame that has Wasm `catch` instruction, i.e., every call
frame with try-catch clauses.



## One-Phase Unwinding


## LSDA Information


### Base ABI


### C++ ABI


## Exception Structure Recovery


## Wasm C++ Exception Handling ABI

