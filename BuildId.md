# Build ID
A Build ID (or debug info ID) is a value that uniquely identifies a build.
It is intended to capture the "meaning" or inputs of the build, and is usually
associated with debug info. So for example programs compiled from different sources
would have different build IDs, even if their generated code happened to be the same.
A common use case is when a build is created with debug info, and then the debug info is stripped 
before distribution and archived by the developer. If both the distributed and archived
version retain the build ID, then they can be matched, and the distributed version can be debugged or 
symbolized.

Because the build ID is usually intended to identify debug info, tools that
transform Wasm binaries will need to decide whether they will preserve, drop, or
recompute the build ID. Generally speaking, if a transformation would invalidate debug info
(for example, by rewriting the code section and changing the code offsets), then the tool
should drop or recompute the build ID. If a tool updates or regenerates debug info along
with its transformation, it should also generally update the build ID, since the debug
info no longer matches. Conversely, adding custom sections to a binary would generally
not require updating the build ID.

## Build ID Section
The Build ID section is a 
[custom section](https://webassembly.github.io/spec/core/binary/modules.html#custom-section)
and thus has no semantic effects and can be stripped at any time. It is named `build_id`
and has no restriction on where in the binary it can appear. It consists of only 2 fields:

| Field       | Type        | Description |
| ----------- | ----------- | ----------- |
| length      | `varuint32` | number of bytes that follow |
| id          | `bytes`     | sequence of bytes |

Unlike most "string" fields in wasm binaries, the `id` field is arbitrary binary data and is not 
required to be valid UTF-8.

## Implementation Notes
The exact size and method of generating the build ID is unspecified, other than that it should
be unique. GNU ld and LLVM lld support several different methods, including various types of
hashes (which include at least all the code, data, and debug info sections of the output),
a random UUID, and user-specified values. Hashing is generally the default because it is
deterministic for a given set of inputs.
