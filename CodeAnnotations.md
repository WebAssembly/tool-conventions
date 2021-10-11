# Code Annotations Framework

This document describe a convention for  encoding a number of WebAssembly features (here generically called "code annotations") that don't affect the module semantics.
The goal of this convention is to make it easier for tools that work on WebAssembly modules to handle and preserve  such code annotations.

Note: This is a work in progress

## Code Annotation

A code annotation is a piece of metadata attached to a position in the code section.

Its meaning depends on the particular type of annotation.

Discarding a code annotation does not change the semantics of the module.

A tool that transform the module must drop any code annotation that it does not know or know it can’t preserve.

## Binary Representation

Each type of code annotation is encoded in a custom section named `code_annotation.<type>`.

Such sections have the following binary format:

```
codeannotationsec(A) ::= section_0(codeannotationdata(A))

codeannotationdata(A) ::= n:name (if n = 'code_annotation.A')
                          vec(funcannotations(A))

funcannotations(A) ::= idx: funcidx
                       vec(annotation(A))

annotation(A) ::= funcpos: u32
                  size: u32 (if size = ||A||)
                  data: A
```

Where `funcpos` is the byte offset of the annotation starting from the beginning of the function body,  and `data` is a further payload, whose content depends on the section type `A`.

`funcannotations` entries must appear in order of increasing `idx`, and duplicate `idx` values are not allowed.
`codeannotation` entries must appear in order of increasing `funcpos`, and duplicate `funcpos` values are not allowed.

## Text Representation

Code annotations are representend in the .wat format using [custom annotations](https://github.com/WebAssembly/annotations), as follows:

```
(@code_annotation.<type> data:str)
```
The `data` fields correspond to the field with the same name in the binary representation.
The code position is implicit and it is derived by the position of the annotation:

Custom annotations can appear anywhere , but **code annotations** are allowed only in function definitions (in which case the code position is the offset of the start of the function body in the code section), or before an instruction (in which case the code position is the byte offset of the instruction relative to the beginning of the function body).

Example:

```
(module
  (type (;0;) (func (param i32 result i32)))
  (func (@code_annotation.hotness "\1") $test (type 0)
    (@code_annotation.branch_hint "\0") if
      i32.const 0
      local.set 0
    end
    local.get 1
    (@code_annotation.custom "aaa\13bb") return
  )
)
```

## Code annotation types

Currently the following type of code annotations are defined:

### Branch Hints

- section name: `code_annotation.branch_hint`
- binary format:

```
annotation(branch_hint) ::= funcpos: u32
               size: 0x01
               data: branchhint
branch_hint ::= unlikely | likely
unlikely ::= 0x00
likely ::= 0x01
```

Branch hints can appear only before a `if` or `br_if` instruction, and are considered attached to it.
Code transformations that remove the instruction should remove the associated annotation, and transformations that flip the direction of the branch should preserve the hint but flip the hint.

## Trace Instruction

- section name: code_annotation.trace_inst
- binary format:

```
annotation(trace_inst) ::= funcpos: u32
               size: 0x04
               data: mark_id
mark_id ::= u32
```

Trace marks can appear on any instruction and are considered attached to the instruction. If a code transformation reorders the instruction, the trace mark should move with it. If a code transformation removes the instruction, the trace mark should be removed.
