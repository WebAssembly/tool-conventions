WebAssembly Object File Linking
===============================

This document describes the early plans for how linking of WebAssembly modules
might work in the clang/LLVM WebAssembly backend and other tools.  As mentioned
in [README](README.md), it is not the only possible way to link WebAssembly
modules.  Note: the ABI described in the document is a work in progress and
**should not be considered stable**.

Each compilation unit is compiled as a single WebAssembly module.  Each
module contains a single code section and a single data section.  The goal
of the linker is to take two or more modules and merge them into single module.
In order to achieve this the following tasks need to be performed:

- Merging of function sections (re-numbering functions)
- Merging of globals sections (re-numbering globals)
- Merging of data segments (re-positioning data)
- Resolving undefined external references

The linking technique described here is designed to be fast, and avoids having
the disassemble the the code section.  The relocation information required by
the linker is stored in custom sections whos names begin with "reloc.".  For
each section that requires relocation a "reloc" section will be present in the
wasm file.  By convension the reloc section names end with name of the section
thet they refer to: e.g. "reloc.CODE" for code section relocations.  However
everything after the period is ignored and the specific target section is
encoded in the reloc section itself.

The "reloc" Section
-------------------

The "reloc" section is defined as:

| Field          | Type                | Description                    |
| -------------- | ------------------- | ------------------------------ |
| section\_index | `varuint32`         | the section to which the relocations refer. An integer betweeen 1 and N where N is the number of section in the wasm object file |
| count          | `varuint32`         | count of entries to follow     |
| entries        | `relocation_entry*` | sequence of relocation entries |

a `relocation_entry` is:

| Field    | Type                | Description                    |
| -------- | ------------------- | ------------------------------ |
| type     | `varuint32`         | the relocation type            |

A relocation type can be one of the following:

- `0 / R_FUNCTION_INDEX` - a function index encoded as an LEB128.  Used
  for the immediate argument of a `call` instruction in the code section.
- `1 / R_TABLE_INDEX` - a table index encoded as an SLEB128.  Used
  for the immediates that refer to the table index space. e.g. loading the
  address of the function using `i32.const`.
- `2 / R_GLOBAL_INDEX` - a global index encoded as an LEB128.  Points to
  the immediate value of `get_global` / `set_global` instructions.
- `3 / R_DATA` - an index into the global space which is used store the address
  of a C global

For relocation types other than `R_DATA` the following fields are present:

| Field  | Type             | Description                         |
| ------ | ---------------- | ----------------------------------- |
| offset | `varuint32`      | offset of [S]LEB within the section |

For `R_DATA` relocations the following fields are presnet:

| Field         | Type              | Description                    |
| ------------- | ----------------- | ------------------------------ |
| global\_index | `varuint32`       | the index of the global used   |

Merging Global Section
----------------------

Merging of globals sections requires re-numbering of the globals.  To enable
this an `R_GLOBAL_INDEX` entry in the `reloc` section is generated for each
`get_global` / `set_global` instruction.  The immediate values of all
`get_global` / `set_global` instruction are stored as padded LEB123 such that
they can be rewritten without altering the size of the code section.  The
relocation points to the offset of the padded immediate value within the code
section, allowing the linker to both read the current value and write an updated
one.

Merging Function Sections
-------------------------

Merging of the function sections requires the re-numbering of functions.  This
requires modification to code sections at each location where a function
index is embedded.  There are currently two ways in which function indices are
stored in the code section:

1. Immediate argument of the `call` instruction (calling a function)
2. Immediate argument of the `i32.const` instruction (taking the address of a
   function).

The immediate argument of all such instruction are stored as padded LEB123
such that they can be rewritten without altering the size of the code section.
For each such instruction a `R_FUNCTION_INDEX_LEB` or `R_FUNCTION_INDEX_SLEB`
`reloc` entry is generated pointing to the offset of the immediate within the
code section.

The same technique applies for all function calls whether the function is
imported or defined locally.

Merging Data Sections
---------------------

References to global data are modeled as loads or stores via a wasm
[global](https://github.com/WebAssembly/design/blob/master/Modules.md#global-variables).
Each C global is assigned a wasm global, and access to C global variables will
generate a `get_global` followed by a load/store to/from the resulting address.
The addresses stored in these wasm globals can then be set by the linker when it
relocates data segments.  For each wasm global that is used in this way an entry
in the `reloc` of type `R_DATA` is generated so that the linker knows which
wasm globals require modification.

External references
-------------------

Undefined external references are modeled as named [function
imports](https://github.com/WebAssembly/design/blob/master/Modules.md#imports).

Exported functions
------------------

Non-static functions are modeled as [function
exports](https://github.com/WebAssembly/design/blob/master/Modules.md#exports).
