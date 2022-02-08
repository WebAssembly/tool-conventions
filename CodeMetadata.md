# Code Metadata Framework

This document describe a convention for  encoding a number of WebAssembly features (here generically called "code metadata") that don't affect the module semantics.
The goal of this convention is to make it easier for tools that work on WebAssembly modules to handle and preserve such metadata.

Note: This is a work in progress

## Code Metadata

Each type of Code Metadata is identified by a name: `metadata.code.<type>`.

An instance of Code Metadata is defined by its type, a position in the code section,
and a payload.

The payload is a byte string, whose meaning depends on the type.

Removing Code Metadata from a module does not change its semantics.

A tool that transforms the module must drop any Code Metadata that it does not know, or knows it can’t preserve.

## Binary Representation

Each type of Code Metadata is encoded in a custom section named `metadata.code.<type>`.

Such sections have the following binary format:

```
codemetadatasec(A) ::= section_0(codemetadatacontent(A))

codemetadatacontent(A) ::= n:name (if n = 'metadata.code.A')
                          vec(codemetadatafunc(A))

codemetadatafunc(A) ::= idx: funcidx
                       vec(codemetadatainstance(A))

codemetadatainstance(A) ::= funcpos: u32
                  size: u32 (if size = ||A||)
                  data: A
```

Where `funcpos` is the byte offset of the annotation starting from the beginning of the function body,  and `data` is a further payload, whose content depends on the section type `A`.

`codemetadatafunc` entries must appear in order of increasing `idx`, and duplicate `idx` values are not allowed.
`codemetadatainstance` entries must appear in order of increasing `funcpos`, and duplicate `funcpos` values are not allowed.

## Text Representation

Code Metadata are represented in the .wat format using [custom annotations](https://github.com/WebAssembly/annotations), as follows:

```
(@metadata.code.<type> data:str)
```
The `data` fields correspond to the field with the same name in the binary representation.
The code position is implicit and it is derived by the position of the annotation:

Custom annotations can appear anywhere , but **Code Metadata annotations** are allowed only in function definitions (in which case the code position is the offset of the start of the function body in the code section), or before an instruction (in which case the code position is the byte offset of the instruction relative to the beginning of the function body).

Example:

```
(module
  (type (;0;) (func (param i32 result i32)))
  (func (@metadata.code.hotness "\1") $test (type 0)
    (@metadata.code.branch_hint "\0") if
      i32.const 0
      local.set 0
    end
    local.get 1
    (@metadata.code.custom "aaa\13bb") return
  )
)
```

## Code Metadata well-known types

Currently the following type of Code Metadata are defined:

### Branch Hints

- section name: `metadata.code.branch_hint`
- binary format:

```
codemetadatainstance(branch_hint) ::= funcpos: u32
               size: 0x01
               data: branchhint
branch_hint ::= unlikely | likely
unlikely ::= 0x00
likely ::= 0x01
```

Branch hints can appear only before a `if` or `br_if` instruction, and are considered attached to it.
Code transformations that remove the instruction should remove the associated instance, and transformations that flip the direction of the branch should preserve the hint but flip the hint.

## Trace Instruction

- section name: metadata.code.trace_inst
- binary format:

```
codemetadatainstance(trace_inst) ::= funcpos: u32
               size: 0x04
               data: mark_id
mark_id ::= u32
```

Trace marks can appear on any instruction and are considered attached to the instruction. If a code transformation reorders the instruction, the trace mark should move with it. If a code transformation removes the instruction, the trace mark should be removed.
