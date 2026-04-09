This document describes conventions regarding debugging.

# DWARF

For a detailed description of how to use DWARF debug information with
WebAssembly, see [Dwarf.md](Dwarf.md).

## Embedded DWARF

DWARF sections are embedded as WebAssembly custom sections with the same name
(`.debug_*`) and raw data as in the DWARF spec. See
[Embedding DWARF Within a WebAssembly File](Dwarf.md#embedding-dwarf-within-a-webassembly-file)
for details.

## External DWARF

DWARF information can also be kept external to the Wasm file. See
[External DWARF File](Dwarf.md#external-dwarf-file) for details.
When doing so, the main Wasm file does not need to contain any debug info, and
instead has a custom section with the name `external_debug_info`. That section
contains:

| Field        | Type        | Description                       |
| ------------ | ----------- | --------------------------------- |
| url_name_len | `varuint32` | Length of `url_name_str` in bytes |
| url_name_str | `bytes`     | URL to debug info file            |

`url_name` is the location of a file containing DWARF debug info. That file is
a Wasm container, which includes DWARF in Wasm custom sections, in the same
format as they would appear normally in a Wasm file. Note that the container may
also contain other sections, such as the code and data sections in the original
Wasm file.

# Source maps

Adoption of DWARF is a fairly recent addition to WebAssembly, and many toolchains still
support [Source Map](https://sourcemaps.info/spec.html) based debugging as well (or instead).

Source map is an external JSON file that specifies how to map a (zero-based) line and column
position in generated code to a file, line, and column location in the source. For
WebAssembly binary locations, the line number is always 1, and the column number
is interpreted as a byte offset into the WebAssembly binary content.
Source locations are interpreted as in the source map spec.

On the WebAssembly side, the URL of such Source Map file is stored in a custom section with the name
`sourceMappingURL`. That section contains:

| Field        | Type        | Description                       |
| ------------ | ----------- | --------------------------------- |
| url_name_len | `varuint32` | Length of `url_name_str` in bytes |
| url_name_str | `bytes`     | URL to the Source Map file        |
