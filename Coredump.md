This document describes the usage of coredump for post-mortem debugging with
WebAssembly.

# Idea

When WebAssembly enters a trap, it starts unwinding and collects debugging
information. For each stack frame, collect the values in locals (includes
function parameters) and on the stack. Along with binary offsets to resolve to
source file locations. Finally, make a snapshot of the linear memory (or
multiple linear memories when the [multi-memory] feature is used), tables and
globals.

All this information is saved to the file, called the coredump file.

The post mortem analysis is done using the coredump and [DWARF] information.
Similar to the debugging flow with [gdb].

# Implementation status

Stability of this specification is **experimental**.

Tools that support the generation of Wasm coredumps:
- [wasm-edit]

Debugger that supports post-mortem debugging with Wasm coredumps:
- [wasmgdb]

## Runtime support

Most of the WebAssembly runtimes are already able to present a useful stacktrace
on crash to the user. When they are configured to emit a coredump, they collect
the debugging information and write a coredump file.

An example output:
```
$ wasmrun module.wasm

Exit 1: Uncaught RuntimeError: memory access out of bounds (core dumped).
``` 
A coredump file has been generated.

For experimenting, runtime support is not strictly necessary. A tool can
transform the Wasm binary to inject code that will manually unwind the stack and
collect debugging information, for instance [wasm-edit coredump]. Such a
transformation has important limitations; a trap caused by an invalid memory
operation or exception in a host function might not be caught.

## Security and privacy considerations

Using the WebAssembly linear memory for debugging exposes the risk of seeing,
manipulating and/or collecting sensitive informations.

For the user of Wasm coredumps, there's no particular security or privacy
considerations.

## Debugger support

[gdb] doesn't support Wasm coredump and it's unclear if it can. Wasm coredump
differ from ELF coredump in a few significant ways:
- Wasm semantics; usage of locals, globals and the stack.
- The process image is only the Wasm linear memory.
- etc.

For experimenting, a custom tool has been built and mimics [gdb]: [wasmgdb].

It seems possible for Chrome's Wasm debugger extension to support Wasm
coredumps.  Challenges for coredumps in the web context would be to collect the
instance's state as tools like emscripten (and of course most of a larger web
app's state) are in JS rather than Wasm.

# Coredump file format

The coredump file is encoded using the [Wasm binary format], containing:
- general information about the process.
- the threads and stack frames.
- a snapshot of the WebAssembly linear memory or relevant regions.

The order in which they appear in the file is not important.

As opposed to regular Wasm files, Wasm Coredumps are not [instantiated].

`u32` are encoded using [Wasm u32].

## Process information

General information about the process is stored in a [Custom section], called
`core`.

```
core         ::= customsec(process-info)
process-info ::= 0x0 executable-name:name
```

## Thread(s) and stack frames

For each thread a [Custom section], called `corestack`, is used to store the
debugging information.

```
corestack   ::= customsec(thread-info vec(frame))
thread-info ::= 0x0 thread-name:name
frame       ::= 0x0 funcidx:u32 codeoffset:u32 locals:vec(value)
                stack:vec(value)
```

`funcidx` is the WebAssembly function index in the module and `codeoffset` is
the instruction's offset relative to the function's start.

> Note: implementations may leave `codeoffset` offset empty if unknown. Setting
> 0 will point to the function's start.

Local and stack values are encoded using one byte for the type (similar to
Wasm's [Number Types]) followed by bytes representing the actual value:
```
value ::= 0x01       => ∅
        | 0x7F n:i32 => n
        | 0x7E n:i64 => n
        | 0x7D n:f32 => n
        | 0x7C n:f64 => n
```

The special byte `0x01` is used to represent a missing value, usually because it
was optimized out by the WebAssembly engine.

## Memory

The process memory is captured in the [Data Section], either entirely as one
active data segment or as multiple active data segments (used to represent
partial coredumps).

## Globals

Globals are captured in the [Global Section] as global constants (non mutable).

One or multiple memories are written in the [Memory Section].

# Demo

Please have a look at the demonstration using the experimental support and
tooling: [demo].

# Useful links

- [ELF coredump]
- [Wasmer FrameInfo]

[Wasm Vectors]: https://webassembly.github.io/spec/core/binary/conventions.html#binary-vec
[ELF coredump]: https://www.gabriel.urdhr.fr/2015/05/29/core-file/
[Core dump on Wikipedia]: https://en.wikipedia.org/wiki/Core_dump
[gdb]: https://linux.die.net/man/1/gdb
[wasm-edit coredump]: https://github.com/xtuc/wasm-coredump/blob/main/bin/rewriter/src/rewriter.rs
[wasm-edit]: https://github.com/xtuc/wasm-coredump/tree/main/bin/rewriter
[wasmgdb]: https://github.com/xtuc/wasm-coredump/tree/main/bin/wasmgdb
[DWARF]: https://yurydelendik.github.io/webassembly-dwarf
[Wasmer FrameInfo]: https://docs.rs/wasmer/latest/wasmer/struct.FrameInfo.html
[Wasm u32]: https://webassembly.github.io/spec/core/binary/values.html#binary-int
[demo]: https://github.com/xtuc/wasm-coredump/blob/main/bin/wasmgdb/demo.md
[multi-memory]: https://github.com/WebAssembly/multi-memory
[Wasm binary format]: https://webassembly.github.io/spec/core/binary/index.html
[Data Section]: https://webassembly.github.io/spec/core/binary/modules.html#data-section
[Custom section]: https://webassembly.github.io/spec/core/binary/modules.html#binary-customsec
[Memory Section]: https://webassembly.github.io/spec/core/binary/modules.html#binary-memsec
[instantiated]: https://webassembly.github.io/spec/core/exec/modules.html#instantiation
[Global Section]: https://webassembly.github.io/spec/core/binary/modules.html#binary-globalsec 
[Number Types]: https://webassembly.github.io/spec/core/binary/types.html#binary-numtype
