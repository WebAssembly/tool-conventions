This document describes the usage of coredump for post-mortem debugging with
WebAssembly.

# Idea

When WebAssembly enters a trap, it starts unwinding and collects debugging
information. For each stack frame, collect the values in locals (includes
function parameters) and on the stack. Along with an instruction binary offset
(relative to the code section, as specified by [DWARF]). Finally, make a
snapshot of the linear memory (or multiple linear memories when the
[multi-memory] feature is used), tables and globals.

All these informations are saved to the file, called the coredump file.

The post mortem analyze is done using the coredump and [DWARF] informations.
Similar to the debugging flow with [gdb].

# Implementation status

Stability of this specification is **experimental**.

Tools that support the generation of Wasm coredumps:
- [wasm-edit]

Debugger that support post-mortem debugging with Wasm coredumps:
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

For experimenting, runtime support is not strictly necessary. A tools can
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

The generated coredump is a binary file containing: 
- a snapshot of the WebAssembly linear memory or relevant regions.
- the `coredump` struct.

The placement of the `coredump` struct within the coredump file is not defined
yet. However, for the sake of argument we assume it's at offset 0.

# `coredump` struct

The coredump struct starts with the numbers of frame recorded and the combined
size of all frames, followed by the frames themself.

```
coredump ::= size:u32 cont:vec(frame)
```

> implementer note: since the `frame` struct doesn't have a fixed size, the
> `size` value can be used to append new frames because it's pointing at the end
> of the `coredump`.

```
frame ::= codeoffset:u32
          locals:vec(local)
          stack:vec(stack)
          reserved:u32
```

The `reserved` bytes are decoded as an empty vector and reserved for future use.

`vec` (same encoding as [Wasm Vectors]):
```
vec(B) ::= n:u32 cont:B
```

`u32` are encoding using LEB128, like [Wasm u32].

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
[wasm-edit coredump]: https://github.com/xtuc/wasm-edit/blob/main/src/coredump.rs
[wasm-edit]: https://github.com/xtuc/wasm-edit
[wasmgdb]: https://github.com/xtuc/wasmgdb
[DWARF]: https://yurydelendik.github.io/webassembly-dwarf
[Wasmer FrameInfo]: https://docs.rs/wasmer/latest/wasmer/struct.FrameInfo.html
[Wasm u32]: https://webassembly.github.io/spec/core/binary/values.html#binary-int
[demo]: https://github.com/xtuc/wasmgdb/wiki/Demo
[multi-memory]: https://github.com/WebAssembly/multi-memory
