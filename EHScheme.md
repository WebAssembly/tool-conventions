# WebAssembly Exception Handling Scheme

This document describes the plans for a new exception handling scheme for
WebAssembly, regarding what each tool components does and how they interact with
each other to implement the scheme.

The exception handling support implemented in [WebAssembly upstream backend in
LLVM](https://github.com/llvm-mirror/llvm/tree/master/lib/Target/WebAssembly)
and other tools ([binaryen](https://github.com/WebAssembly/binaryen/) and
[emscripten](https://github.com/kripken/emscripten)) as for Sep 2017 uses
library functions in asm.js, which is slow because there are many foreign
function calls between WebAssembly and JavaScript involved. A new, low-cost
WebAssembly exception support for WebAssembly has been
[proposed](https://github.com/WebAssembly/exception-handling/blob/master/proposals/Exceptions.md)
and is currently being implemented in V8.

Here we propose a new exception handling scheme for WebAssembly for the
toolchain side to generate compatible wasm binary files to support the
aforementioned [WebAssembly exception handling
proposal](https://github.com/WebAssembly/excption-handling/blob/master/proposals/Exceptions.md).

This spec is tentative and may change in future. The prototype implementation
work is in progress, and is currently only targeting C++ based on Itanium C++
ABI. This document assumes you have general knowledge about Itanium C++ ABI
based exception handling.

---

## Background

### WebAssembly try and catch Blocks

_Disclaimer: Some Changes to the current spec have been
[proposed](https://github.com/WebAssembly/exception-handling/issues/29), so this
section may change in the future._

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
exceptions.** `catch` instruction with tags for other languages and `catch_all`
instructions are not generated for the current version of implementation. **All
catch clauses for various C++ types go into this big `catch (C++ tag)` block.**
Each language will have a tag number assigned to it, so you can think the C++
tag as a fixed integer here. So the structure for the prototype will look like
```
try
  instruction*
catch (C++ tag)
  instruction*
try_end
```

So for example, if we have this C++ code:
```cpp
try {
  foo(); // may throw
} catch (int n) {
  printf("int caught");
} catch (float f) {
  printf("float caught");
}
```

The resulting grouping of WebAssembly instructions will be, in pseudocode, like
this:
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
instruction throws an exception within a `try` block or functions called from
it, the control flow is transferred to `catch (C++ tag)` instruction, after
which the thrown exception object is placed on top of WebAssembly value stack.
This means, from user code's point of view, `catch` instruction returns the
thrown exception object. For more information, refer to [Try and catch
blocks](https://github.com/WebAssembly/exception-handling/blob/master/proposals/Exceptions.md#try-and-catch-blocks)
section in the exception proposal.


### C++ Libraries

Here we only discuss C++ libraries because currenly we only support C++
exceptions, but every language that supports exceptions should have some kind of
libraries that play similar roles, which we can extend to support WebAssembly
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

The unwind library provides a family of `_Unwind_*` functions implementing the
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
libcxxabi) and [libunwind](https://github.com/llvm-mirror/libunwind).


## Why New Exception Handing Scheme?

Currently there are several exception handling schemes supported by major
compilers such as GCC or LLVM. LLVM supports four kinds of exception handling
schemes: Dwarf CFI, SjLj (setjmp/longjmp), ARM (EABI), and WinEH. Then why do we
need the support for a new exception handling scheme in a compiler as well as
libraries supporting C++ ABI?

The most distinguished aspect about WebAssembly EH that necessiates a new
exception handling scheme is WebAssembly code is not allowed to inspect or
modify the call stack, and cannot jump indirectly.  As a result, when an
exception is thrown, the stack is unwound by not the unwind library but the VM.
This affects various components of WebAssembly EH that will be discussed in
detail in this document.

The definition of an exception handling scheme can be different when defined
from a compiler's point of view and when from libraries. LLVM currently supports
four exception handling schemes: Dwarf CFI, SjLj, ARMEH, and WinEH, where all of
them use Itanium C++ ABI with an exception of WinEH. ARMEH resembles Dwarf CFI
in many ways other than a few architectural differences. Unwind libraries
implement different unwinding mechanism for many architectures, each of which
can be considered as a separate scheme. We will refer to the WebAssembly
exception handling scheme as WebAssembly EH in short in this document.

In this document we mostly describe WebAssembly EH using comparisons with with
two Itanium-based schemes: Dwarf CFI and SjLj. Even though the unwinding process
itself is very different, code transformation required by compiler and the way
C++ ABI library and unwind library communicate partly resemble that of SjLj
exception handling scheme.

---

## Direct Personality Function Call

### Stack Unwinding and Personality Function

For other schemes, stack unwinding is performed by the unwind library: for
example, DWARF CFI scheme uses call frame information stored in DWARF format to
access callers' frames, whereas SjLj scheme traverses in-memory chain of
structures recorded for every try clause to find a matching catch site. And at
every call frame with try-catch clauses, these exception handling schemes call
the _personality function_ in the C++ ABI library to check if we need to stop at
the call frame, in which case there is a matching catch site or cleanup actions
to perform.

**Unlike this process, WebAssembly unwinding process is performed by a VM, and
it stops at every call frame that has `catch (C++ tag)` instruction.** From
WebAssembly code's point of view, after a
[`throw`](https://github.com/WebAssembly/exception-handling/blob/master/proposals/Exceptions.md#throws)
instruction within a try block throws, the control flow is magically transferred
to a corresponding `catch (C++ tag)` instruction, which returns an exception
object. So the unwinding process is completely hidden from WebAssembly code,
which means the personality function cannot be called before control returns to
the compiler-generated user code.

For example, in Dwarf CFI scheme, after the personality function figures out
which frame to stop, the function does three things (in SjLj scheme the
personality function doesn't do the landing pad setting because it uses
`longjmp`):
* Sets IP to the start of a matching landing pad block (so that the unwinder
will jump to this block after the personality routine returns).
* Gives the address of the thrown exception object.
* Gives the _selector value_ corresponding to the type of exception thrown.

Can WebAssembly EH get all this information without calling a personality
function? Program control flow is transferred to `catch (C++ tag)` instruction
by the unwinder in a VM; WebAssembly code cannot access or modify IP.
WebAssembly `catch` instruction's result is the address of a thrown object.
**But we cannot get a selector without calling a personality function.** In
WebAssembly EH, the personality function is _directly_ called from the
compiler-generated user code rather than from the unwind library. To do that,
WebAssembly compiler inserts a call to the personality function at the start of
each landing pad.


### Landing Pad Code

In exception handling schemes based on Itanium C++ ABI, C++ `throw` keyword is
compiled into a call to
[`__cxa_throw`](https://github.com/llvm-mirror/libcxxabi/blob/05ba3281482304ae8de31123a594972a495da06d/src/cxa_exception.cpp#L210)
function, which calls
[`_Unwind_RaiseException`](https://github.com/llvm-mirror/libunwind/blob/469bacd2ea64679c15bb4d86adf000f2f2c27328/src/UnwindLevel1.c#L341)
(in Dwarf CFI scheme) or
[`_Unwind_SjLj_RaiseException`](https://github.com/llvm-mirror/libunwind/blob/469bacd2ea64679c15bb4d86adf000f2f2c27328/src/Unwind-sjlj.c#L279)
(in SjLj scheme) to start an unwinding process. These
[`_Unwind_RaiseException`](https://github.com/llvm-mirror/libunwind/blob/469bacd2ea64679c15bb4d86adf000f2f2c27328/src/UnwindLevel1.c#L341)
/
[`_Unwind_SjLj_RaiseException`](https://github.com/llvm-mirror/libunwind/blob/469bacd2ea64679c15bb4d86adf000f2f2c27328/src/Unwind-sjlj.c#L279)
functions performs the actual stack unwinding process and calls the personality
function for each eligible call frame. You can see libcxxabi's personality
function implementation
[here](https://github.com/llvm-mirror/libcxxabi/blob/05ba3281482304ae8de31123a594972a495da06d/src/cxa_personality.cpp#L936).

As discussed above, in WebAssembly EH stack unwinding is not done by the unwind
library, the compiler inserts a call to a personality function, more precisely,
a _wrapper_ to the personality function after WebAssembly `catch` instruction,
passing the thrown exception object returned from the `catch` instruction. The
wrapper function lives in the unwind library, and its signature will be
```cpp
_Unwind_Reason_Code _Unwind_CallPersonality(void *exception_ptr);
```

Even though the wrapper signature looks simple, we use an auxiliary data
structure to pass more information from the compiler-generated user code to the
personality function and retrieve a selector computed after the function
returns. The structure is used as a communication channel: we set input
parameters within the structure before calling the wrapper function, and reads
output parameters after the function returns. This structure lives in the unwind
library and this is how it looks like:
```cpp
struct _Unwind_LandingPadContext {
  // Input information to personality function
  uintptr_t lpad_index;                // landing pad index
  __personality_routine personality;   // personality function
  uintptr_t lsda;                      // LSDA address

  // Output information computed by personality function
  uintptr_t selector;       // selector value, used to select a C++ catch clause
};

// Communication channel between WebAssembly code and personality function
struct _Unwind_LandingPadContext __wasm_lpad_context = ...;

// Personality function wrapper
_Unwind_Reason_Code _Unwind_CallPersonality(void *exception_ptr) {
  struct _Unwind_Exception *exception_obj =
      (struct _Unwind_Exception *)exception_ptr;

  // Call personality function
  _Unwind_Reason_Code ret = (*__wasm_lpad_context->personality)(
      1, _UA_CLEANUP_PHASE, exception_obj->exception_class, exception_obj,
      (struct _Unwind_Context *)__wasm_lpad_context);
  return ret;
}
```

As you can see in the code above, here's the list of input and output parameters
communicated throw `__wasm_lpad_context`:
* Input parameters
  * Landing pad index
  * Personality function address
  * LSDA information (exception handling table) address
* Output parameters
  * Selector value

These three input parameters are not directly passed to the personality function
as arguments, but are read from it using various `_Unwind_Get*` functions in
unwind library API. The output parameter, a selector value is also not directly
returned by the personality function but will be set by the personality function
using `_Unwind_SetGR`. (`SetGR` here means setting a general register, and it
does set a physical register in Dwarf CFI. But for SjLj and WebAssembly schemes
it sets some field in a data structure instead.)

When looking for a matching catch site in each call frame, what the personality
function does is querying the call site table within the current function's LSDA
(Language Specipic Data Area), also known as exception handling table or
`gcc_except_table`, with a call site information. For example, the table answers
queries such as "If an exception is thrown at this call site, which action table
entry should I check?" In Dwarf CFI scheme, the offset of actual callsite
address relative to function start address is used as callsite information. In
SjLj scheme, each callsite that can throw has an index starting from 0, and the
indices serve as callsite information to query the action table. In WebAssembly
EH, because a call to the personality function wrapper is inserted at the start
of each landing pad, we give each landing pad an index starting from 0 and use
this as callsite information. We also need to pass the address of the
personality function so that the wrapper can call it. The address of LSDA for
the current function is also required because the personality function examines
the tables there to look for a matching catch site.

Putting it all together, below is an example of code snippet the compiler
inserts at the beginning of each landing pad. (This is C-style pseudocode; the
real code inserted will be in IR or assembly level.)
```cpp
// Gets a thrown exception object
void *exn = catch(0); // WebAssembly catch instruction

// Set input parameters
__wasm_lpad_context.lpad_index = index;
__wasm_lpad_context.personality = __gxx_personality_v0;
__wasm_lpad_context.lsda = &GCC_except_table0; // LSDA symbol of this function

// Call personality wrapper function
_Unwind_CallPersonality(exn);

// Retrieve output parameter
int selector = __wasm_lpad_context.selector;

// use exn and selector hereafter
```


### You Shouldn't Prune Unreachable Resumes

Suppose you have this code:
```cpp
try {
  foo(); // may throw
} catch (int n) {
  ...
}

some code...
```
In this code, when the type of a thrown exception is not int, the exception is
rethrown to the caller. The possible CFG structure for this code is,
```LLVM
try:
  foo();
  if exception occured, go to lpad, or else go to try.cont

lpad: ; landing pad block
  if type of exception is int, go to catch, or else go to eh.resume

catch:
  catch int type exception

eh.resume: ; resume block!
  rethrow exception to caller

try.cont:
  some code...
```

Some compilers, such as LLVM,
[prune](https://github.com/llvm-mirror/llvm/blob/7d677e7e2a15d185d82bab44ee9d4f6375569a8c/lib/CodeGen/DwarfEHPrepare.cpp#L132)
basic blocks like `eh.resume` in the code above, considering it unreachable,
which holds true in other exception handling schemes, because if there is
neither matching catch site nor cleanup actions (such as calling destructors to
stack-allocated objects) to do, the unwinder does not even stop at this call
frame. But as we mentioned earlier, WebAssembly unwinding is done by a VM and it
stops at every call frame that has WebAssembly `catch` instruction. So, in the
example above, after we get a selector value from active personality function
call, we actually need to execute the remaining parts of WebAssembly code to
reach the eh.resume block, within which the exception is passed to the caller.
So when we implement WebAssembly EH on a compiler, we should disable this kind
of optimizations.

---

## No Two-Phase Unwinding

Itanium-style two-phase unwinding typically consists of two phases: search and
cleanup. In the search phase, call frames are searched to find a matching catch
site that can catch the type of exception thrown or one that needs some cleanup
action as the stack is unwound. If one is found, it enters the cleanup phase in
which the unwinder stops at the stack frame with the matching catch site found
and starts to run the code there. (The whole search in the second phase is
usually avoided by reusing cached information from the first search phase.) If
no matching clause is found in the first phase, the program aborts.

**WebAssembly unwinder does not perform two-phase unwinding.** Therefore,
effectively, it only runs the second, cleanup phase. As discussed, because the
unwinding is done by a VM, the unwind library and the C++ ABI library cannot
drive its two-phase unwinding. Because we do not have any cached information
from the first search stage, we do full searches as in the first search stage of
two-phase unwinding.

---

## LSDA Information

LSDA (Language Specific Data Area) contains various tables used by the
personality function to check if there is any matching catch sites or cleanup
code to run. Every function that has landing pads has its own LSDA information
area. Usually symbols with prefix `GCC_except_table` or `gcc_except_table` are
used to denote the start of a LSDA information. For some exception handling
schemes LSDA information is stored in its own section, but WebAssembly uses
[data
section](https://github.com/WebAssembly/design/blob/master/Modules.md#data-section).

There are three tables in WebAssembly LSDA information:
* Call site table
  * Maps call sites (landing pad indices) to action table entries.
* Action table
  * Each entry contains the current action (type information and whether to
catch it or filter it) and the next action entry to proceed. Refers to type
information table on which type to catch or filter.
* Type information table
  * List of type information

In WebAssembly EH, the formats of the action table and the type information
table are the same with that of Dwarf CFI and SjLj scheme. The primary
difference of our scheme is we use landing pad indices as call sites.

```text
    Exception Handling Table Layout:

+-----------------+--------+----------------------+
| lpStartEncoding | (char) | always DW_EH_PE_omit |
+---------+-------+--------+---------------+----------+
| lpStart | (encoded with lpStartEncoding) | Not used |
+---------+-----+--------+-----------------+---------------+
| ttypeEncoding | (char) | Encoding of the type_info table |
+---------------+-+------+----+----------------------------+----------------+
| classInfoOffset | (ULEB128) | Offset to type_info table, defaults to null |
+-----------------++--------+-+----------------------------+----------------+
| callSiteEncoding | (char) | Encoding for Call Site Table |
+------------------+--+-----+-----+------------------------+--------------------------+
| callSiteTableLength | (ULEB128) | Call Site Table length, used to find Action table |
+---------------------+-----------+---------------------------------------------------+
+---------------------+-----------+------------------------------------------------+
| Beginning of Call Site Table            landing pad index is a index into this   |
|                                         table.                                   |
| +-------------+---------------------------------+------------------------------+ |
| | landingPad  | (ULEB128)                       | landingpad index             | |
| | actionEntry | (ULEB128)                       | Action Table Index 1-based   | |
| |             |                                 | actionEntry == 0 -> cleanup  | |
| +-------------+---------------------------------+------------------------------+ |
| ...                                                                              |
+----------------------------------------------------------------------------------+
+---------------------------------------------------------------------+
| Beginning of Action Table       ttypeIndex == 0 : cleanup           |
| ...                             ttypeIndex  > 0 : catch             |
|                                 ttypeIndex  < 0 : exception spec    |
| +--------------+-----------+--------------------------------------+ |
| | ttypeIndex   | (SLEB128) | Index into type_info Table (1-based) | |
| | actionOffset | (SLEB128) | Offset into next Action Table entry  | |
| +--------------+-----------+--------------------------------------+ |
| ...                                                                 |
+---------------------------------------------------------------------+-----------------+
| type_info Table, but classInfoOffset does *not* point here!                           |
| +----------------+------------------------------------------------+-----------------+ |
| | Nth type_info* | Encoded with ttypeEncoding, 0 means catch(...) | ttypeIndex == N | |
| +----------------+------------------------------------------------+-----------------+ |
| ...                                                                                   |
| +----------------+------------------------------------------------+-----------------+ |
| | 1st type_info* | Encoded with ttypeEncoding, 0 means catch(...) | ttypeIndex == 1 | |
| +----------------+------------------------------------------------+-----------------+ |
| +---------------------------------------+-----------+------------------------------+  |
| | 1st ttypeIndex for 1st exception spec | (ULEB128) | classInfoOffset points here! |  |
| | ...                                   | (ULEB128) |                              |  |
| | Mth ttypeIndex for 1st exception spec | (ULEB128) |                              |  |
| | 0                                     | (ULEB128) |                              |  |
| +---------------------------------------+------------------------------------------+  |
| ...                                                                                   |
| +---------------------------------------+------------------------------------------+  |
| | 0                                     | (ULEB128) | throw()                      |  |
| +---------------------------------------+------------------------------------------+  |
| ...                                                                                   |
| +---------------------------------------+------------------------------------------+  |
| | 1st ttypeIndex for Nth exception spec | (ULEB128) |                              |  |
| | ...                                   | (ULEB128) |                              |  |
| | Mth ttypeIndex for Nth exception spec | (ULEB128) |                              |  |
| | 0                                     | (ULEB128) |                              |  |
| +---------------------------------------+------------------------------------------+  |
+---------------------------------------------------------------------------------------+
```

You can see the exception table structure for DwarfCFI and SjLj scheme
[here](https://github.com/llvm-mirror/libcxxabi/blob/05ba3281482304ae8de31123a594972a495da06d/src/cxa_personality.cpp#L26).
Other than call site table, the structure for WebAssembly EH is mostly the same.

---

## WebAssembly C++ Exception Handling ABI

We discussed in a [prior section](#landing-pad-code) about some additions
required to the C++ ABI library and the unwind library to implement WebAssembly
EH. Here we list up required additional data structure/functions and
WebAssembly's implementation of required APIs.

### Compiler Builtins

This section describes compiler builtins that require support from compiler
implementations.

##### __builtin_wasm_throw
```
void __builtin_wasm_throw(unsigned int, void *);
```
A call to this builtin function is converted to a WebAssembly
[`throw`](https://github.com/WebAssembly/exception-handling/blob/master/proposals/Exceptions.md#throws)
instruction in the instruction selection stage in the backend. This builtin
function is used to implement exception-throwing functions in the base ABI.

##### __builtin_wasm_rethrow
```
void __builtin_wasm_rethrow();
```
A call to this builtin function is converted to a WebAssembly
[`rethrow`](https://github.com/WebAssembly/exception-handling/blob/master/proposals/Exceptions.md#rethrows)
instruction in the instruction selection stage in the backend. This builtin
function is used to implement rethrowing exceptions in the base API.


### Base ABI

This section defines the unwind library interface, expected to be provided by
any Itanium ABI-compliant system. This is the interface on which the C++ ABI
exception-handling facilities are built. This section describes what WebAssembly
version of the ABI functions do and additional data structures or functions we
need to add. For the complete Itanium C++ base ABI, refer to the spec
[here](https://itanium-cxx-abi.github.io/cxx-abi/abi-eh.html#base-abi).


#### Data Structures

##### Landing Pad Context
This serves as a communication channel between WebAssembly code and the
personality function. A global variable `__wasm_lpad_context` is an instance of
this data structure.

```cpp
struct _Unwind_LandingPadContext {
  // Input information to personality function
  uintptr_t lpad_index;                // landing pad index
  __personality_routine personality;   // personality function
  uintptr_t lsda;                      // LSDA address

  // Output information computed by personality function
  uintptr_t selector;                  // selector value
};

// Communication channel between WebAssembly code and personality function
struct _Unwind_LandingPadContext __wasm_lpad_context = ...;
```


#### Throwing an Exception

##### _Unwind_RaiseException
```cpp
_Unwind_Reason_Code
_Unwind_RaiseException(struct _Unwind_Exception *exception_object);
```
Raise an exception using the [`__builtin_wasm_throw`
builtin](#__builtin_wasm_throw), which will be converted to WebAssembly
[`throw`](https://github.com/WebAssembly/exception-handling/blob/master/proposals/Exceptions.md#throws)
instruction. The arguments to the builtin are the tag number for C++ and a
pointer to an exception object.

##### _Unwind_ForcedUnwind
Not used.

##### _Unwind_Resume
```cpp
void _Unwind_Resume(struct _Unwind_Exception *exception_object);
```
Resume propagation of an existing exception. Unlike other `_Unwind_*` functions
that are called from the C++ ABI library, this is called from compiler-generated
user code. In other exception handling schemes, this function is mostly used
when a call frame does not have a matching catch site but has cleanup code to
run so that the unwinder stops there only to run the cleanup and resume the
exception's propagation. But in WebAssembly EH, because the unwinder stops at
every call frame with landing pads, this runs on every call frame with landing
pads that does not have a matching catch site. This function also makes use of
[`__builtin_wasm_throw` builtin](#__builtin_wasm_throw) to resume the
propagation of an exception.


#### Context Management

##### _Unwind_GetGR / _Unwind_SetGR
```cpp
uint64 _Unwind_GetGR(struct _Unwind_Context *context, int index);
void
_Unwind_SetGR(struct _Unwind_Context *context, int index, uint64 new_value);
```
The meaning of the original API name is it gets/sets the value of the given
general register. But in WebAssembly EH, `_Unwind_SetGR` is only used to [set a
selector
value](https://github.com/llvm-mirror/libcxxabi/blob/05ba3281482304ae8de31123a594972a495da06d/src/cxa_personality.cpp#L528)
to a data structure used as a communication channel
(`__wasm_lpad_context.selector`).

In WebAssembly EH, `_Unwind_SetGR` expects the first argument to be a pointer to
`struct _Unwind_LandingPadContext` instance, and only 1 is accepted as the
second argument, in which case it sets the first argument's `selector` field.
`_Unwind_GetGR` is not used.

##### _Unwind_GetIP / _Unwind_SetIP
```cpp
uint64 _Unwind_GetIP(struct _Unwind_Context *context);
void _Unwind_SetIP(struct _Unwind_Context *context, uint64 new_value);
```
This sets/gets a real IP address in Dwarf CFI, but in our scheme `_Unwind_GetIP`
returns the value of (landing pad index - 1). The landing pad index is set by
compiler-generated user code to `__wasm_lpad_context.lpad_index` as discussed in
[Landing Pad Code](#landing-pad-code). This information is used in the
personality function to query the call site table. `_Unwind_SetIP` is not used.

##### _Unwind_GetLanguageSpecificData
```cpp
uint64 _Unwind_GetLanguageSpecificData(struct _Unwind_Context *context);
```
Returns the address of the current function's LSDA information
(`__wasm_lpad_context.lsda`), set by compiler-generated user code as discussed
in [Landing Pad Code](#landing-pad-code).

##### _Unwind_GetRegionStart
Not used.


#### Personality Routine

##### Personality Function Wrapper
A wrapper function used to call the actual personality function. This is
supposed to be called from compiler-generated user code. Refer to [Landing Pad
Code](#landing-pad-code) for details.

```cpp
_Unwind_Reason_Code _Unwind_CallPersonality(void *exception_ptr) {
  struct _Unwind_Exception *exception_obj =
      (struct _Unwind_Exception *)exception_ptr;

  // Call personality function
  _Unwind_Reason_Code ret = (*__wasm_lpad_context->personality)(
      1, _UA_CLEANUP_PHASE, exception_obj->exception_class, exception_obj,
      (struct _Unwind_Context *)__wasm_lpad_context);
  return ret;
}
```

##### Transferring Control to a Landing Pad
Transferring program control to a landing pad is done by not the unwind library
but the VM. Refer to [Stack Unwinding and Personality
Function](#stack-unwinding-and-personality-function) section for details.


### C++ ABI

The second level of specification is the minimum required to allow
interoperability of C++ implementations. This part contains the definition of an
exception object, and various high-level APIs including functions required to
allocate / throw / catch / rethrow an exception object. Functions in this
section rely on the [base
API](https://itanium-cxx-abi.github.io/cxx-abi/abi-eh.html#base-abi) to do
low-level architecture-dependent tasks. WebAssembly EH does not have a lot of
things to add on this level because architecture-dependent components are
usually taken care of in the base API level. But we still need some
modifications on the personality function and functions called from it to handle
some subtle differences between WebAssembly EH and other schemes, such as Dwarf
CFI or SjLj. For the complete Itanium C++ ABI, refer to the spec
[here](https://itanium-cxx-abi.github.io/cxx-abi/abi-eh.html#cxx-abi).

---

## Exception Structure Recovery

To regroup instructions in CFG into this `try`-`catch i`-...-`try-end` structure
described in the [WebAssembly exception handling
proposal](https://github.com/WebAssembly/exception-handling/blob/master/proposals/Exceptions.md),
the compiler should recover the near-original try-catch clause structure from
the CFG. We presented a very simple example of this grouping in [WebAssembly try
and catch Blocks](#webassembly-try-and-catch-blocks) section. How we do this is
more of an internal algorithm than the spec for our exception handling scheme,
but we present the current algorithm implemented in LLVM here to show an
example. Note that this is not the only way blocks can be grouped and other
compiler implementations may use other algorithms. This currently only supports
C++ exceptions: it generates neither `catch` instructions for other language
tags nor `catch_all` intructions.

_TODO: This section will be filled once LLVM patch for this part is landed._

---

## References

* [Exception Handling in LLVM](https://llvm.org/docs/ExceptionHandling.html)
* [Itanium C++ ABI: Exception
Handling](https://itanium-cxx-abi.github.io/cxx-abi/abi-eh.html)

* Github mirror
  * LLVM
    * [llvm](https://github.com/llvm-mirror/llvm)
    * [libcxxabi](https://github.com/llvm-mirror/libcxxabi)
    * [libunwind](https://github.com/llvm-mirror/libunwind)
  * GCC
    * [gcc](https://github.com/gcc-mirror/gcc)
    * [libsupc++](https://github.com/gcc-mirror/gcc/tree/master/libstdc%2B%2B-v3/libsupc%2B%2B)
    * [libgcc_s](https://github.com/gcc-mirror/gcc/tree/master/libgcc)
