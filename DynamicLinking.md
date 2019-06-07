WebAssembly Dynamic Linking
===========================

This document describes a proposed ABI for dynamic linking of WebAssembly
modules along with the current implementation status.

Note: This ABI is still a work in progress.  There is no stable ABI yet.

# Dynamic Libraries

A WebAssembly dynamic library is a WebAssembly binary with a special custom
section that indicates this is a dynamic library and contains additional
information needed by the loader.

## The "dylink" Section

The "dylink" section is defined as:

| Field                  | Type            | Description                    |
| ---------------------- | --------------- | ------------------------------ |
| memorysize             | `varuint32`     | Size of the memory area the loader should reserve for the module, which will begin at `env.__memory_base` |
| memoryalignment        | `varuint32`     | The required alignment of the memory area, in bytes, encoded as a power of 2. |
| tablesize              | `varuint32`     | Size of the table area the loader should reserve for the module, which will begin at `env.__table_base` |
| tablealignment         | `varuint32`     | The required alignment of the table area, in elements, encoded as a power of 2. |
| needed_dynlibs_count   | `varuint32`     | Number of needed shared libraries |
| needed_dynlibs_entries | `dynlib_entry*` | Repeated dynamic library entries as described below |

The "dynlib_entry" type is defined as:

| Field           | Type        | Description                    |
| --------------- | ----------- | ------------------------------ |
| dynlib_name_len | `varuint32` | Length of `dynlib_name_str` in bytes |
| dynlib_name_str | `bytes`     | Name of a needed dynamic library: valid UTF-8 byte sequence |

`env.__memory_base` and `env.__table_base` are `i32` imports that contain
offsets into the linked memory and table, respectively. If the dynamic library
has `memorysize > 0` then the loader will reserve room in memory of that size
and initialize it to zero (note: can be larger than the memory segments in the
module, if the dynamic library wants additional space) at offset
`env.__memory_base`, and similarly for the table (where initialization is to
`null`, i.e., a trap will occur if it is called). The allocated regions of the
table and memory are guaranteed to be at least as aligned as the library
requests in the `memoryalignment, tablealignment` properties. The library can
then place memory and table segments at the proper locations using those
imports.

If `needed_dynlibs_count > 0` then the loader, before loading the library, will
first load needed libraries specified by `needed_dynlibs_entries`.

The "dylink" section should be the very first section in the module; this allows
detection of whether a binary is a dynamic library without having to scan the
entire contents.

## Interface and usage

A WebAssembly dynamic library must obey certain conventions.  In addition to
the `dylink` section described above a module may import the following globals
that will be provided by the dynamic loader:

 * The module can import `env.memory` for memory that is shared with the
   outside. If it does so, it should import `env.__memory_base`, an `i32`
   WebAssembly global, in which the loader will provide the start of the region
   in memory which has been reserved and zero-initialized for this module, as
   described earlier.  The module can use this global in the intializer of its
   data segments so that they loaded at the correct address.
 * The module can import `env.table` for a table that is shared with the
   outside. If it does so, it should import `env.__table_base`, an `i32`
   WebAssembly global, in which the loader will provide the start of the region
   in the table which has been reserved for this module, as described earlier.

### Relocations

WebAssembly dynamic libraries do not require relocations in the code section.
This allows for streaming compilation and better code sharing, and reduces the
complexity of the dynamic linker.  For external symbols this is achieved by
referencing WebAssembly imports.  For internal symbols we introduce two new
relocation types for accessing data and functions address relative to
`__memory_base` and `__table_base` global:

- `11 / R_WASM_MEMORY_ADDR_REL_SLEB,` - a memory address relative to the
  `__memory_base` wasm global.  Used in position independent code (`-fPIC`)
  where absolute memory addresses are not known at link time.
- `12 / R_WASM_TABLE_INDEX_REL_SLEB` - a function address (table index)
  relative to the `__table_base` wasm global.  Used in position indepenent code
  (`-fPIC`) where absolute function addresses are not known at link time.

All code that gets linked into a WebAssembly dynamic library must be compiled
as position independant.  The corresponding absolute reloction types
(R_WASM_MEMORY_ADDR_SLEB and R_WASM_TABLE_INDEX_SLEB) are not permitted in
position independant code and will be rejected at link time.

For relocation within the data segments a runtime fixup may be required.  For
example, if the address of an external symbol is stored in global data.  In this
case the dynamic library must generate code to apply these relocations at
startup.  The module can export a function called `__post_instantiate`. If it is
so exported, the loader will call it after the module is instantiated, and
before any other function is called.  The `__post_instantiate` function is used
both to apply relocations and to run any static constructors.

### Imports

Functions are directly imported from the `env` module (e.g.
`env.enternal_func`).  Data addresses and function addresses are imported as
WebAssembly globals that store the memory offset or table offset of the symbol.
Such address are imported from `GOT.mem` and `GOT.func` respectively.  The `GOT`
prefix is borrowed from the ELF linking world and stands for "Global Offset
Table".  In WebAssembly the GOT is modeled as a set of imported wasm globals.

For example, a dynamic library might import and use an external data symbol as
follows:

```wasm
(import "GOT.mem" "foo" (global $foo_addr (mut i32))
...
...
get_global $foo_addr
i32.load
```

And an external function symbol as follows:

```wasm
(import "GOT.func" "bar" (global $bar_addr i32))
...
...
get_global $bar_addr
call_indirect
```

Note: This has no effect on exports, or the import of functions for direct call.

In the case of data symbols the imported global must be mutable as the dynamic
linker will need to modify the value after instantiation.   This is because the
data symbol offsets might be specified as wasm exports from other modules which
have not yet been instantiated.  However, imports of function addresses do not
need to be mutable since the linker can assign a table index to each imported
function before it instantiates any of the modules.

### Exports

Functions are directly exported as WebAssembly function exports.  Exported
addresses (i.e., exported memory locations or exported table locations) are
exported as i32 WebAssembly globals.  However since exports are static, modules
connect export the final relocated addresses (i.e. they cannot add
`__memory_base` before exporting). Thus, the exported address is before
relocation; the loader, which knows `__memory_base`, can then calculate the
final relocated address.

## Implementation Status

### LLVM Implementation

When llvm is run with `--relocation-model=pic` (a.k.a `-fPIC`) it will generate
code that accesses non-DSO-local addresses via the `GOT.mem` and `GOT.func`
entries.  Such code must then be linked with either `-shared` to produce a
shared library or `-pie` to produced a dynamically linked executable.

### Emscripten

Emscripten can load WebAssembly dynamic libraries either at startup (using
`RUNTIME_LINKED_LIBS`) or dynamically (using `dlopen`/`dlsym`/etc).
See `test_dylink_*` adnd `test_dlfcn_*` in the test suite for examples.

Emscripten can create WebAssembly dynamic libraries with its `SIDE_MODULE`
option, see [the wiki](https://github.com/kripken/emscripten/wiki/WebAssembly-Standalone).

In order to use the llvm output in emscripten (which still uses the old ABI
described above) a binaryen pass is run as part of `wasm-emscripten-finalize`
then coverts from the ABI descirbed in this document to the ABI used by the
emscripten dynamic linker is somewhat different.  The emscripten ABI uses
specially named functions (e.g. `g$foo` and `fp$foo`) for accessing the
addresses of the dynamically linked symbols rather than using WebAssembly
globals.
