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
