WebAssembly Object File Linking
===============================

This document describes the early plans for how linking of WebAssembly modules
might work in the clang/LLVM WebAssembly backend.  As mentioned in
[README](README.md), it is not the only possible way to link WebAssembly
modules.

Each compilation unit is compiled with a single WebAssembly module.  Each
module contains a single code section and a single data section.  The goal
of the linker is to take two or more modules and merge them into single module.
In order to achieve this the following tasks need to be performed:

- Merging of function section (re-numbering functions)
- Merging of data segments (re-positioning data)
- Resolving undefined external references

The linking technique described here is designed to be fast, and avoid having
the decode the WebAssembly op-codes in the code section.  A `user-defined`
section called called "reloc" to used to store additional information required
by the linker.

The "reloc" section is defined as:

| Field   | Type                | Description                    |
| ------- | ------------------- | ------------------------------ |
| count   | `varuint32`         | count of entries to follow     |
| entries | `relocation_entry*` | sequence of relocation entries |

a `relocation_entry` is:

| Field    | Type                | Description                    |
| -------- | ------------------- | ------------------------------ |
| type     | `varuint32`         | the relocation type            |

A relocation type can be one of the following:

- `0 - R_CALL` - a local function call
- `1 / R_GLOBAL` - a global data reference

For `R_CALL` relocations the following fields are presnet:

| Field    | Type                | Description                    |
| -------- | ------------------- | ------------------------------ |
| location | `varuint32`         | location of call opcode        |

For `R_GLOBAL` relocations the following fields are presnet:

| Field         | Type              | Description                    |
| ------------- | ----------------- | ------------------------------ |
| global\_index | `varuint32`       | the index of the global used   |
| size          | `varuint32`       | the size of the referenced data|

Merging Function Sections
-------------------------

Merging of the function sections requires the re-numbering of functions.  This
requires each of the call sites in the code section to be modified.  In order
to achieve this the code is generated such that the immediate `function_index`
of each `call` instruction is stored as a padded LEB128 that can be modified in
place without requiring any additional bytes of storage.  An `R_CALL` entry
in the `reloc` section is then generated pointing to location of each `call`
opcode.

The same technique works for all function calls weather the function is
imported or defined locally.

Merging Data Sections
---------------------

References to global data are modeled as wasm
[globals](https://github.com/WebAssembly/design/blob/master/Modules.md#global-variables).
Each access to a global memory location generates a `get_global` instruction
and the value of the global can then be modified by the linker when it relocates
data segments.  For each global that is used in this way an entry
in the `reloc` of type `R_GLOBAL` is generated.

External references
-------------------

Undefined external references are modeled as named [function
imports](https://github.com/WebAssembly/design/blob/master/Modules.md#imports).

Exported functions
------------------

Non-static functions are modeled as [function
exports](https://github.com/WebAssembly/design/blob/master/Modules.md#exports).
