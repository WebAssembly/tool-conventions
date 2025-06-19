;; Lime1 test.
;;
;; This tests that at least some part of every feature in the [Lime1] feature
;; is present in an engine. It is not a comprehensive conformance test.
;;
;; [Lime1]: https://github.com/WebAssembly/tool-conventions/blob/main/Lime.md#lime1

;; Import/Export of Mutable Globals (mutable-globals)
(module
  (global (export "global_i32") (mut i32) (i32.const 0))
)
(register "test")
(module
  (import "test" "global_i32" (global (mut i32)))
)

;; Non-trapping float-to-int Conversions (nontrapping-fptoint)
(module
  (func (param f32) (result i32) (i32.trunc_sat_f32_s (local.get 0)))
  (func (param f32) (result i32) (i32.trunc_sat_f32_u (local.get 0)))
  (func (param f64) (result i32) (i32.trunc_sat_f64_s (local.get 0)))
  (func (param f64) (result i32) (i32.trunc_sat_f64_u (local.get 0)))
  (func (param f32) (result i64) (i64.trunc_sat_f32_s (local.get 0)))
  (func (param f32) (result i64) (i64.trunc_sat_f32_u (local.get 0)))
  (func (param f64) (result i64) (i64.trunc_sat_f64_s (local.get 0)))
  (func (param f64) (result i64) (i64.trunc_sat_f64_u (local.get 0)))
)

;; Sign-extension Operators (sign-ext)
(module
  (func (param i32) (result i32) (i32.extend8_s (local.get 0)))
  (func (param i32) (result i32) (i32.extend16_s (local.get 0)))
  (func (param i64) (result i64) (i64.extend8_s (local.get 0)))
  (func (param i64) (result i64) (i64.extend16_s (local.get 0)))
  (func (param i64) (result i64) (i64.extend32_s (local.get 0)))
)

;; Multi-value (multi-value)
(module (func (result i32 i32)
  (block (result i32 i32)
    (i32.const 0)
    (i32.const 0)
  )
))

;; `memory.copy` and `memory.fill` from Bulk Memory Operations (bulk-memory-opt)
(module
  (memory 1)
  (func (param i32 i32 i32)
    local.get 0
    local.get 1
    local.get 2
    memory.copy
    local.get 0
    local.get 1
    local.get 2
    memory.fill
  )
)

;; Extended Constant Expressions (extended-const)
(module
  (global i32 (i32.add (i32.const 1) (i32.const 2)))
  (global i32 (i32.sub (i32.const 1) (i32.const 2)))
  (global i32 (i32.mul (i32.const 1) (i32.const 2)))
  (global i64 (i64.add (i64.const 1) (i64.const 2)))
  (global i64 (i64.sub (i64.const 1) (i64.const 2)))
  (global i64 (i64.mul (i64.const 1) (i64.const 2)))
)

;; Overlong `call_indirect` immediates from Reference Types (call-indirect-overlong)
(module binary
  "\00asm" "\01\00\00\00" ;; magic header
  "\01\04"    ;; type section, 4 bytes
  "\01"       ;; 1 type
  "\60\00\00" ;; function type, no params, no results
  "\03\02"    ;; function section, 2 bytes
  "\01"       ;; 1 function
  "\00"       ;; function0 has type 0
  "\04\04"    ;; table section, 4 bytes
  "\01"       ;; 1 table
  "\70\00\01" ;; funcref table, no flags, min 1 element
  "\0a\0c"    ;; code section, 12 bytes
  "\01"       ;; 1 function
  "\0a"       ;; function is 10 bytes
  "\00"       ;; no locals
  "\41\00"    ;; i32.const 0

  ;; call_indirect opcode + (type 0) immediate
  "\11\00"

  ;; 4-byte encoding of the immediate 0, the table index for `call_indirect`
  "\80\80\80\00"

  "\0b"       ;; end
)

;; Test that floating-point types are supported.
(module (func (param i32 i64 f32 f64)))
