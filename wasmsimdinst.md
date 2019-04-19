**WebAssembly Single Instruction Multiple Data Intrinsic Instructions**

# Table of Contents
1. [Introduction](#introduction)
2. [Proposed Vector Types](#proposed-vector-types)
3. [Load and Store Definitions](#load-and-store-definitions)
5. [Broadcast, Extract and Replace Definitions](#broadcast-extract-and-replace-definitions)
6. [Arithmetic Operations Definition](#arithmetic-operations-definition)
7. [Logical Operations Definition](#logical-operations-definition)
8. [Future Single Instruction Multiple Data Instructions](#future-single-instruction-multiple-data-instructions)

## **Introduction** <a name=introduction></a>
This document is a proposed list of WebAssembly Intrinsic Instructions for C/C++ Clang compiler and an explanation of some of the design decisions and current state of WebAssembly Intrinsics.

##### **Proposed Vector Types** <a name=proposed-vector-types></a>
The following is a proposed vector type.  In asking others I thought it could be defined like llvm does  i8x16  for i8x16 and u8x16 for u8x16 but there was a preference expressed for using the v notation for loads and stores so it was kept.

typedef v128 i8x16 __attribute__((__vector_size__(16)));
typedef int8_t i8x16 __attribute__((__vector_size__(16)));
typedef uint8_t u8x16 __attribute__((__vector_size__(16)));
typedef int16_t i16x8 __attribute__((__vector_size__(16)));
typedef uint16_t u16x8 __attribute__((__vector_size__(16)));
typedef int32_t i32x4 __attribute__((__vector_size__(16)));
typedef uint32_t u32x4 __attribute__((__vector_size__(16)));
typedef int64_t i64x2 __attribute__((__vector_size__(16)));
typedef uint64_t u64x2 __attribute__((__vector_size__(16)));
typedef float f32x4 __attribute__((__vector_size__(16)));
typedef double f64x2 __attribute__((__vector_size__(16)));

##### **Load and Store Definitions** <a name=load-and-store-definitions></a>
~~~
v128 wasm_v128_constant(...)
~~~
Loads v128 into a 128 bit vector

~~~
v128 wasm_v128_load(v128* mem)
~~~
Loads v128 into a 128 bit vector

~~~
wasm_v128_store(v128 *mem, v128 a)
~~~
Stores 128 bit vector into the memory location pointed to at mem

##### **Broadcast, Extract and Replace Definitions** <a name=broadcast-extract-and-replace-definitions></a>
~~~
i8x16 wasm_i8x16_splat(int8_t a)
~~~
Duplicates the value int8_t a into the i8x16 vector

~~~
i16x8 wasm_i16x8_splat(int16_t a)
~~~
Duplicates the value int16_t a into the i16x8 vector

~~~
i32x4 wasm_i32x4_splat(int32_t a)
~~~
Duplicates the value int32x4 a into the i32x4 vector

~~~
f32x4 wasm_f32x4_splat(float a)
~~~
Duplicates the value f32 a into the f32x4 vector

~~~
int8_t wasm_i8x16_extract_lane(i8x16 a, imm)
~~~
Extracts the int8_t element designated by the imm returning it as a int32_t

~~~
int16_t wasm_i16x8_extract_lane(i16x8 a, imm)
~~~
Extracts the int16_t element designated by the imm returning it as a int32_t

~~~
int32_t wasm_i32x4_extract_lane(i32x4 a, imm)
~~~
Extracts the int32_t element designated by the imm returning it as a int32_t

~~~
float wasm_f32x4_extract_lane(f32x4, imm)
~~~
Extracts the float element designated by the imm returning it as a float

~~~
i8x16 wasm_i8x16_replace_lane(i8x16 a, imm i, int32_t b)
~~~
Replaces the i8 element specified by the immediate i with the value of int32_t b (why not do i8?)

~~~
i16x8 wasm_i16x8_replace_lane(i16x8 a, imm i, int32_t b)
~~~
Replaces the i16 element specified by the immediate i with the value of int32_t b (why not do i16?)

~~~
i32x4 wasm_i32x4_replace_lane(i32x4 a, imm i, int32_t b)
~~~
Replaces the i32 element specified by the immediate i with the value of int32_t b

~~~
f32x4 wasm_f32x4_replace_lane(f32x4 a, imm i, float b)
~~~
Replaces the float element specified by the immediate i with the value of float b

##### **Arithmetic Operations Definition** <a name=arithmetic-operations-definition></a>

~~~
i8x16 wasm_i8x16_add(i8x16 a i8x16 b)
~~~
Adds i8x16 vector a  with i8x16 vector b returning a i8x16 vector

~~~
i16x8 wasm_i16x8_add(i16x8 a i16x8 b)
~~~
Adds i16x8 vector a  with i16x8 vector b returning a i16x8 vector

~~~
i32x4 wasm_i32x4_add(i32x4 a i32x4 b)
~~~
Adds i32x4 vector a  with i32x4 vector b returning a i32x4 vector

~~~
i8x16 wasm_i8x16_sub(i8x16 a, i8x16 b)
~~~
Subtracts i8x16 vector a  with i8x16 vector b returning a i8x16 vector

~~~
i16x8 wasm_i16x8_sub(i16x8 a i16x8 b)
~~~
Subtracts i16x8 vector a  with i16x8 vector b returning a i16x8 vector

~~~
i32x4 wasm_i32x4_sub(i32x4 a i32x4 b)
~~~
Subtracts i32x4 vector a  with i32x4 vector b returning a i32x4 vector

~~~
i8x16 wasm_add_saturate(i8x16 a, i8x16 b)
~~~
Adds the i8x16 vector a to i8x16 vector b saturating the signed results returning a i8x16 vector.

~~~
u8x16 wasm_add_saturate(u8x16 a, u8x16 b)
~~~
Add the u8x16 vector a to u8x16 vector b saturating the unsigned results returning a u8x16 vector.

~~~
i16x8 wasm_add_saturate(i16x8 a, i16x8 b)
~~~
Adds the i16x8 vector a to i16x8 vector b saturating the signed results returning a i16x8 vector.

~~~
u16x8 wasm_add_saturate(u16x8 a, u16x8 b)
~~~
Adds the u16x8 vector a to u16x8 vector b saturating the unsigned results returning a u16x8 vector.

~~~
i8x16 wasm_sub_saturate(i8x16 a, i8x16 b)
~~~
Subtracts the i8x16 vector a to i8x16 vector b saturating the signed results returning a i8x16 vector.

~~~
u8x16 wasm_sub_saturate(u8x16 a, u8x16 b)
~~~
Subtracts the u8x16 vector a to u8x16 vector b saturating the unsigned results returning a u8x16 vector.

~~~
i16x8 wasm_sub_saturate(i16x8 a, i16x8 b)
~~~
Subtracts the i16x8 vector a to i16x8 vector b saturating the signed results returning a i16x8 vector.

~~~
u16x8 wasm_sub_saturate(u16x8 a, u16x8 b)
~~~
Subtracts the u16x8 vector a to u16x8 vector b saturating the unsigned results returning a u16x8 vector.

~~~
i8x16 wasm_i8x16_mul(i8x16 a i8x16 b)
~~~
Multiplies the i8x16 vector a with i8x16 vector b returning a i8x16 vector. (Implemented not but sure the value but there maybe some use case)

~~~
i16x8 wasm_i16x8_mul(i16x8 a i16x8 b)
~~~
Multiplies the i16x8 vector a with i16x8 vector b returning a i16x8 vector.

~~~
i32x4 wasm_i32x4_mul(i32x4 a i32x4 b)
~~~
Multiplies the i32x4 vector a with i32x4 vector b returning a i32x4 vector.

~~~
i8x16 wasm_i8x16_neg(i8x16 a)
~~~
Changes the sign of each element of the i8x16 vector returning a i8x16.

~~~
i16x8 wasm_i16x8_neg(i16x8 a)
~~~
Changes the sign of each element of the i16x8 vector returning a i16x8.

~~~
i32x4 wasm_i32x4_neg(i32x4 a)
~~~
Changes the sign of each element of the i32x4 vector returning a i32x4.

~~~
f32x4 wasm_f32x4_neg(f32x4 a)
~~~
Changes the sign of each element of the f32x4 vector returning a f32x4.

##### **Logical Operations Definition** <a name=logical-operations-definition></a>

~~~
i8x16 wasm_i8x16_shl(i8x16 a, int32_t b)
~~~
Shifts each element of the i8x16 a vector by int32_t b bits left and returns a i8x16 vector.

~~~
i16x8 wasm_i16x8_shl(i16x8 a, int32_t b)
~~~
Shifts each element of the i16x8 a vector by int32_t b bits left and returns a i16x8 vector.

~~~
i32x4 wasm_i32x4_shl(i32x4 a, int32_t b)
~~~
Shifts each element of the i32x4 a vector by int32_t b bits left and returns a i32x4 vector.

~~~
i8x16 wasm_i8x16_shr(i8x16 a, int8_t b)
~~~
Shifts each element of the i8x16 a vector by int32_t b bits signed right for each element returning a i8x16.

~~~
u8x16 wasm_u8x16_shr(u8x16 a uint8_t b)
~~~
Shifts each element of the i8x16 a vector by uint8_t b bits unsigned right for each element returning a u8x16.

~~~
i16x8 wasm_i16x8_shr(i16x8 a, int16_t b)
~~~
Shifts each element of the i16x8 a vector by int16_t b bits signed right for each element returning a i16x8.

~~~
u16x8 wasm_i16x8_shr(u16x8 a, uint16_t b)
~~~
Shifts each element of the u16x8 a vector by uint16_t b bits unsigned right for each element returning a u16x8.

~~~
i32x4 wasm_i32x4_shr(i32x4 a, int32_t b)
~~~
Shifts each element of the i32x4 a vector by int32_t b bits signed right for each element returning a i32x4.

~~~
u32x4 wasm_u32x4_shr(u32x4 a, uint32_t b)
~~~
Shifts each element of the u32x4 a vector by uint32_t b bits unsigned right for each element returning a u32x4.

~~~
i8x16 wasm_i8x16_and(i8x16 a, i8x16 b)
~~~
Does a logical and operation on the vector i8x16 a and i8x16 b returning a i8x16 vector c.

~~~
i8x16 wasm_i8x16_or(i8x16 a, i8x16 b)
~~~
Does a logical or operation on the vector i8x16 a and i8x16 b returning a i8x16 vector c.

~~~
i8x16 wasm_i8x16_xor(i8x16 a, i8x16 b)
~~~
Does a logical xor operation on the vector i8x16 a and i8x16 b returning a i8x16 vector c.

~~~
i8x16 wasm_i8x16_not(i8x16 a)
~~~
Does a logical not operation on the vector i8x16 a and i8x16 b returning a i8x16 vector c.

~~~
i8x16 wasm_i8x16_bitselect(i8x16 a, i8x16 b, i8x16 c)
~~~
Uses the i8x16 vector c values to select which bit should be copied from i8x16 vector a (value 1) or i8x16 vector b (value 0) to the resultant vector returned.

~~~
bool wasm_i8x16_any_true(i8x16 a)
~~~
Returns a bool true if all elements are non zero.  Returns a scalar value of 0 any of the elements are 0.

~~~
bool wasm_i16x8_any_true(i16x8 a)
~~~
Returns a bool true if all elements are non zero.  Returns a scalar value of 0 any of the elements are 0.

~~~
bool wasm_i32x4_any_true(i32x4 a)
~~~
Returns a bool true if all elements are non zero.  Returns a scalar value of 0 any of the elements are 0.

~~~
i8x16 wasm_i8x16_eq(i8x16 a, i8x16 b)
~~~
Returns all 1’s in the returning element of the vector if i8x16 a vector’s element equals i8x16 b vector’s element.  Otherwise returns all 0’s in the returning element.

~~~
i16x8 wasm_i16x8_eq(i16x8 a, i16x8 b)
~~~
Returns all 1’s in the returning element of the vector if i16x8 a vector’s element equals i16x8 b vector’s element.  Otherwise returns all 0’s in the returning element.

~~~
i32x4 wasm_i32x4_eq(i32x4 a, i32x4 b)
~~~
Returns all 1’s in the returning element of the vector if i32x4 a vector’s element equals i32x4 b vector’s element.  Otherwise returns all 0’s in the returning element.

~~~
i32x4 wasm_f32x4_eq(f32x4 a f32x4 b)
~~~
Returns all 1’s in the returning element of the vector if f32x4 a vector’s element equals f32x4 b vector’s element.  Otherwise returns all 0’s in the returning element.

~~~
i8x16 wasm_i8x16_ne(i8x16 a, i8x16 b)
~~~
Returns all 1’s in the returning element of the vector if i8x16 a vector’s element is not equal i8x16 b vector’s element.  Otherwise returns all 1’s in the returning element.

~~~
i16x8 wasm_i16x8_ne(i16x8 a, i32x4 b)
~~~
Returns all 1’s in the returning element of the vector if i16x8 a vector’s element is not equal i16x8 b vector’s element.  Otherwise returns all 1’s in the returning element.

~~~
i32x4 wasm_i32x4_ne(i32x4 a, i32x4 b)
~~~
Returns all 1’s in the returning element of the vector if i32x4 a vector’s element is not equal i32x4 b vector’s element.  Otherwise returns all 1’s in the returning element.

~~~
i8x16 wasm_i8x16_lt(i8x16 a, i8x16 b)
~~~
Returns all 1’s in the corresponding element of the i8x16 vector returned if the signed element in vector a is less than the signed element in vector b.  Otherwise all 0’s is returned in the corresponding element of the returned vector.

~~~
u8x16 wasm_u8x16_lt(u8x16 a, u8x16 b)
~~~
Returns all 1’s in the corresponding element of the u8x16 vector returned if the unsigned element in vector a is less than the unsigned element in vector b.  Otherwise all 0’s is returned in the corresponding element of the returned vector.

~~~
i16x8 wasm_i16x8_lt(i16x8 a, i16x8 b)
~~~
Returns all 1’s in the corresponding element of the i16x8 vector returned if the signed element in vector a is less than the signed element in vector b.  Otherwise all 0’s is returned in the corresponding element of the returned vector.

~~~
u16x8 wasm_u16x8_lt(u16x8 a, u16x8 b)
~~~
Returns all 1’s in the corresponding element of the u16x8 vector returned if the unsigned element in vector a is less than the unsigned element in vector b.  Otherwise all 0’s is returned in the corresponding element of the returned vector.

~~~
i32x4 wasm_i32x4_lt(i32x4 a, i32x4 b)
~~~
Returns all 1’s in the corresponding element of the u32x4 vector returned if the signed element in vector a is less than the signed element in vector b.  Otherwise all 0’s is returned in the corresponding element of the returned vector.

~~~
u32x4 wasm_i32x4_lt(u32x4 a, u32x4 b)
~~~
Returns all 1’s in the corresponding element of the u32x4 vector returned if the unsigned element in vector a is less than the unsigned element in vector b.  Otherwise all 0’s is returned in the corresponding element of the returned vector.

~~~
f32x4 wasm_f32x4_lt(f32x4 a, f32x4 b)
~~~
Returns all 1’s in the corresponding element of the f32x4 vector returned if the element in vector a is less than the element in vector b.  Otherwise all 0’s is returned in the corresponding element of the returned vector.

~~~
i8x16 wasm_i8x16_le(i8x16 a, i8x16 b)
~~~
Returns all 1’s in the corresponding element of the i8x16 vector returned if the signed element in vector a is less than or equal to the signed element in vector b.  Otherwise all 0’s is returned in the corresponding element of the returned vector.

~~~
u8x16 wasm_u8x16_le(u8x16 a, u8x16 b)
~~~
Returns all 1’s in the corresponding element of the u8x16 vector returned if the unsigned element in vector a is less than or equal to the unsigned element in vector b.  Otherwise all 0’s is returned in the corresponding element of the returned vector.

~~~
i16x8 wasm_i16x8_le(i16x8 a, i16x8 b)
~~~
Returns all 1’s in the corresponding element of the i16x8 vector returned if the signed element in vector a is less than or equal to the signed element in vector b.  Otherwise all 0’s is returned in the corresponding element of the returned vector.

~~~
u16x8 wasm_u16x8_le(u16x8 a, u16x8 b)
~~~
Returns all 1’s in the corresponding element of the u16x8 vector returned if the unsigned element in vector a is less than or equal to the unsigned element in vector b.  Otherwise all 0’s is returned in the corresponding element of the returned vector.

~~~
i32x4 wasm_i32x4_le(i32x4 a, i32x4 b)
~~~
Returns all 1’s in the corresponding element of the i32x4 vector returned if the signed element in vector a is less than or equal to the signed element in vector b.  Otherwise all 0’s is returned in the corresponding element of the returned vector.

~~~
u32x4 wasm_u32x4_le(u32x4 a, u32x4 b)
~~~
Returns all 1’s in the corresponding element of the u32x4 vector returned if the unsigned element in vector a is less than or equal to the unsigned element in vector b.  Otherwise all 0’s is returned in the corresponding element of the returned vector.

~~~
f32x4 wasm_f32x4_le(f32x4 a, f32x4 b)
~~~
Returns all 1’s in the corresponding element of the f32x4 vector returned if the element in vector a is less than or equal to the element in vector b.  Otherwise all 0’s is returned in the corresponding element of the returned vector.

~~~
i8x16 wasm_i8x16_gt(i8x16 a, i8x16 b)
~~~
Returns all 1’s in the corresponding element of the i8x16 vector returned if the signed element in vector a is greater than the signed element in vector b.  Otherwise all 0’s is returned in the corresponding element of the returned vector.

~~~
u8x16 wasm_u8x16_gt(u8x16 a, u8x16 b)
~~~
Returns all 1’s in the corresponding element of the u8x16 vector returned if the unsigned element in vector a is greater than the unsigned element in vector b.  Otherwise all 0’s is returned in the corresponding element of the returned vector.

~~~
i16x8 wasm_i16x8_gt(i16x8 a, i16x8 b)
~~~
Returns all 1’s in the corresponding element of the i16x8 vector returned if the signed element in vector a is greater than the signed element in vector b.  Otherwise all 0’s is returned in the corresponding element of the returned vector.

~~~
u16x8 wasm_u16x8_gt(u16x8 a, u16x8 b)
~~~
Returns all 1’s in the corresponding element of the u16x8 vector returned if the unsigned element in vector a is greater than the unsigned element in vector b.  Otherwise all 0’s is returned in the corresponding element of the returned vector.

~~~
i32x4 wasm_i32x4_gt(i32x4 a, i32x4 b)
~~~
Returns all 1’s in the corresponding element of the i32x4 vector returned if the signed element in vector a is greater than the signed element in vector b.  Otherwise all 0’s is returned in the corresponding element of the returned vector.

~~~
u32x4 wasm_u32x4_gt(u32x4 a, u32x4 b)
~~~
Returns all 1’s in the corresponding element of the u32x4 vector returned if the unsigned element in vector a is greater than the unsigned element in vector b.  Otherwise all 0’s is returned in the corresponding element of the returned vector.

~~~
f32x4 wasm_f32x4_gt(f32x4 a, f32x4 b)
~~~
Returns all 1’s in the corresponding element of the f32x4 vector returned if the element in vector a is greater than the element in vector b.  Otherwise all 0’s is returned in the corresponding element of the returned vector.

~~~
i8x16 wasm_i8x16_ge(i8x16 a, i8x16 b)
~~~
Returns all 1’s in the corresponding element of the i8x16 vector returned if the signed element in vector a is greater than or equal to the signed element in vector b.  Otherwise all 0’s is returned in the corresponding element of the returned vector.

~~~
u8x16 wasm_u8x16_ge(u8x16 a, u8x16 b)
~~~
Returns all 1’s in the corresponding element of the u8x16 vector returned if the unsigned element in vector a is greater than or equal to the unsigned element in vector b.  Otherwise all 0’s is returned in the corresponding element of the returned vector.

~~~
i16x8 wasm_i16x8_ge(i16x8 a, i16x8 b)
~~~
Returns all 1’s in the corresponding element of the i16x8 vector returned if the signed element in vector a is greater than or equal to the signed element in vector b.  Otherwise all 0’s is returned in the corresponding element of the returned vector.

~~~
u16x8 wasm_u16x8_ge(u16x8 a, u16x8 b)
~~~
Returns all 1’s in the corresponding element of the u16x8 vector returned if the unsigned element in vector a is greater than or equal to the unsigned element in vector b.  Otherwise all 0’s is returned in the corresponding element of the returned vector.

~~~
i32x4 wasm_i32x4_ge(i32x4 a, i32x4 b)
~~~
Returns all 1’s in the corresponding element of the i32x4 vector returned if the signed element in vector a is greater than or equal to the signed element in vector b.  Otherwise all 0’s is returned in the corresponding element of the returned vector.

~~~
u32x4 wasm_u32x4_ge(u32x4 a, u32x4 b)
~~~
Returns all 1’s in the corresponding element of the u32x4 vector returned if the unsigned element in vector a is greater than or equal to the unsigned element in vector b.  Otherwise all 0’s is returned in the corresponding element of the returned vector.

~~~
f32x4 wasm_f32x4_ge(f32x4 a, f32x4 b)
~~~
Returns all 1’s in the corresponding element of the f32x4 vector returned if the element in vector a is greater than or equal to the element in vector b.  Otherwise all 0’s is returned in the corresponding element of the returned vector.

~~~
i8x16  wasm_i8x16_abs(i8x16 a)
~~~
Takes the input i8x16 vector a elements and returns the absolute values for each of the elements in the returned vector.

~~~
i16x8  wasm_i16x8_abs(i16x8 a)
~~~
Takes the input i16x8 vector a elements and returns the absolute values for each of the elements in the returned vector.

~~~
i32x4  wasm_i32x4_abs(i32x4 a)
~~~
Takes the input i32x4 vector a elements and returns the absolute values for each of the elements in the returned vector.

~~~
f32x4  wasm_f32x4_abs(f32x4 a)
~~~
Takes the input f32x4 vector a elements and returns the absolute values for each of the elements in the returned vector.

// not sure how this should work with variable input
// #define wasm_i8x16_shuffle(a, b) \
//  (__builtin_shufflevector(a, b, 0, 1, 2, 3, 4, 5, 6, 7))
// converts float and doubles to int

##### **Future Single Instruction Multiple Data Instructions**<a name=future-single-instruction-multiple-data-instructions></a>

~~~
i64x2 wasm_i64x2_splat(int64_t a)
~~~
Duplicates the value int64x4 a into the i64x2 vector

~~~
f64x2 wasm_f64x2_splat(double a)
~~~
Duplicates the value f64 a into the f64x2 vector

~~~
int64_t wasm_i64x2_extract_lane(i64x2, imm)
~~~
Extracts the int64_t element designated by the imm returning it as a int64_t

~~~
double wasm_f64x2_extract_lane(f64x2, imm)
~~~
Extracts the double element designated by the imm returning it as a double

~~~
i64x2 wasm_i64x2_replace_lane(i64x2 a, imm i, int64_t b)
~~~
Replaces the i64 element specified by the immediate i with the value of int64_t b

~~~
f64x2 wasm_f64x4_replace_lane(f64x2 a, imm i, double b)
~~~
Replaces the double element specified by the immediate i with the value of the double b

~~~
i64x2 wasm_i64x2_add(i64x2 a i64x2 b)
~~~
Adds i64x2 vector a  with i64x2 vector b returning a i64x2 vector

~~~
i64x2 wasm_i64x2_sub(i64x2 a i64x2 b)
~~~
Subtracts i64x2 vector a  with i64x2 vector b returning a i64x2 vector

~~~
i64x2 wasm_i64x2_mul(i64x2 a i64x2 b)
~~~
Multiplies the i64x2 vector a with i64x2 vector b returning a i64x2 vector.

~~~
i64x2 wasm_i64x2_neg(i64x2 a)
~~~
Changes the sign of each element of the i64x2 vector returning a i64x2.

~~~
i64x2 wasm_i64x2_shl(i64x2 a, int32_t b)
~~~
Shifts each element of the i64x2 a vector by int32_t b bits left and returns a i64x2 vector.

~~~
f64x2 wasm_f64x2_neg(f64x2 a)
~~~
Changes the sign of each element of the f64x2 vector returning a f64x2.

~~~
i64x2 wasm_i64x2_shr(i64x2 a, int64_t b)
~~~
Shifts each element of the i64x2 a vector by int32_t b bits signed right for each element returning a i64x2.

~~~
u64x2 wasm_u64x2_shr(u64x2 a, uint64_t b)
~~~
Shifts each element of the u64x2 a vector by uint64_t b bits unsigned right for each element returning a u64x2.

~~~
bool wasm_i64x2_any_true(i64x2 a)
~~~
Returns a bool true if all elements are non zero.  Returns a scalar value of 0 any of the elements are 0.

~~~
f64x2 wasm_f64x2_eq(f64x2 a, f64x2 b)
~~~
Returns all 1’s in the returning element of the vector if f64x2 a vector’s element equals f64x2 b vector’s element.  Otherwise returns all 0’s in the returning element.

~~~
f64x2 wasm_f64x2_le(f64x2 a, f64x2 b)
~~~
Returns all 1’s in the corresponding element of the f64x2 vector returned if the element in vector a is less than or equal to the element in vector b.  Otherwise all 0’s is returned in the corresponding element of the returned vector.

~~~
f64x2 wasm_f64x2_lt(f64x2 a, f64x2 b)
~~~
Returns all 1’s in the corresponding element of the f64x2 vector returned if the element in vector a is less than the element in vector b.  Otherwise all 0’s is returned in the corresponding element of the returned vector.

~~~
f64x2 wasm_f64x2_gt(f64x2 a, f64x2 b)
~~~
Returns all 1’s in the corresponding element of the f64x2 vector returned if the element in vector a is greater than the element in vector b.  Otherwise all 0’s is returned in the corresponding element of the returned vector.

~~~
f64x2 wasm_f64x2_ge(f64x2 a, f64x2 b)
~~~
Returns all 1’s in the corresponding element of the f64x2 vector returned if the element in vector a is greater than or equal to the element in vector b.  Otherwise all 0’s is returned in the corresponding element of the returned vector.

~~~
i64x2  wasm_i64x2_abs(i64x2 a)
~~~
Takes the input i64x2 vector a elements and returns the absolute values for each of the elements in the returned vector.

~~~
f64x2  wasm_i64x2_abs(f64x2 a)
~~~
Takes the input f64x2 vector a elements and returns the absolute values for each of the elements in the returned vector.
