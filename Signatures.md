# WebAssembly module signatures

This document describes a digital signature format specifically designed for WebAssembly modules.

It satisfies the following requirements:

- Is is possible to verify a module before execution.
- It is possible to add signed custom sections to an already signed module.
- It is possible to verify a subset of the module sections, at predefined boundaries.
- The entire module doesn't have to fit in memory in order for a signature to be verified.
- Signatures can be embedded in a custom section, or provided separately ("detached signatures").
- Multiple signatures and algorithms can be used to sign a single module.
- Signing an entire module doesn't require the module to be modified.

Signatures have no semantic effects. A runtime that doesn't support signatures can ignore them.

Note: this is still a work in progress.

## Discussion venues

The [WebAssembly Modules Signatures](https://github.com/wasm-signatures/design) repository is the main discussion venue for this project.

We also hold bimonthly open meetings. See the above repository for details.

## Custom sections

Two custom section types are required for this signature format:

- Custom sections named `signature`, storing signature data, when this information is embedded in the module.
- Custom sections named `signature_delimiter`, separating consecutive sections that can be signed and verified independently.

Example structure of a module with an embedded signature and delimiters:

| sections                                  |
| ----------------------------------------- |
| signature                                 |
| part _(one or more consecutive sections)_ |
| delimiter                                 |
| part _(one or more consecutive sections)_ |
| delimiter                                 |
| ...                                       |
| part _(one or more consecutive sections)_ |
| delimiter                                 |

## Parts and delimiters

A module can be split into one or more parts (one or more consecutive sections).
Each part is followd by a delimiter. A delimiter is a custom section named `signature_delimiter`, containing a 16 byte random string.

| sections                                       |
| ---------------------------------------------- |
| `p1` = input part 1 _(one or more sections)_   |
| `d1` = delimiter 1                             |
| `p2` = input part 2 _(one or more sections)_   |
| `d2` = delimiter 2                             |
| ...                                            |
| `pn` = input part `n` _(one or more sections)_ |
| `dn` = delimiter `n`                           |

If a signature covers the entire module (i.e. there is only one part), the delimiter is optional.

However, its absence prevents additional sections to be added and signed later.

## Signature data

The signature data is a concatenation of the following:

- An identifier representing the version of the specification the module was signed with.
- An identifier representing the hash function whose output will be signed.
- A sequence of hashes and their signatures.

A hash is computed for all the parts to be signed:

`hn = H(pn‖dn)`

A signature is computed on the concatenation of these hashes:

`hashes = h1 ‖ h2 ‖ … ‖ hn`

`s = Sign(k, "wasmsig" ‖ spec_version ‖ hash_id ‖ hashes)`

One or more signatures can be associated with `hashes`, allowing multiple parties to sign the same data.

The signature data can either be stored in the payload of a custom section named `signature`, or provided separately.

If embedded in a module, the section must be the first section of the module.

The signature data contains a sequence of signatures, where the end of the last signature must coincide with the last byte of the data.

| Field               | Type        | Description                                   |
| ------------------- | ----------- | --------------------------------------------- |
| spec_version        | `byte`      | Specification version (`0x01`)                |
| hash_fn             | `byte`      | Hash function identifier (`0x01` for SHA-256) |
| signed_hashes_count | `varuint32` | Number of signed hashes                       |
| signed_hashes*      | `byte`      | Sequence of hashes and their signatures       |

where `signed_hashes` is encoded as:

| Field           | Type         | Description                                       |
| --------------- | ------------ | ------------------------------------------------- |
| hashes_count    | `varuint32`  | Number of the concatenated hashes in bytes        |
| hashes          | `bytes`      | Concatenated hashes of the signed sections        |
| signature_count | `varuint32`  | Number of signatures                              |
| signatures      | `signature*` | Sequence of `signature_count` `signature` records |

where a `signature` is encoded as:

| Field         | Type        | Description                                                |
| ------------- | ----------- | ---------------------------------------------------------- |
| key_id_len    | `varuint32` | Public key identifier length in bytes (can be `0`)         |
| key_id        | `bytes`     | Public key identifier                                      |
| signature_len | `varuint32` | Signature length in bytes                                  |
| signature     | `bytes`     | Signature for `hashes` that can be verified using `key_id` |

## Signature verification algorithm for an entire module

1. Verify the presence of the signature section, extract the specification version, the hash function to use and the signatures.
2. Check that at least one of the signatures is valid for `hashes`. If not, return an error and stop.
3. Split `hashes` (included in the signature) into `h1 … hn`
4. Read the module, computing the hash of every `(pi, di)` tuple with `i ∈ {1 … n}`, immediately returning an error if the output doesn't match `hi`
5. Return an error if the number of the number of hashes doesn't match the number of parts.

## Partial signatures

The above format is compatible with partial signatures, i.e. signatures ignoring one or more parts.

In order to do so, a signer only includes hashes of relevant parts.

## Partial verification

The format is compatible with partial verification, i.e. verification of an arbitrary subset of a module:

1. Verify the presence of the header, extract the specification version, the hash function to use and the signatures.
2. Check that at least one of the signatures is valid for `hashes`. If not, return an error and stop.
3. Split `hashes` (included in the signature) into `h1 … hm` with `m` being the last section to verify.
4. Read the module, computing the hash of the `(pi, di)` tuples to verify, immediately returning an error if the output doesn't match `hi`.
5. Return an error if the number of the number of hashes doesn't match the number of parts to verify.

Notes:

- Subset verification doesn't require additional signatures, as verification is always made using the full set `hashes`.
- Verifiers don't learn any information about removed sections due to delimiters containing random bits.

By default, partial signatures must be ignored by WebAssembly runtimes. An explicit configuration is required to accept a partially signed module.

## Equivalence between embedded and detached signatures

Signatures can be embedded in a module, or detached, i.e. not stored in the module itself but provided separately.

A detached signature is equivalent to the payload of a `signature` custom section.

Given an existing signed module with an embedded signature, the signature can be detached by:

- Copying the payload of the `signature` custom section
- Removing the `signature` custom section.

Reciprocally, a detached signature can be embedded by adding a `signature` custom section, whose payload is a copy of the detached signature.

Implementations should accept signatures as an optional parameter. If this parameter is not defined, the signature is assumed to be embedded, but the verification function remains the same.

## Algorithms and identifiers

Identifier for the current version of the specification: `0x01`

A conformant implementation must include support for the following hash functions:

| Function | Identifier |
| -------- | ---------- |
| SHA-256  | `0x01`     |

## Signature algorithms and key serialization

For interoperability purposes, a conformant implementation must include support for the following signature systems:

- Ed25519 (RFC8032)

Public and private keys must include the algorithm and parameters they were created for.

| Key type           | Serialized key size | Identifier |
| ------------------ | ------------------- | ---------- |
| Ed25519 public key | 1 + 32 bytes        | `0x01`     |
| Ed25519 key pair   | 1 + 64 bytes        | `0x81`     |

Representation of Ed25519 keys:

- Ed25519 public key:

`0x01 ‖ public key (32 bytes)`

- Ed25519 key pair:

`0x81 ‖ secret key (32 bytes) ‖ public key (32 bytes)`

Implementations may support additional signatures schemes and key encoding formats.

## Appendix A. Examples

The following examples assume the following unsigned module structure as a common starting point:

```text
0:	type section
1:	import section
2:	function section
3:	table section
4:	memory section
5:	global section
6:	export section
7:	element section
8:	code section
9:	data section
10:	custom section: [.debug_info]
11:	custom section: [.debug_macinfo]
12:	custom section: [.debug_loc]
13:	custom section: [.debug_ranges]
14:	custom section: [.debug_abbrev]
15:	custom section: [.debug_line]
16:	custom section: [.debug_str]
17:	custom section: [name]
18:	custom section: [producers]
```

### Signatures for the entire module.

Signed module structure:

```text
0:	custom section: [signature]
1:	type section
2:	import section
3:	function section
4:	table section
5:	memory section
6:	global section
7:	export section
8:	element section
9:	code section
10:	data section
11:	custom section: [.debug_info]
12:	custom section: [.debug_macinfo]
13:	custom section: [.debug_loc]
14:	custom section: [.debug_ranges]
15:	custom section: [.debug_abbrev]
16:	custom section: [.debug_line]
17:	custom section: [.debug_str]
18:	custom section: [name]
19:	custom section: [producers]
20:	custom section: [signature_delimiter]
```

Content of the signature section, for a single signature:

- `0x01` (spec_version)
- `0x01` (hash_fn)
- `1` (signed_hashes_count)
- signed_hashes:
  - `1` (hashes_count)
  - `<32 bytes>` (hashes=SHA-256(sections 1..end))
  - `1` (`signatures_count`)
  - signature:
    - `0` (`key_id_len` - no key ID)
    - `65` (`signature_len`)
    - `<65 bytes>` (0x01 ‖ Ed22519(k, hashes))

### Signatures allowing partial verification.

In this example, a signature can be verified for any of the following ranges of sections:

- 1..10 (until the custom sections)
- 1..17 (code, data and debugging information)
- 1..end (entire module)

```text
0:	custom section: [signature]
1:	type section
2:	import section
3:	function section
4:	table section
5:	memory section
6:	global section
7:	export section
8:	element section
9:	code section
10:	data section
11:	custom section: [signature_delimiter]
12:	custom section: [.debug_info]
13:	custom section: [.debug_macinfo]
14:	custom section: [.debug_loc]
15:	custom section: [.debug_ranges]
16:	custom section: [.debug_abbrev]
17:	custom section: [.debug_line]
18:	custom section: [.debug_str]
19:	custom section: [signature_delimiter]
20:	custom section: [name]
21:	custom section: [producers]
22:	custom section: [signature_delimiter]
```

Content of the signature section, for a single signature:

- `0x01` (spec_version)
- `0x01` (hash_fn)
- `1` (signed_hashes_count)
- signed_hashes:
  - `3` (hashes_count)
  - `<96 bytes>` (hashes=SHA-256(sections 1..12) ‖ SHA-256(sections 1..20) ‖ SHA-256(sections 1..end))
  - `1` (signatures_count)
  - signature:
    - `0` (key_id_len - no key ID)
    - `65` (signature_len)
    - `<65 bytes>` (0x01 ‖ Ed22519(k, hashes))

Variant with two signatures for the same content and key identifiers:

- `0x01` (spec_version)
- `0x01` (hash_fn)
- `1` (signed_hashes_count)
- signed_hashes:
  - `3` (hashes_count)
  - `<96 bytes>` (hashes=SHA-256(sections 1..12) ‖ SHA-256(sections 1..20) ‖ SHA-256(sections 1..end))
  - `2` (signatures_count)
  - signature_1:
    - `5` (key_id_len)
    - `"first"` (key_id)
    - `65` (`signature_len`)
    - `<65 bytes>` (0x01 ‖ Ed22519(k_first, hashes))
  - signature_2:
    - `6` (key_id_len)
    - `"second"` (key_id)
    - `65` (`signature_len`)
    - `<65 bytes>` (0x01 ‖ Ed22519(k_second, hashes))
