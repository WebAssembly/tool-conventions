WebAssembly Object File Linking
===============================

This document describes the early plans for how static linking of WebAssembly
might work in the clang/LLVM WebAssembly backend and other tools.  As mentioned
in [README](README.md), it is not the only possible way to link WebAssembly
modules.  Note: the ABI described in the document is a work in progress and
**should not be considered stable**.

Each compilation unit is compiled as a "relocatable" WebAssembly module.  These
modules are not expected to be directly executable and have certain
constraints on them, but are otherwise well-formed WebAssembly modules.  In
order to distinguish relocatable modules the linker can check for the presence
of the ["linking"](#linking-metadata-section) custom section which must exist in
all relocatable modules.

The goal of the linker is to take one or more modules and merge them into
single executable module.  In order to achieve this the following tasks need to
be performed:

- Merging of function sections (re-numbering functions)
- Merging of globals sections (re-numbering globals)
- Merging of data segments (re-positioning data)
- Resolving undefined external references

The linking technique described here is designed to be fast, and avoids having
to disassemble the code section.  The extra metadata required by the linker
is stored in a custom ["linking"](#linking-metadata-section) section and zero or
more relocation sections whose names begin with "reloc.".  For each section that
requires relocation a "reloc" section will be present in the wasm file.  By
convention the reloc section names end with the name of the section that they refer
to: e.g. "reloc.CODE" for code section relocations.  However everything after
the period is ignored and the specific target section is encoded in the reloc
section itself.

Relocation Sections
-------------------

A relocation section is a user-defined section with a name starting with
"reloc." Relocation sections start with an identifier specifying which
section they apply to, and must be sequenced in the module after that
section.

Relocations contain the following fields:

| Field      | Type                | Description                    |
| ---------- | ------------------- | ------------------------------ |
| section_id | `varuint32`         | the section to which the relocations refer. |
| name_len   | `varuint32` ?       | the length of name in bytes, present if `section_id == 0` |
| name       | `bytes` ?           | the name of custom section, present if `section_id == 0` |
| count      | `varuint32`         | count of entries to follow     |
| entries    | `relocation_entry*` | sequence of relocation entries |

A `relocation_entry` begins with:

| Field    | Type                | Description                    |
| -------- | ------------------- | ------------------------------ |
| type     | `varuint32`         | the relocation type            |

A relocation type can be one of the following:

- `0 / R_WEBASSEMBLY_FUNCTION_INDEX_LEB` - a function index encoded as a 5-byte
  [varuint32]. Used for the immediate argument of a `call` instruction.
- `1 / R_WEBASSEMBLY_TABLE_INDEX_SLEB` - a function table index encoded as a
  5-byte [varint32]. Used to refer to the immediate argument of a `i32.const`
  instruction, e.g. taking the address of a function.
- `2 / R_WEBASSEMBLY_TABLE_INDEX_I32` - a function table index encoded as a
  [uint32], e.g. taking the address of a function in a static data initializer.
- `3 / R_WEBASSEMBLY_MEMORY_ADDR_LEB` - a linear memory index encoded as a 5-byte
  [varuint32]. Used for the immediate argument of a `load` or `store`
  instruction, e.g. directly loading from or storing to a C++ global.
- `4 / R_WEBASSEMBLY_MEMORY_ADDR_SLEB` - a linear memory index encoded as a 5-byte
  [varint32]. Used for the immediate argument of a `i32.const` instruction,
  e.g. taking the address of a C++ global.
- `5 / R_WEBASSEMBLY_MEMORY_ADDR_I32` - a linear memory index encoded as a
  [uint32], e.g. taking the address of a C++ global in a static data
  initializer.
- `6 / R_WEBASSEMBLY_TYPE_INDEX_LEB` - a type table index encoded as a
  5-byte [varuint32], e.g. the type immediate in a `call_indirect`.
- `7 / R_WEBASSEMBLY_GLOBAL_INDEX_LEB` - a global index encoded as a
  5-byte [varuint32], e.g. the index immediate in a `get_global`.

[varuint32]: https://github.com/WebAssembly/design/blob/master/BinaryEncoding.md#varuintn
[varint32]: https://github.com/WebAssembly/design/blob/master/BinaryEncoding.md#varintn
[uint32]: https://github.com/WebAssembly/design/blob/master/BinaryEncoding.md#uintn

For `R_WEBASSEMBLY_FUNCTION_INDEX_LEB`, `R_WEBASSEMBLY_TABLE_INDEX_SLEB`,
and `R_WEBASSEMBLY_TABLE_INDEX_I32` relocations the following fields are
present:

| Field  | Type             | Description                              |
| ------ | ---------------- | ---------------------------------------- |
| offset | `varuint32`      | offset of the value to rewrite           |
| index  | `varuint32`      | the index into the symbol table (which must reference a function symbol) |

For `R_WEBASSEMBLY_MEMORY_ADDR_LEB`, `R_WEBASSEMBLY_MEMORY_ADDR_SLEB`,
and `R_WEBASSEMBLY_MEMORY_ADDR_I32` relocations the following fields are
present:

| Field  | Type             | Description                         |
| ------ | ---------------- | ----------------------------------- |
| offset | `varuint32`      | offset of the value to rewrite      |
| index  | `varuint32`      | the index into the symbol table (which must reference a data symbol) |
| addend | `varint32`       | addend to add to the address        |

For `R_WEBASSEMBLY_TYPE_INDEX_LEB` relocations the following fields are
present:

| Field  | Type             | Description                         |
| ------ | ---------------- | ----------------------------------- |
| offset | `varuint32`      | offset of the value to rewrite      |
| index  | `varuint32`      | the index of the type used          |

For `R_WEBASSEMBLY_GLOBAL_INDEX_LEB` relocations the following fields
are present:

| Field  | Type             | Description                         |
| ------ | ---------------- | ----------------------------------- |
| offset | `varuint32`      | offset of the value to rewrite      |
| index  | `varuint32`      | the index into the symbol table (which must reference a global symbol) |

Linking Metadata Section
------------------------

A linking metadata section is a user-defined section with the name
"linking".

A linking metadata section contains a series of sub-sections layed
out in the same way as the ["names"][names_sec] section:

| Field        | Type        | Description                          |
| ------------ | ----------- | ------------------------------------ |
| type         | `varuint7`  | code identifying type of subsection  |
| payload_len  | `varuint32` | size of this subsection in bytes     |
| payload_data | `bytes`     | content of this subsection, of length `payload_len` |

The current list of valid `type` codes are:

- `5 / WASM_SEGMENT_INFO` - Extra metadata about the data segments.

- `6 / WASM_INIT_FUNCS` - Specifies a list of constructor functions to be called
  at startup time.

- `7 / WASM_COMDAT_INFO` - Specifies the COMDAT groups of associated linking
  objects, which are linked only once and all together.

- `8 / WASM_SYMBOL_TABLE` - Specifies extra information about the symbols present
  in the module.

For `WASM_SEGMENT_INFO` the following fields are present in the
subsection:

| Field       | Type         | Description                      |
| ----------- | ------------ | -------------------------------- |
| count       | `varuint32`  | number of `segment` in segments  |
| segments    | `segment*`   | sequence of `segment`            |

where a `segment` is encoded as:

| Field        | Type         | Description                                   |
| ------------ | ------------ | --------------------------------------------- |
| name_len     | `varuint32`  | length of `name_data` in bytes                |
| name_data    | `bytes`      | UTF-8 encoding of the segment's name          |
| alignment    | `varuint32`  | The alignment requirement (in bytes) of the segment |
| flags        | `varuint32`  | a bitfield containing flags for this segment  |

For `WASM_INIT_FUNCS` the following fields are present in the
subsection:

| Field       | Type         | Description                           |
| ----------- | ------------ | ------------------------------------- |
| count       | `varuint32`  | number of init functions that follow  |
| functions   | `varuint32*` | sequence of symbol indices            |

For `WASM_SYMBOL_TABLE` the following fields are present in the
subsection:

| Field  | Type            | Description                  |
| ------ | --------------- | ---------------------------- |
| count  | `varuint32`     | number of `syminfo` in infos |
| infos  | `syminfo*`      | sequence of `syminfo`        |

where a `syminfo` is encoded as:

| Field        | Type           | Description                                 |
| ------------ | -------------- | ------------------------------------------- |
| kind         | `varuint32`    | The symbol type.  One of:                   |
|              |                |   `0 / SYMTAB_FUNCTION`                     |
|              |                |   `1 / SYMTAB_DATA`                         |
|              |                |   `2 / SYMTAB_GLOBAL`                       |
| flags        | `varuint32`    | a bitfield containing flags for this symbol |

For functions and globals, we reference an existing Wasm object, which is either
an import or a defined function/global (recall that the operand of a Wasm
`call` instruction uses an index space consisting of the function imports
followed by the defined functions, and similarly `get_global` for global imports
and definitions).  If a function or global symbol references an import, then the
name is taken from the import; otherwise the `syminfo` specifies the symbol's
name.

| Field        | Type           | Description                                 |
| ------------ | -------------- | ------------------------------------------- |
| index        | `varuint32`    | the index of the Wasm object corresponding to the symbol, which references an import if and only if the `WASM_SYM_UNDEFINED` flag is set  |
| name_len     | `varuint32` ?  | the optional length of `name_data` in bytes, omitted if `index` references an import |
| name_data    | `bytes` ?      | UTF-8 encoding of the symbol name           |

For data symbols:

| Field        | Type           | Description                                 |
| ------------ | -------------- | ------------------------------------------- |
| name_len     | `varuint32`    | the length of `name_data` in bytes          |
| name_data    | `bytes`        | UTF-8 encoding of the symbol name           |
| index        | `varuint32` ?  | the index of the data segment; provided if the symbol is defined |
| offset       | `varuint32` ?  | the offset within the segment; provided if the symbol is defined; must be <= the segment's size |
| size         | `varuint32` ?  | the size (which can be zero); provided if the symbol is defined; `offset + size` must be <= the segment's size |

The current set of valid flags for symbols are:

- `1 / WASM_SYM_BINDING_WEAK` - Indicating that this is a weak symbol.  When
  linking multiple modules defining the same symbol, all weak definitions are
  discarded if any strong definitions exist; then if multiple weak definitions
  exist all but one (unspecified) are discarded; and finally it is an error if
  more than one definition remains.
- `2 / WASM_SYM_BINDING_LOCAL` - Indicating that this is a local symbol (this
  is exclusive with `WASM_SYM_BINDING_WEAK`). Local symbols are not to be
  exported, or linked to other modules/sections. The names of all non-local
  symbols must be unique, but the names of local symbols are not considered for
  uniqueness. A local function or global symbol cannot reference an import.
- `4 / WASM_SYM_VISIBILITY_HIDDEN` - Indicating that this is a hidden symbol.
  Hidden symbols are not to be exported when performing the final link, but
  may be linked to other modules.
- `0x10 / WASM_SYM_UNDEFINED` - Indicating that this symbol is not defined.
  For function/global symbols, must match whether the symbol is an import or
  is defined; for data symbols, determines whether a segment is specified.

For `WASM_COMDAT_INFO` the following fields are present in the
subsection:

| Field   | Type        | Description                                    |
| ------- | ----------- | ---------------------------------------------- |
| count   | `varuint32` | Number of `Comdat` in `comdats`                |
| comdats | `Comdat*`   | Sequence of `Comdat`

where a `Comdat` is encoded as:

| Field       | Type         | Description                               |
| ----------- | ------------ | ----------------------------------------- |
| name_len    | `varuint32`  | length of `name_str` in bytes             |
| name_str    | `bytes`      | UTF-8 encoding of the name                |
| flags       | `varuint32`  | Must be zero, no flags currently defined  |
| count       | `varuint32`  | Number of `ComdatSym` in `comdat_syms`    |
| comdat_syms | `ComdatSym*` | Sequence of `ComdatSym`                   |

and where a `ComdatSym` is encoded as:

| Field    | Type           | Description                                 |
| -------- | -------------- | ------------------------------------------- |
| kind     | `varuint32`    | Type of symbol, one of:                     |
|          |                |   * `0 / WASM_COMDATA_DATA`, a data segment |
|          |                |   * `1 / WASM_COMDATA_FUNCTION`             |
|          |                |   * `2 / WASM_COMDATA_GLOBAL`               |
| index    | `varuint32`    | Index of the data segment/function/global in the Wasm module (depending on kind).  The function/global must not be an import. |


Merging Global Sections
-----------------------

Merging of the global sections requires the re-numbering of globals.  This
follows the normal rules for defining symbols: if two object files provide the
same global symbol strongly, there is a link error; if two object files provide
the symbol weakly, one is chosen.

When creating non-relocatable output, the Wasm output shall have an import for
each undefined strong symbol, and an export for each defined symbol with
non-local linkage and non-hidden visibility.

The linker may provide certain symbols itself, even if not defined by any
object file.  For example, the `__stack_pointer` symbol may be provided at
link-time.


Merging Function Sections
-------------------------

Merging of the function sections requires the re-numbering of functions.  This
requires modification to code sections at each location where a function
index is embedded.  There are currently two ways in which function indices are
stored in the code section:

1. Immediate argument of the `call` instruction (calling a function)
2. Immediate argument of the `i32.const` instruction (taking the address of a
   function).

The immediate argument of all such instructions are stored as padded LEB128
such that they can be rewritten without altering the size of the code section.
For each such instruction a `R_WEBASSEMBLY_FUNCTION_INDEX_LEB` or
`R_WEBASSEMBLY_TABLE_INDEX_SLEB` `reloc` entry is generated pointing to the
offset of the immediate within the code section.

The same technique applies for all function calls whether the function is
imported or defined locally.

When creating non-relocatable output, the Wasm output shall have an import for
each undefined strong symbol, and an export for each defined symbol with
non-local linkage and non-hidden visibility.


Merging Data Sections
---------------------

Merging of data sections is performed by creating a new data section from the
data segments in the object files. Data symbols (C/C+ globals) are represented
in the object file as Wasm data segments with an associated data symbol, so
each linked data symbol pulls its associated data segment into the linked
output.

Segments are merged according their type: segments with a common prefix such as
`.data` or `.rodata` are merged into a single segment in the output data
section.

The output data section is formed, essentially, by concatenating the data
sections of the input files.  Since the final location in linear memory of any
given symbol (C global) is not known until link time, all references to global
addresses with the code and data sections generate `R_WEBASSEMBLY_MEMORY_ADDR_*`
relocation entries, which reference a data symbol, which in turn identifies the
segment and data within the segment.

Segments are linked as a whole, and a segment is either entirely included or
excluded from the link.


Processing Relocations
----------------------

The final code and data sections are written out with relocations applied.

`R_WEBASSEMBLY_TYPE_INDEX_LEB` relocations cannot fail.  The output Wasm file
shall contain a newly-synthesised type section which contains entries for all
functions and type relocations in the output.

`R_WEBASSEMBLY_TABLE_INDEX_SLEB` and `R_WEBASSEMBLY_TABLE_INDEX_I32` relocations
cannot fail.  The output Wasm file shall contain a newly-synthesised table,
which contains an entry for all defined or imported symbols referenced by table
relocations.  The output table elements shall begin at a non-zero offset within
the table, so that a `call_indirect 0` instruction is guaranteed to fail.
Finally, when processing table relocations for symbols which have neither an
import nor a definition (namely, weakly-undefined function symbols), the value
`0` is written out as the value of the relocation.

`R_WEBASSEMBLY_FUNCTION_INDEX_LEB` relocations may fail to be processed, in
which case linking fails.  This occurs if there is a weakly-undefined function
symbol, in which case there is no legal value that can be written as the target
of any `call` instruction.  The frontend must generate calls to undefined weak
symbols via a `call_indirect` instruction.

`R_WEBASSEMBLY_GLOBAL_INDEX_LEB` relocations may fail to be processed, in which
case linking fails.  This occurs if there is a weakly-undefined global symbol,
in which case there is no legal value that can be written as the target of any
`get_global` or `set_global` instruction.  The frontend must not weak globals
which may not be defined; a definition or import must exist for all global
symbols in the linked output.

`R_WEBASSEMBLY_MEMORY_ADDR_LEB`, `R_WEBASSEMBLY_MEMORY_ADDR_SLEB` and
`R_WEBASSEMBLY_MEMORY_ADDR_I32` relocations cannot fail.  The relocation's value
is the offset within the linear memory of the symbol within the output segment,
plus the symbol's addend.  If the symbol is undefined (whether weak or strong),
the value of the relocation shall be `0`.


[names_sec]: https://github.com/WebAssembly/design/blob/master/BinaryEncoding.md#name-section
