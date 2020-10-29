This document describes conventions regarding debugging.

# DWARF

It is a goal to support DWARF in WebAssembly, see
[the proposed additions to DWARF](https://yurydelendik.github.io/webassembly-dwarf/)
for how that is planned to work.

## External DWARF

That proposal allows keeping the DWARF information
[external to the wasm](https://yurydelendik.github.io/webassembly-dwarf/#external-DWARF).
When doing so, the main wasm file does not need to contain any debug info, and
instead has a custom section with the name `external_debug_info`. That section
contains:

| Field         | Type        | Description                        |
| ------------- | ----------- | ---------------------------------- |
| path_name_len | `varuint32` | Length of `path_name_str` in bytes |
| path_name_str | `bytes`     | Path to debug info file            |

`path_name` is the location of a file containing DWARF debug info. Note that it
may also contain the full wasm file as well, which can be simpler to handle
(and tends to have little downside, as DWARF size tends to be much bigger than
wasm size anyhow).

# Source maps

Adoption of DWARF is a fairly recent addition to WebAssembly, and many toolchains still
support an earlier [Source Map based debugging proposal](https://github.com/WebAssembly/design/pull/1051).
This proposal uses a mapping between locations in source files and an offset in the WebAssembly binary
stored in an external file in a format as defined by the [Source Map spec](https://sourcemaps.info/spec.html).

On the WebAssembly side, the URL of this Source Map file is stored in a custom section with the name
`sourceMappingURL`. That section contains:

| Field         | Type       | Description                       |
| ------------- | ---------- | --------------------------------- |
| url_name_len | `varuint32` | Length of `url_name_str` in bytes |
| url_name_str | `bytes`     | Path to the Source Map file       |
