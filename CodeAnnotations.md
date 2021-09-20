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
codeannotationsec(A) ::= vec(funcannotations(A))

funcannotations(A) ::= idx: funcidx
                    vec(annotation(A))

annotation(A) ::= funcpos: u32
               size: u32 (if size = ||A||)
               data: A
```

Where `funcpos` is the byte offset of the annotation starting from the beginning of the function,  and `data` is a further payload, whose content depends on the section type.

`funcannotations` entries must appear in order of increasing `idx`, and duplicate `idx` values are not allowed.
`codeannotation` entries must appear in order of increasing `funcpos`, and duplicate `funcpos` values are not allowed.

## Text Representation

Code annotations are representend in the .wat format using [custom annotations](https://github.com/WebAssembly/annotations), as follows:

```
(@code_annotation.<type> data:str)
```
The `data` fields correspond to the field with the same name in the binary representation.
The code position is implicit and it is derived by the position of the annotation:

Custom annotations can appear anywhere , but **code annotations** are allowed only before function definitions (in which case the code position is the offset of the start of the function body in the code section), or before an instruction (in which case the code position is the offset of the instruction in the code section).

Example:

```
(module
  (type (;0;) (func (param i32 result i32)))
  (func (@code_annotation.hotness "\1") $test (type 0)
    (@code_annotation.branch_hints "\0") if
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

- section name: `code_annotation.branch_hints`
- binary format:

```
annotation(branchhint) ::= funcpos: u32
               size: 0x01
               data: branchhint
branchhint: unlikely | likely
unlikely: 0x00
likely: 0x01
```

Branch hints can appear only before a `if` or `br_if` instruction, and are considered attached to it.
Code transformations that remove the instruction should remove the associated annotation, and transformations that flip the direction of the branch should preserve the hint but flip the hint.
