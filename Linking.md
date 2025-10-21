# WebAssembly Object File Linking

This document describes the WebAssembly object file format and the ABI used for
statically linking them to produce an executable WebAssembly module. This is
currently implemented in the clang/LLVM WebAssembly
backend and other tools such as binaryen and wabt.  As mentioned in
[README](README.md), this is not part of the official WebAssembly specification
and other runtimes may choose to follow a different set of linking conventions.

## Overview

Each translation unit is compiled into a WebAssembly object file.  These files
are themselves valid WebAssembly module binaries but are not expected to be
directly executable and have certain additional constraints.  In order to
distinguish object files from executable WebAssembly modules the linker can
check for the presence of the ["linking"](#linking-metadata-section) custom
section which must exist in all object files.

The goal of the linker is to take one or more WebAssembly object files and merge
them into a single executable module.  In order to achieve this the following
tasks need to be performed:

- Merging of function sections (re-numbering functions)
- Merging of globals sections (re-numbering globals)
- Merging of event sections (re-numbering events)
- Merging of table sections (re-numbering tables)
- Merging of data segments (re-positioning data with [limitations](#limitations))
- Resolving undefined external references
- Synthesizing functions to call constructors and perform other initialization

The linking technique described here is designed to be fast, and avoids having
to disassemble the code section.  The extra metadata required by the linker
is stored in a custom ["linking"](#linking-metadata-section) section and zero or
more relocation sections whose names begin with "reloc.".  For each section that
requires relocation a "reloc" section will be present in the wasm file.  By
convention the reloc section names end with the name of the section that they 
refer to: e.g. "reloc.CODE" for code section relocations.  However, everything 
after the period is ignored and the specific target section is encoded in the 
reloc section itself.

The linker additionally checks that linked object files were built targeting
compatible feature sets. Unlike native targets, WebAssembly has no runtime
feature detection, and the presence of unsupported features causes a binary to
fail to validate. It is therefore important for the user to have explicit
control over the features used in the output binary and for the linker to
provide helpful errors when instructed to link incompatible or disallowed
features. This feature information is stored in a custom ["target feature
section"](#target-features-section).

## Relocation Sections

A relocation section is a user-defined section with a name starting with
"reloc." Relocation sections start with an identifier specifying which
section they apply to, and must be sequenced in the module after that
section.

Relocation sections can only target code, data and custom sections. All other
sections are synthetic sections: that is, rather than being `memcpy`'d into
place as the code and data sections are, they are created from scratch by the
linker.

The "reloc." custom sections must come after the
["linking"](#linking-metadata-section) custom section in order to validate
relocation indices.

Any LEB128-encoded values should be maximally padded so that they can be
rewritten without affecting the position of any other bytes. For instance, the
function index 3 should be encoded as `0x83 0x80 0x80 0x80 0x00`.

Relocations contain the following fields:

| Field     | Type                | Description                     |
| ----------| ------------------- | ------------------------------- |
| section   | `varuint32`         | the index of the target section |
| count     | `varuint32`         | count of entries to follow      |
| entries   | `relocation_entry*` | sequence of relocation entries  |

A `relocation_entry` begins with:

| Field    | Type                | Description                    |
| -------- | ------------------- | ------------------------------ |
| type     | `uint8`             | the relocation type            |
| offset   | `varuint32`         | offset of the value to rewrite (relative to the relevant section's contents: offset zero is immediately after the id and size of the section) |
| index    | `varuint32`         | the index of the symbol used (or, for `R_WASM_TYPE_INDEX_LEB` relocations, the index of the type) |

A relocation type can be one of the following:

- `0 / R_WASM_FUNCTION_INDEX_LEB` (since LLVM 10.0) - a function index encoded
as a 5-byte [varuint32]. Used for the immediate argument of a `call`
instruction.
- `1 / R_WASM_TABLE_INDEX_SLEB` (since LLVM 10.0) - a function table index
encoded as a 5-byte [varint32]. Used to refer to the immediate argument of a
`i32.const`  instruction, e.g. taking the address of a function.
- `2 / R_WASM_TABLE_INDEX_I32` (since LLVM 10.0) - a function table index
encoded as a [uint32], e.g. taking the address of a function in a static data
initializer.
- `3 / R_WASM_MEMORY_ADDR_LEB` (since LLVM 10.0) - a linear memory index
encoded as a 5-byte [varuint32]. Used for the immediate argument of a `load` or
`store` instruction, e.g. directly loading from or storing to a C++ global.
- `4 / R_WASM_MEMORY_ADDR_SLEB` (since LLVM 10.0) - a linear memory index
encoded as a 5-byte [varint32]. Used for the immediate argument of a `i32.const`
instruction, e.g. taking the address of a C++ global.
- `5 / R_WASM_MEMORY_ADDR_I32` (since LLVM 10.0) - a linear memory index
encoded  as a [uint32], e.g. taking the address of a C++ global in a static data
initializer.
- `6 / R_WASM_TYPE_INDEX_LEB` (since LLVM 10.0) - a type index encoded as
a 5-byte [varuint32], e.g. the type immediate in a `call_indirect`.
- `7 / R_WASM_GLOBAL_INDEX_LEB` (since LLVM 10.0) - a global index encoded as a
  5-byte [varuint32], e.g. the index immediate in a `get_global`.
- `8 / R_WASM_FUNCTION_OFFSET_I32` (since LLVM 10.0) - a byte offset within
code section for the specific function encoded as a [uint32]. The offsets start
at the actual function code excluding its size field.
- `9 / R_WASM_SECTION_OFFSET_I32` (since LLVM 10.0) - a byte offset from start
of the specified section encoded as a [uint32].
- `10 / R_WASM_EVENT_INDEX_LEB` (since LLVM 10.0) - an event index encoded as a
5-byte [varuint32]. Used for the immediate argument of a `throw` and `if_except`
  instruction.
- `13 / R_WASM_GLOBAL_INDEX_I32` (since LLVM 11.0) - a global index encoded as
[uint32].
- `14 / R_WASM_MEMORY_ADDR_LEB64` (since LLVM 11.0) - the 64-bit counterpart of
`R_WASM_MEMORY_ADDR_LEB`. A 64-bit linear memory index encoded as a 10-byte
[varuint64], Used for the immediate argument of a `load` or `store` instruction
on a 64-bit linear memory array.
- `15 / R_WASM_MEMORY_ADDR_SLEB64` (since LLVM 11.0) - the 64-bit counterpart
of `R_WASM_MEMORY_ADDR_SLEB`. A 64-bit linear memory index encoded as a 10-byte
[varint64]. Used for the immediate argument of a `i64.const` instruction.
- `16 / R_WASM_MEMORY_ADDR_I64` (since LLVM 11.0) - the 64-bit counterpart of
`R_WASM_MEMORY_ADDR`. A 64-bit linear memory index encoded as a [uint64], e.g.
taking the 64-bit address of a C++ global in a static data initializer.
- `18 / R_WASM_TABLE_INDEX_SLEB64` (in LLVM 12.0) - the 64-bit counterpart
of  `R_WASM_TABLE_INDEX_SLEB`. A function table index encoded as a 10-byte
[varint64]. Used to refer to the immediate argument of a `i64.const`
instruction, e.g. taking the address of a function in Wasm64.
- `19 / R_WASM_TABLE_INDEX_I64` (in LLVM 12.0) - the 64-bit counterpart of
`R_WASM_TABLE_INDEX_I32`. A function table index encoded as a [uint64], e.g.
taking the address of a function in a static data initializer.
- `20 / R_WASM_TABLE_NUMBER_LEB` (in LLVM 12.0) - a table number encoded as
a 5-byte [varuint32]. Used for the table immediate argument in the table.*
  instructions.
- `22 / R_WASM_FUNCTION_OFFSET_I64` (in LLVM 12.0) - the 64-bit counterpart
of `R_WASM_FUNCTION_OFFSET_I32`. A byte offset within code section for the
specific function encoded as a [uint64].
- `23 / R_WASM_MEMORY_ADDR_LOCREL_I32` (in LLVM 13.0) - a byte offset between
the relocating address and a linear memory index encoded as a [uint32]. Used
for pointer-relative addressing.
- `24 / R_WASM_TABLE_INDEX_REL_SLEB64` (in LLVM 13.0) - the 64-bit counterpart
of `R_WASM_TABLE_INDEX_REL_SLEB`. A function table index encoded as a 10-byte
[varint64].
- `26 / R_WASM_FUNCTION_INDEX_I32` (in LLVM 17.0) - a function index encoded as
a [uint32]. Used in custom sections for function annotations (`__attribute__((annotate(<name>)))`).

**Note**: Please note that the 64bit relocations are not yet stable and 
therefore, subject to change.

[varuint32]: https://github.com/WebAssembly/design/blob/master/BinaryEncoding.md#varuintn
[varuint64]: https://github.com/WebAssembly/design/blob/master/BinaryEncoding.md#varuintn
[varint32]: https://github.com/WebAssembly/design/blob/master/BinaryEncoding.md#varintn
[varint64]: https://github.com/WebAssembly/design/blob/master/BinaryEncoding.md#varintn
[uint32]: https://github.com/WebAssembly/design/blob/master/BinaryEncoding.md#uintn
[uint64]: https://github.com/WebAssembly/design/blob/master/BinaryEncoding.md#uintn

For `R_WASM_MEMORY_ADDR_*`, `R_WASM_FUNCTION_OFFSET_I32`, and
`R_WASM_SECTION_OFFSET_I32` relocations (and their 64-bit counterparts) the 
following field is additionally present:

| Field  | Type             | Description                         |
| ------ | ---------------- | ----------------------------------- |
| addend | `varint32`       | addend to add to the address        |

Note that for all relocation types, the bytes being relocated:
* from `offset` to `offset + 5` for LEB/SLEB relocations;
* from `offset` to `offset + 10` for LEB64/SLEB64 relocations;
* from `offset` to `offset + 4` for I32 relocations;
* or from `offset` to `offset + 8` for I64;

must lie within the section to which the relocation applies (as offsets are relative
to the section's contents, this means that they cannot be too large). In addition,
the bytes being relocated may not overlap the boundary between the section's chunks,
where such a distinction exists (it may not for custom sections).  For example, for
relocations applied to the CODE section, a relocation cannot straddle two
functions, and for the DATA section relocations must lie within a data element's
body.

## Linking Metadata Section

A linking metadata section is a user-defined section with the name
"linking".

The "linking" custom section must be after the [data
section](https://github.com/WebAssembly/design/blob/master/BinaryEncoding.md#data-section)
in order to validate data symbols.

A linking metadata section begins with a version number which is then followed
by a series of sub-sections laid out in the same way as the ["names"][names_sec]
section:

| Field       | Type          | Description                          |
| ----------- | ------------- | ------------------------------------ |
| version     | `varuint32`   | the version of linking metadata contained in this section. Currently: 2 |
| subsections | `subsection*` | sequence of `subsection`             |

This `version` allows for breaking changes to be made to the format described
here.  Tools can then choose to reject inputs containing unexpected versions.

Each `subsection` is encoded as:

| Field        | Type        | Description                          |
| ------------ | ----------- | ------------------------------------ |
| type         | `uint8`     | code identifying type of subsection  |
| payload_len  | `varuint32` | size of this subsection in bytes     |
| payload_data | `bytes`     | content of this subsection, of length `payload_len` |

The current list of valid `type` codes are:

- `5 / WASM_SEGMENT_INFO` - Extra metadata about the data segments.

- `6 / WASM_INIT_FUNCS` - Specifies a list of constructor functions to be called
  at startup. These constructors will be called in priority order after memory
  has been initialized.

- `7 / WASM_COMDAT_INFO` - Specifies the COMDAT groups of associated linking
  objects, which are linked only once and all together.

- `8 / WASM_SYMBOL_TABLE` - Specifies extra information about the symbols present
  in the module.

### Segment Info Subsection

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
| alignment    | `varuint32`  | The required alignment of the segment, encoded as a power of 2 |
| flags        | `varuint32`  | a bitfield containing flags for this segment  |

The current set of valid flag for segments are:
- `1 / WASM_SEGMENT_FLAG_STRINGS` - Signals that the segment contains only null terminated strings allowing the linker to perform merging.
- `2 / WASM_SEGMENT_FLAG_TLS` - The segment contains thread-local data. This means that a unique copy of this segment will be created for each thread.
- `4 / WASM_SEG_FLAG_RETAIN` - If the object file is included in the final link, the segment should be retained in the final output regardless of whether it is used by the program.

### Init Functions Subsection

For `WASM_INIT_FUNCS` the following fields are present in the
subsection:

| Field       | Type         | Description                           |
| ----------- | ------------ | ------------------------------------- |
| count       | `varuint32`  | number of init functions that follow  |
| functions   | `init_func*` | sequence of `init_func`               |

where an `init_func` is encoded as:

| Field        | Type        | Description                                                  |
| ------------ | ----------- | ------------------------------------------------------------ |
| priority     | `varuint32` | priority of the init function                                |
| symbol_index | `varuint32` | the symbol index of init function (*not* the function index) |

The `WASM_INIT_FUNC` subsection must come after the `WASM_SYMBOL_TABLE` subsection.

### Symbol Table Subsection

For `WASM_SYMBOL_TABLE` the following fields are present in the
subsection:

| Field  | Type            | Description                  |
| ------ | --------------- | ---------------------------- |
| count  | `varuint32`     | number of `syminfo` in infos |
| infos  | `syminfo*`      | sequence of `syminfo`        |

where a `syminfo` is encoded as:

| Field        | Type           | Description                                 |
| ------------ | -------------- | ------------------------------------------- |
| kind         | `uint8`        | The symbol type.  One of:                   |
|              |                |   `0 / SYMTAB_FUNCTION`                     |
|              |                |   `1 / SYMTAB_DATA`                         |
|              |                |   `2 / SYMTAB_GLOBAL`                       |
|              |                |   `3 / SYMTAB_SECTION`                      |
|              |                |   `4 / SYMTAB_EVENT`                        |
|              |                |   `5 / SYMTAB_TABLE`                        |
| flags        | `varuint32`    | a bitfield containing flags for this symbol |

For functions, globals, events and tables, we reference an existing Wasm object, which
is either an import or a defined function/global/event/table (recall that the operand of a
Wasm `call` instruction uses an index space consisting of the function imports
followed by the defined functions, and similarly `get_global` for global imports
and definitions and `throw` for event imports and definitions).

If a symbols refers to an import, and the
`WASM_SYM_EXPLICIT_NAME` flag is not set, then the name is taken from the
import; otherwise the `syminfo` specifies the symbol's name.

| Field        | Type           | Description                                 |
| ------------ | -------------- | ------------------------------------------- |
| index        | `varuint32`    | the index of the Wasm object corresponding to the symbol, which references an import if and only if the `WASM_SYM_UNDEFINED` flag is set  |
| name_len     | `varuint32` ?  | the optional length of `name_data` in bytes, omitted if `index` references an import |
| name_data    | `bytes` ?      | UTF-8 encoding of the symbol name, omitted if `index` references an import |

For data symbols:

| Field        | Type           | Description                                 |
| ------------ | -------------- | ------------------------------------------- |
| name_len     | `varuint32`    | the length of `name_data` in bytes          |
| name_data    | `bytes`        | UTF-8 encoding of the symbol name           |
| index        | `varuint32` ?  | the index of the data segment; provided if the symbol is defined |
| offset       | `varuint32` ?  | the offset within the segment; provided if the symbol is defined; must be <= the segment's size |
| size         | `varuint32` ?  | the size (which can be zero); provided if the symbol is defined; `offset + size` must be <= the segment's size |

For section symbols:

| Field        | Type           | Description                                 |
| ------------ | -------------- | ------------------------------------------- |
| section      | `varuint32`    | the index of the target section             |

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
  For non-data symbols, this must match whether the symbol is an import
  or is defined; for data symbols, determines whether a segment is specified.
- `0x20 / WASM_SYM_EXPORTED` - The symbol is intended to be exported from the
  wasm module to the host environment. This differs from the visibility flags
  in that it effects the static linker.
- `0x40 / WASM_SYM_EXPLICIT_NAME` - The symbol uses an explicit symbol name,
  rather than reusing the name from a wasm import. This allows it to remap
  imports from foreign WebAssembly modules into local symbols with different
  names.
- `0x80 / WASM_SYM_NO_STRIP` - The symbol is intended to be included in the
  linker output, regardless of whether it is used by the program.
- `0x100 / WASM_SYM_TLS` - The symbol resides in thread local storage.
- `0x200 / WASM_SYM_ABSOLUTE` - The symbol represents an absolute address. This
  means it's offset is relative to the start of the wasm memory as opposed to
  being relative to a data segment.

### COMDAT Info Subsection

For `WASM_COMDAT_INFO` the following fields are present in the
subsection:

| Field   | Type        | Description                                    |
| ------- | ----------- | ---------------------------------------------- |
| count   | `varuint32` | Number of `Comdat` in `comdats`                |
| comdats | `comdat*`   | Sequence of `Comdat`

where a `comdat` is encoded as:

| Field       | Type          | Description                               |
| ----------- | ------------- | ----------------------------------------- |
| name_len    | `varuint32`   | length of `name_str` in bytes             |
| name_str    | `bytes`       | UTF-8 encoding of the name                |
| flags       | `varuint32`   | Must be zero, no flags currently defined  |
| count       | `varuint32`   | Number of `comdat_sym` in `comdat_syms`   |
| comdat_syms | `comdat_sym*` | Sequence of `comdat_sym`                  |

and where a `comdat_sym` is encoded as:

| Field    | Type           | Description                                 |
| -------- | -------------- | ------------------------------------------- |
| kind     | `uint8`        | Type of symbol, one of:                     |
|          |                |   * `0 / WASM_COMDAT_DATA`, a data segment  |
|          |                |   * `1 / WASM_COMDAT_FUNCTION`              |
|          |                |   * `2 / WASM_COMDAT_GLOBAL`                |
|          |                |   * `3 / WASM_COMDAT_EVENT`                 |
|          |                |   * `4 / WASM_COMDAT_TABLE`                 |
|          |                |   * `5 / WASM_COMDAT_SECTION`               |
| index    | `varuint32`    | Index of the data segment/function/global/event/table in the Wasm module (depending on kind). The function/global/event/table must not be an import. |

## Target Features Section

The target features section is an optional custom section with the name
"target_features". The target features section must come after the
["producers"](./ProducersSection.md) section.

The contents of the target features section is a vector of entries:

| Field   | Type    | Description                              |
| ------- | ------- | ---------------------------------------- |
| prefix  | `byte`  | See below.                               |
| feature | `bytes` | The name of the feature. Must be unique. |

The recognized prefix bytes and their meanings are below. When the user does not
supply a set of allowed features explicitly, the set of allowed features is
taken to be the set of used features. Any feature not mentioned in an object's
target features section is not used by that object, but is not necessarily
prohibited in the final binary.

| Prefix     | Meaning |
| ---------- | ------- |
| 0x2b (`+`) | This object uses this feature, and the link fails if this feature is not in the allowed set. |
| 0x2d (`-`) | This object does not use this feature, and the link fails if this feature is in the allowed set. |

The generally accepted features are:

1. `atomics`
1. `bulk-memory`
1. `bulk-memory-opt`
1. `call-indirect-overlong`
1. `exception-handling`
1. `extended-const`
1. `memory64`
1. `multimemory`
1. `multivalue`
1. `mutable-globals`
1. `nontrapping-fptoint`
1. `reference-types`
1. `relaxed-simd`
1. `sign-ext`
1. `simd128`
1. `tail-call`

These features generally correspond to feature proposals as standardized in the CG with two exceptions:
`bulk-memory-opt` refers to the `memory.copy` and `memory.fill` operations (a subset of `bulk-memory`).
`call-indirect-overlong` allows the table field of the `call_indirect` instruction to be encoded
as an LEB (which allows multibyte "overlong" encodings of small integers); this is a subset of the
`reference-types` proposal.

## Merging Global Sections

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

## Merging Event Sections

Events are meant to represent various control-flow changing constructs of wasm.
Currently, we have a
[proposal](https://github.com/WebAssembly/exception-handling/blob/master/proposals/exception-handling/Exceptions.md)
for one kind of events: exceptions, but the event section can be used to support
other kinds of events in future as well. The event section is a list of declared
events associated with the module.

Merging of the event sections requires the re-numbering of events. This follows
the normal rules for defining symbols: if two object files provide the same
event symbol strongly, there is a link error; if two object files provide the
symbol weakly, one is chosen.

When creating non-relocatable output, the Wasm output shall have an import for
each undefined strong symbol, and an export for each defined symbol with
non-local linkage and non-hidden visibility.

## Merging Function Sections

Merging of the function sections requires the re-numbering of functions.  This
requires modification to code sections at each location where a function
index is embedded.  There are currently two ways in which function indices are
stored in the code section:

1. Immediate argument of the `call` instruction (calling a function)
2. Immediate argument of the `i32.const` instruction (taking the address of a
   function).

The immediate argument of all such instructions are stored as padded LEB128 such
that they can be rewritten without altering the size of the code section.  For
each such instruction a `R_WASM_FUNCTION_INDEX_LEB` or `R_WASM_TABLE_INDEX_SLEB`
`reloc` entry is generated pointing to the offset of the immediate within the
code section.

The same technique applies for all function calls whether the function is
imported or defined locally.

When creating non-relocatable output, the Wasm output shall have an import for
each undefined strong symbol, and an export for each defined symbol with
non-local linkage and non-hidden visibility.

## Merging Data Sections

Merging of data sections is performed by creating a new data section from the
data segments in the object files. Data symbols (e.g. C/C+ globals) are
represented in the object file as Wasm data segments with an associated data
symbol, so each linked data symbol pulls its associated data segment into the
linked output.

Segments are merged according their type: segments with a common prefix such as
`.data` or `.rodata` are merged into a single segment in the output data
section. It is an error if this behavior would merge shared and unshared
segments.

The output data section is formed, essentially, by concatenating the data
sections of the input files.  Since the final location in linear memory of any
given symbol is not known until link time, all references to data addresses with
the code and data sections generate `R_WASM_MEMORY_ADDR_*` relocation entries,
which reference a data symbol.

Segments are linked as a whole, and a segment is either entirely included or
excluded from the link.

## Merging Custom Sections

Merging of custom sections is performed by concatenating all payloads for the
customs sections with the same name. The section symbol will refer the resulting
section, this means that the relocation entries addend that refer
the referred custom section fields shall be adjusted to take new offset
into account.

## COMDATs

A COMDAT group may contain one or more functions, data segments, and/or custom sections.
The linker will include all of these elements with a given group name from one object file,
and will exclude any element with this group name from all other object files.

## Processing Relocations

The final code and data sections are written out with relocations applied.

`R_WASM_TYPE_INDEX_LEB` relocations cannot fail.  The output Wasm file
shall contain a newly-synthesised type section which contains entries for all
functions and type relocations in the output.
`R_WASM_TABLE_INDEX_*` relocations cannot fail.  The output Wasm file shall
contain a newly-synthesised table, which contains an entry for all defined or
imported symbols referenced by table relocations.  The output table elements
shall begin at a non-zero offset within the table, so that a `call_indirect 0`
instruction is guaranteed to fail.  Finally, when processing table relocations
for symbols which have neither an import nor a definition (namely,
weakly-undefined function symbols), the value `0` is written out as the value
of the relocation.

`R_WASM_FUNCTION_INDEX_LEB` relocations may fail to be processed, in
which case linking fails.  This occurs if there is a weakly-undefined function
symbol, in which case there is no legal value that can be written as the target
of any `call` instruction.  The frontend must generate calls to undefined weak
symbols via a `call_indirect` instruction.

`R_WASM_GLOBAL_INDEX_LEB` relocations may fail to be processed, in which
case linking fails.  This occurs if there is a weakly-undefined global symbol,
in which case there is no legal value that can be written as the target of any
`get_global` or `set_global` instruction. (This means the frontend must not
generate weak globals which may not be defined; a definition or import must
exist for all global symbols in the linked output.)

`R_WASM_MEMORY_*` relocations cannot fail.  The relocation's value is the offset
within the linear memory of the symbol within the output segment, plus the
symbol's addend.  If the symbol is undefined (whether weak or strong), the value
of the relocation shall be `0`.

`R_WASM_FUNCTION_OFFSET_I32` relocations cannot fail. The values shall be
adjusted to reflect new offsets in the code section.

`R_WASM_SECTION_OFFSET_I32` relocation cannot fail. The values shall be
adjusted to reflect new offsets in the combined sections.

`R_WASM_EVENT_INDEX_LEB` relocations may fail to be processed, in which
case linking fails. This occurs if there is a weakly-undefined event symbol, in
which case there is no legal value that can be written as the target of any
`throw` and `if_except` instruction. (This means the frontend must not generate
weak events which may not be defined; a definition or import must exist for all
event symbols in the linked output.)

[names_sec]: https://github.com/WebAssembly/design/blob/master/BinaryEncoding.md#name-section

## Start Section

By default the static linker should not output a WebAssembly start
section. Constructors are instead called from a synthetic function
`__wasm_call_ctors` that the runtime and embedder should arrange to have called
after instantiation. `__wasm_call_ctors` is not exported by default because it
may be called by some other startup function defined by the runtime. For the
embedder to call it directly it should be exported like any other function.

Rationale: Use of the WebAssembly start function was considered for running
static constructors and/or the main entry point to the program.  However,
running arbitrary code in the start section is currently problematic due to the
fact the module exports not available to the embedder at the time when the start
function runs.  A common example is the module memory itself.  If the code in
the start function wants to transfer any data to the embedder (e.g. `printf`)
this will not work as the embedded cannot yet access the modules memory.  This
extends to all embedder functions that might want to call back into the module.

If some future version of the WebAssembly spec allows for module exports to be
available during execution of the start function it will make sense to
reconsider this.

When shared memory is requested, a start function will be emitted to initialize
memory as described below.

## Experimental Threading Support

By default all atomics and TLS are currently lowered to WebAssembly MVP and
threads are not supported.  However, when enabled, llvm does support an
exprimental multithreading ABI based on the WebAssembly threads proposal.  These
features are used to support threading in Emscripten.

The next section describes compatibility between threading features and MVP, and
the following sections describe shared memory and TLS implementation based on
bulk memory and experimental threading support.

### Lowering Atomics and TLS to MVP

MVP WebAssembly does not include support for atomic operations or the bulk
memory operations necessary to implement thread-local storage. As a result, any
atomics or TLS present at the source level must be lowered to non-atomic
operations and normal storage when targeting MVP WebAssembly. This is safe as
long as the resulting MVP object files are not used in a multi-threaded context.

To enforce this safety guarantee, the linker will error out if a shared memory
is requested but the `atomics` target feature is disallowed in the target
features section of any input objects. The compiler is responsible for marking
`atomics` disallowed and thereby preventing thread-unsafe linking if either
atomic operations or TLS are stripped during compilation. If the compiler
removes either one of atomic operations or TLS, the resulting object may only be
used with a single thread with an unshared memory, so the other one should be
removed as well.

If `atomics` or `bulk-memory` is not available during compilation but the source
does not contain atomic operations or TLS, then the result is a
"thread-agnostic" object that neither uses nor disallows the `atomics` feature.
Thread-agnostic objects can be safely linked with objects that do or do not use
`atomics`, although not both at the same time.

### Shared Memory and Passive Segments

When shared memory is enabled, all data segments will be emitted as [passive
segments][passive_segments] to prevent each thread from reinitializing
memory. In a web context, using active segments would cause memory to be
reinitialized every time the module is instantiated on a new WebWorker as part
of spawning a new thread. The `memory.init` instructions that initialize these
passive segments and the `data.drop` instructions that mark them collectible
will be emitted into a synthetic function `__wasm_init_memory` that is made the
WebAssembly start function and called automatically on instantiation but is not
exported. `__wasm_init_memory` shall perform any synchronization necessary to
ensure that no thread returns from instantiation until memory has been fully
initialized, even if a module is instantiated on multiple threads
simultaneously. This synchronization may involve waiting, but waiting is
disallowed in some Web contexts such as on the main thread or in Audio worklets.
For instantiation to succeed on all threads, the embedder must guarantee for
each thread in a context that disallows waiting that the thread either wins the
race and becomes responsible for initializing memory or that it is initialized
after memory has already been initialized[1]. To make the `memory.init` and
`data.drop` instructions valid, a [DataCount section][datacount_section] will
also be emitted.

Note that `memory.init` and the DataCount section are features of the
bulk-memory proposal, not the atomics proposal, so any engine that supports
threads needs to support both of these proposals.

[1] In LLVM 13 and earlier, embedders had to guarantee that threads on contexts
that disallow waiting had to win the race to initialize memory. That meant that
there could only be one such thread in the system.

[passive_segments]: https://github.com/WebAssembly/bulk-memory-operations/blob/master/proposals/bulk-memory-operations/Overview.md#design
[datacount_section]: https://github.com/WebAssembly/bulk-memory-operations/blob/master/proposals/bulk-memory-operations/Overview.md#datacount-section

### Thread Local Storage

Currently, thread-local storage is only supported in the main WASM module
and cannot be accessed outside of it. This corresponds to the ELF local
exec TLS model.

Additionally, thread local storage depends on bulk memory instructions, and
therefore support depends on the bulk memory proposal.

All thread local variables will be merged into one passive segment called
`.tdata`. This section contains the starting values for all TLS variables.
The thread local block of every thread will be initialized with this segment.

In a threaded build, the linker will create:

* an immutable global variable of type `i32` called `__tls_size`.
  Its value is the total size of the thread local block for the module,
  i.e. the sum of the sizes of all thread local variables plus padding.
  This value will be `0` if there are no thread-local variables.
* an immutable global variable of type `i32` called `__tls_align`.
  Its value is the alignment requirement of the thread local block, in bytes,
  and will be a power of 2. The value will be `1` if there are no thread-local
  variables.
* a mutable global `i32` called `__tls_base`, with a `i32.const 0` initializer.
* a global function called `__wasm_init_tls` with signature `(i32) -> ()`.

To initialize thread-local storage, a thread should do the equivalent of the
following pseudo-code upon startup:

    (if (global.get __tls_size) (then
      (call __wasm_init_tls
        (call aligned_alloc
          (global.get __tls_align)
          (call roundUpToMultipleOf
            (global.get __tls_align)
            (global.get __tls_size))))))

`__wasm_init_tls` takes a pointer argument containing the memory block to use
as the thread local storage block of the current thread. It should do nothing if
there are no thread-local variables. Otherwise, the memory block will be
initialized with the passive segment `.tdata` via the `memory.init` instruction.
It will then set `__tls_base` to the address of the memory block passed to
`__wasm_init_tls`.

Note that `__tls_size` is not necessarily a multiple of `__tls_align`. In order to
use `aligned_alloc`, we must round the size up to be a multiple of `__tls_align`.

The relocations for thread local variables shall resolve into offsets relative to
the start of the TLS block. As such, adding the value of `__tls_base` yields the
actual address of the variable. For example, a variable called `tls_var` would
have its address computed as follows:

    (i32.add (global.get __tls_base) (i32.const tls_var))

The variable can then be used as normal. Upon thread exit, the runtime should free
the memory allocated for the TLS block.

### Limitations

- There is currently no support for passive data segments. The relocation types
necessary for referencing such segments (e.g. in `data.drop` or `memory.init`
instruction) do not yet exist.
- There is currently no support for table element segments, either active or
passive.

# Text format

The text format for linking metadata is intended for WAT consumers that wish to
emit relocatable object files, and WAT producers wish to emit human-readable
relocation metadata for later creation of a relocatable object file.

## Relocations

Relocations are represented as WebAssembly annotations of the form
```wat
(@reloc <format> <method> <modifier> <symbol-reference> <addend>)
```

- `format` determines the resulting format of a relocation

|`<format>`| corresponding relocation constants | interpretation      |
|----------|------------------------------------|---------------------|
|`i32`     | `R_WASM_*_I32`                     | 4-byte [uint32]     |
|`i64`     | `R_WASM_*_I64`                     | 8-byte [uint64]     |
|`leb`     | `R_WASM_*_LEB`                     | 5-byte [varuint32]  |
|`sleb`    | `R_WASM_*_SLEB`                    | 5-byte [varint32]   |
|`leb64`   | `R_WASM_*_LEB64`                   | 10-byte [varuint64] |
|`sleb64`  | `R_WASM_*_SLEB64`                  | 10-byte [varint64]  |

- `method` describes the type of relocation, so what kind of symbol we are relocating against and how to interpret that symbol.

| `<method>`  | symbol kind | corresponding relocation constants | interpretation                    |
|-------------|-------------|------------------------------------|-----------------------------------|
| `tag`       | event*      | `R_WASM_EVENT_INDEX_*`             | Final WebAssembly event index     |
| `table`     | table*      | `R_WASM_TABLE_NUMBER_*`            | Final WebAssembly table index (index of a table, not into one) |
| `global`    | global*     | `R_WASM_GLOBAL_INDEX_*`            | Final WebAssembly global index    |
| `func`      | function*   | `R_WASM_FUNCTION_INDEX_*`          | Final WebAssembly function index  |
| `functable` | function    | `R_WASM_TABLE_INDEX_*`             | Index into the dynamic function table, used for taking address of functions |
| `codeseg`   | function    | `R_WASM_FUNCTION_OFFSET`           | Offset into the function body from the start of the function |
| `codesec`   | function    | `R_WASM_SECTION_OFFSET`            | Offset into the function section  |
| `datasec`   | data        | `R_WASM_SECTION_OFFSET`            | Offset into the data section      |
| `customsec` | N/A         | `R_WASM_SECTION_OFFSET`            | Offset into a custom section      |
| `data`      | data        | `R_WASM_MEMORY_ADDR_*`             | WebAssembly linear memory address |

Symbol kinds marked with `*` are considered *primary*.

- `modifier` describes the additional attributes that a relocation might have.

| `<modifier>` | corresponding relocation constants    | interpretation    |
|--------------|---------------------------------------|-------------------|
| nothing      | nothing                               | Normal relocation |
| `pic`        | `R_WASM_*_LOCREL_*`, `R_WASM_*_REL_*` | Address relative to `env.__memory_base` or `env.__table_base`, used for dynamic linking |
| `tls`        | `R_WASM_*_TLS*`                       | Address relative to `env.__tls_base`, used for thread-local storage |

- `addend` describes the additional components of a relocation.

| `<addend>`   | interpretation       | condition                                     |
|--------------|----------------------|-----------------------------------------------|
| nothing      | Zero addend          | always                                        |
| `+<integer>` | Positive byte offset | `method` allows addend                        |
| `-<integer>` | Negative byte offset | `method` allows addend and `format` is signed |
| `<labeluse>` | Byte offest to label | `method` is either `codeseg` or `*sec`        |

- `symbol` describes the symbol against which to perform relocation.
  - For `funcsec` relocation method, this is the function id, so that if the
    addend is zero, the relocation points to the first instruction of that
    function.
  - For `datasec` relocation method, this is the data segment id, so that if
    the addend is zero, the relocation points to the first byte of data in that
    segment.
  - For `customsec` relocation method, this is the name of the custom section,
    so that if the addend is zero, the relocation points to the first byte of
    data in that segment.
  - For other relocation methods, this denotes the symbol in the scope of that
    symbol kind.

The relocation type is looked up from the combination of `format`, `method`,
and `modifier`. If no relocation type exists, an error is raised.

If a component of a relocation is predetermined, it must be skipped in the
annotation text.

If a component of a relocation is defaulted, it may be skipped in the
annotation text.

For example, a relocation into the function table by the index of `$foo` with a
predetermined `format` would look like following:
```wat
(@reloc functable $foo)
```
If all components of a relocation annotation are skipped, the annotation may be
omitted.

### Instruction relocations

For every usage of `typeidx`, `funcidx`, `globalidx`, `tagidx`, a relocation
annotation is added afterwards, with `format` predefined as `leb`, `method`
predefined as the *primary* method for that type, and `symbol` defaulted as the
*primary* symbol of that `idx`

- For the `i32.const` instruction, a relocation annotation is added after the
  integer literal operand, with `format` predefined as `sleb`, and `method` is
  allowed to be either `data` or `functable`.
- For the `i64.const` instruction, a relocation annotation is added after the
  integer literal operand, with `format` predefined as `sleb64`, and `method`
  is allowed to be either `data` or `functable`.
- For the `i{32,64}.{load,store}*` instructions, a relocation annotation is
  added after the offset operand, with `format` predefined as `leb` if the
  *memory* being referenced is 32-bit, and `leb64` otherwise, and `method`
  predefined as `data`.

### Data relocations

In data segments, relocation annotations can be interleaved into the data
string sequence. When that happens, relocations are situated after the last
byte of the value being relocated.

For example, relocation of a 32-bit function pointer `$foo` and a 32-bit
reference to a data symbol `$bar` into the data segment of size 8 would look
like following:
```wat
(data (i32.const 0) "\00\00\00\00" (@reloc i32 functbl $foo) "\00\00\00\00" (@reloc i32 data $bar))
```

## Symbols

For each relocatable WebAssembly entity type, there exists a corresponding
symbol identifier namespaces for symbols of that type.

Additionally, a symbol identifier namespace exists for data symbols.

Symbol idenitfier namespaces differ from common index spaces in that they also
allow purely textual names in addition to numeric + optional textual names
allowed by index spaces.

Symbols are represented as WebAssembly annotations of the form
```wat
(@sym <name> <qualifier>*)
```
Data imports represented as WebAssembly annotations of the form
```wat
(@sym.import.data <name> <qualifier>*)
```

- `name` is the symbol name written as WebAssembly `id`, it is the name by
  which relocation annotations reference the symbol. If it is not present, the
  symbol is considered *primary* symbol for that WebAssembly object, its name
  is taken from the related object
  - There may only be one primary symbol for each WebAssembly object.
  - If a symbol is not associated with a WebAssembly entity, it may not be the
    primary symbol.

After a name for the symbol is determined, it is placed into the symbol
identifier namespace corresponding to that symbol type.

> [!Note]
> As a consequence of that, the only symbols that can be referred to by a
> numeric index are _primary_ symbols, since they inherit their numeric index
> form the relocatable WebAssebly object.

- `qualifier` is one of the allowed qualifiers on a symbol declaration.
  Qualifiers may not repeat.

| `<qualifier>`             | effect                                        |
|---------------------------|-----------------------------------------------|
| `binding=<binding>`       | sets symbol flags according to `<binding>`    |
| `visibility=<visibility>` | sets symbol flags according to `<visibility>` |
| `retain`                  | sets `WASM_SYM_NO_STRIP` symbol flag          |
| `thread_local`            | sets `WASM_SYM_TLS` symbol flag               |
| `size=<int>`              | sets symbol's `size` appropriately            |
| `offset=<int>`            | sets `WASM_SYM_ABSOLUTE` symbol flag, sets symbol's `offset` appropriately |
| `name=<string>`           | sets `WASM_SYM_EXPLICIT_NAME` symbol flag, sets symbol's `name_len`, `name_data` appropriately |
| `priority=<int>`          | adds symbol to `WASM_INIT_FUNCS` section with the given priority |
| `comdat=<id>`             | adds symbol to a `comdat` with the given id   |

| `<binding>` | flag                     |
|-------------|--------------------------|
| `global`    | 0                        |
| `local`     | `WASM_SYM_BINDING_LOCAL` |
| `weak`      | `WASM_SYM_BINDING_WEAK`  |

| `<visibility>` | flag                         |
|----------------|------------------------------|
| `default`      |                              |
| `hidden`       | `WASM_SYM_VISIBILITY_HIDDEN` |

Shorthands may be used in place of full qualifiers:

| shorthand | resulting qualifier |
|-----------|---------------------|
| `hidden`  | `visibility=hidden` |
| `local`   | `binding=local`     |
| `weak`    | `binding=weak`      |

- The `priority` qualifier may only be applied to function symbols.
- The `size` and `offset` qualifiers may only be applied to data symbols.
- The `size` and `name` qualifiers must be applied to data symbols.
- The `name` qualifier must be applied to data imports.

If all components of a symbol annotation are skipped, the annotation may be
omitted.

> [!Note]
> Since all components of a symbol can be skipped, a _primary_ symbol always
> exists for all WebAssembly entities, even if the annotation without a `name`
> is not present in the symbol sequence

### WebAssembly object symbols

For symbols related to WebAssembly objects, the symbol annotation sequence
occurs after the optional `id` of the declaration.

For example, the following code:
```wat
(import "env" "foo" (func (@sym $a retain name="a") (@sym $b hidden name="b") (param) (result)))
```
declares 3 symbols: one primary symbol with the name of the index of the
function, one symbol with the name `$a`, and one symbol with the name `$b`.

### Data symbols

Data symbol annotations can be interleaved into the data string sequence.
When that happens, relocations are situated before the first byte of the value
being defined.

For example, a declaration of a 32-bit global with the name `$foo` and linkage
name "foo" would look like following:
```wat
(data (i32.const 0) (@sym $foo name="foo" size=4) "\00\00\00\00")
```

### Data imports

Data imports occur in the same place as module fields. Data imports are always
situated before data symbols.

## COMDATs

COMDATs are represented as WebAssembly annotations of the form
```wat
(@comdat <id> <string>)
```
where `id` is the WebAssembly name of the COMDAT, and `<string>` is `name_len`
and `name_str` of the `comdat`.

COMDAT declarations occur in the same place as module fields.

## Labels

For some relocation types, an offset into a section/function is necessary. For
these cases, labels exsist.
Labels are represented as WebAssembly annotations of the form
```wat
(@sym.label <id>)
```

### Function labels
Function labels occur in the same place as instructions.
A label always denotes the first byte of the next instruction, or the byte
after the end of the function's instruction stream, if there isn't a next
instruction.

Function label names are local to the function in which they occur.

### Data labels
Data labels can be interleaved into the data string sequence.
When that happens, relocations are situated after the last byte of the value
being relocated.

Data label names are local to the data segment in which they occur.

### Custom labels
Custom labels can be interleaved into the data string sequence.
When that happens, relocations are situated after the last byte of the value
being relocated.

Custom label names are local to the custom section in which they occur.

## Data segment flags
Data segment flags are represented as WebAssembly annotations of the form
```wat
(@sym.segment <qualifier>*)
```

- `qualifier` is one of the allowed qualifiers on a data segment declaration.
Qualifiers may not repeat.

| `<qualifier>`   | effect                                               |
|-----------------|------------------------------------------------------|
| `align=<int>`   | sets segment's `alignment` appropriately             |
| `name=<string>` | sets segment's `name_len`, `name_data` appropriately |
| `strings`       | sets `WASM_SEGMENT_FLAG_STRINGS` segment flag        |
| `thread_local`  | sets `WASM_SEGMENT_FLAG_TLS` segment flag            |
| `retain`        | sets `WASM_SEG_FLAG_RETAIN` segment flag             |

If `align` is not specified, it is given a default value of 1.
If `name` is not specified, it is given an empty default value.

If all components of segment flags are skipped, the annotation may be omitted.

Data segment annotation occurs after the optional `id` of the data segment
declaration.
