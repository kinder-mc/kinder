(* This file is part of the Kind 2 model checker.

   Copyright (c) 2014 by the Board of Trustees of the University of Iowa

   Licensed under the Apache License, Version 2.0 (the "License"); you
   may not use this file except in compliance with the License.  You
   may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0 

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
   implied. See the License for the specific language governing
   permissions and limitations under the License. 

*)

open Lib

(* Abbreviations *)
module I = LustreIdent
module A = LustreAst

module SVS = StateVar.StateVarSet
module VS = Var.VarSet

(* Exceptions *)
exception Type_mismatch
exception Clock_mismatch

(* A Lustre expression is a term *)
type expr = Term.t

(* A Lustre type is a type *)
type lustre_type = Type.t

(* A Lustre clock 

   We don't do clocks, so this is just a unit value *)
type clock = unit


(* A typed and clocked Lustre expression *)
type t = { 
  
  (* Lustre expression for the initial state *)
  expr_init: expr;

  (* Lustre expression after initial state *)
  expr_step: expr;
  
  (* Clock of expression *)
  expr_clock: unit;
  
  (* Type of expression

     Keep the type here instead of reading from expr_init or
     expr_step, otherwise we need to get both types and merge *)
  expr_type: Type.t 

}


(* Total order on expressions *)
let compare
    { expr_init = init1; expr_step = step1; expr_clock = clock1 } 
    { expr_init = init2; expr_step = step2; expr_clock = clock2 } =

  (* Lexicographic comparision of initial value, step value, and clock *)
  let c_init = Term.compare init1 init2 in 
  if c_init = 0 then 
    let c_step = Term.compare step1 step2 in
    if c_step = 0 then
      Pervasives.compare clock1 clock2
    else
      c_step
  else
    c_init


(* Equality on expressions *)
let equal
    { expr_init = init1; expr_step = step1; expr_clock = clock1 } 
    { expr_init = init2; expr_step = step2; expr_clock = clock2 } = 

  Term.equal init1 init2 && Term.equal step1 step2 && clock1 = clock2


(* Hashing of expressions *)
let hash { expr_init; expr_step; expr_clock } =
  Hashtbl.hash
    (Term.hash expr_init, Term.hash expr_step (* , Term.hash expr_clock *) )


(* Return the type of the expression *)
let type_of_lustre_expr { expr_type } = expr_type


(* Hash table over Lustre expressions *)
module LustreExprHashtbl = Hashtbl.Make
    (struct
      type z = t
      type t = z (* avoid cyclic type abbreviation *)
      let equal = equal
      let hash = hash
    end)


(* These offsets are different from the offsets in the transition system,
   because here we want to know if the initial and the step
   expressions are equal without bumping offsets. *)

(* Offset of state variable at first instant *)
let pre_base_offset = Numeral.(- one)


(* Offset of state variable at first instant *)
let base_offset = Numeral.zero


(* Offset of state variable at current instant *)
let cur_offset = Numeral.zero


(* Offset of state variable at previous instant *)
let pre_offset = Numeral.(- one)




(* ********************************************************************** *)
(* Pretty-printing                                                        *)
(* ********************************************************************** *)

(* Pretty-print a type as a Lustre type *)
let rec pp_print_lustre_type safe ppf t = match Type.node_of_type t with

  | Type.Bool -> Format.pp_print_string ppf "bool"

  | Type.Int -> Format.pp_print_string ppf "int"

  | Type.IntRange (i, j) -> 

    Format.fprintf
      ppf 
      "subrange [%a, %a] of int" 
      Numeral.pp_print_numeral i 
      Numeral.pp_print_numeral j

  | Type.Real -> Format.pp_print_string ppf "real"

  | Type.Scalar (s, l) -> 

    Format.fprintf
      ppf 
      "enum { %a }" 
      (pp_print_list Format.pp_print_string " ") l
(*
  | Type.BV i -> 

    raise 
      (Invalid_argument "pp_print_lustre_type: BV is not a Lustre type")
*)
  | Type.Array (s, t) -> pp_print_lustre_type safe ppf t


(* String representation of a symbol in Lustre *)
let string_of_symbol = function
  | `TRUE -> "true"
  | `FALSE -> "false"
  | `NOT -> "not"
  | `IMPLIES -> "=>"
  | `AND -> "and"
  | `OR -> "or"
  | `XOR -> "xor"
  | `EQ -> "="
  | `NUMERAL n -> Numeral.string_of_numeral n
  | `DECIMAL d -> Decimal.string_of_decimal d
  | `MINUS -> "-"
  | `PLUS -> "+"
  | `TIMES -> "*"
  | `DIV -> "/"
  | `INTDIV ->"div"
  | `MOD -> "mod"
  | `ABS -> "abs"
  | `LEQ -> "<="
  | `LT -> "<"
  | `GEQ -> ">="
  | `GT -> ">"
  | `TO_REAL -> "real"
  | `TO_INT -> "int"
  | _ -> failwith "string_of_symbol"


(* Pretty-print a symbol *)
let pp_print_symbol ppf s = Format.fprintf ppf "%s" (string_of_symbol s) 


(* Pretty-print a variable *)
let pp_print_lustre_var _ ppf state_var = 
  Format.fprintf ppf "%a" StateVar.pp_print_state_var state_var


(* Pretty-printa variable with its type *)
let pp_print_lustre_var_typed safe ppf state_var = 

  Format.fprintf ppf
    "%t%a: %a"
    (function ppf -> 
      if StateVar.is_const state_var then Format.fprintf ppf "const ")
    (pp_print_lustre_var safe) state_var
    (pp_print_lustre_type safe) (StateVar.type_of_state_var state_var)
  


(* Pretty-print a variable under [depth] pre operators *)
let rec pp_print_var safe ppf var =

  (* Variable is at an instant *)
  if Var.is_state_var_instance var then 

    (* Get state variable of variable *)
    let state_var = Var.state_var_of_state_var_instance var in
    
    (* Function to pretty-print a variable with or without pre *)
    let pp = 
      
      (* Variable at current offset *)
      if Numeral.equal (Var.offset_of_state_var_instance var) cur_offset then 
        
        Format.fprintf ppf
          "@[<hv 2>%a@]"
          (pp_print_lustre_var safe) 
          
      (* Variable at previous offset *)
      else if Numeral.equal (Var.offset_of_state_var_instance var) pre_offset then 

      Format.fprintf ppf
        "@[<hv 2>(pre %a)@]"
        (pp_print_lustre_var safe) 

      (* Fail on other offsets *)
      else

        function _ -> raise  (Invalid_argument "pp_print_var")

    in

    (* Pretty-print state variable with or without pre *)
    pp state_var
    
  (* Variable is constant *)
  else if Var.is_const_state_var var then

    (* Get state variable of variable *)
    let state_var = Var.state_var_of_state_var_instance var in
    
    Format.fprintf ppf
      "@[<hv 2>%a@]"
      (pp_print_lustre_var safe) 
      state_var    
    
  (* Fail on other types of variables *)
  else

    raise (Invalid_argument "pp_print_var")



(* Pretty-print a term *)
and pp_print_term_node safe ppf t = match Term.T.destruct t with
    
  | Term.T.Var var -> pp_print_var safe ppf var
      
  | Term.T.Const s -> 
    
    pp_print_symbol ppf (Symbol.node_of_symbol s)
      
  | Term.T.App (s, l) -> 
    
    pp_print_app safe ppf (Symbol.node_of_symbol s) l

  | Term.T.Attr (t, _) -> 
    
    pp_print_term_node safe ppf t
      

(* Pretty-print the second and following arguments of a
   left-associative function application *)
and pp_print_app_left' safe s ppf = function 

  | h :: tl -> 

    Format.fprintf ppf 
      " %a@ %a%t" 
      pp_print_symbol s 
      (pp_print_term_node safe) h 
      (function ppf -> pp_print_app_left' safe s ppf tl)

  | [] -> ()


(* Pretty-print a left-associative function application

   Print (+ a b c) as (a + b + c) *)
and pp_print_app_left safe s ppf = function 

  (* Function application must have arguments, is a constant
     otherwise *)
  | [] -> assert false

  (* Print first argument *)
  | h :: tl -> 

    Format.fprintf ppf
      "@[<hv 2>(%a%t)@]" 
      (pp_print_term_node safe) h 
      (function ppf -> pp_print_app_left' safe s ppf tl)


(* Pretty-print arguments of a right-associative function application *)
and pp_print_app_right' safe s arity ppf = function 

  (* Function application must have arguments, is a constant
     otherwise *)
  | [] -> assert false 

  (* Last or only argument *)
  | [h] -> 

    (* Print closing parentheses for all arguments *)
    let rec aux ppf = function 
      | 0 -> ()
      | i -> 
        Format.fprintf ppf
          "%t)@]"
          (function ppf -> aux ppf (pred i))
    in

    (* Print last argument and close all parentheses *)
    Format.fprintf ppf
      "%a%t" 
      (pp_print_term_node safe) h 
      (function ppf -> aux ppf arity)

  (* Second last or earlier argument *)
  | h :: tl -> 

    (* Open parenthesis and print argument *)
    Format.fprintf ppf 
      "@[<hv 2>(%a %a@ %t" 
      (pp_print_term_node safe) h 
      pp_print_symbol s 
      (function ppf -> pp_print_app_right' safe s arity ppf tl)


(* Pretty-print a right-associative function application 

   Print (=> a b c) as (a => (b => c)) *)
and pp_print_app_right safe s ppf l =
  pp_print_app_right' safe s (List.length l - 1) ppf l


(* Pretty-print a chaining function application 

   Print (= a b c) as (a = b) and (b = c) *)
and pp_print_app_chain safe s ppf = function 

  (* Chaining function application must have more than one argument *)
  | []
  | [_] -> assert false 

  (* Last or only pair of arguments *)
  | [l; r] -> 

    Format.fprintf ppf 
      "@[<hv 2>(%a %a@ %a)@]" 
      (pp_print_term_node safe) l 
      pp_print_symbol s
      (pp_print_term_node safe) r

  (* Print function application of first pair, conjunction and continue *)
  | l :: r :: tl -> 

    Format.fprintf ppf 
      "@[<hv 2>(%a %a@ %a) and %a@]" 
      (pp_print_term_node safe) l
      pp_print_symbol s
      (pp_print_term_node safe) r
      (pp_print_app_chain safe s) (r :: tl)


(* Pretty-print a function application *)
and pp_print_app safe ppf = function 

  (* Function application must have arguments, cannot have nullary
     symbols here *)
  | `TRUE
  | `FALSE
  | `NUMERAL _
  | `DECIMAL _
  (* | `BV _ *) -> (function _ -> assert false)

  (* Unary symbols *) 
  | `NOT
  | `TO_REAL
  | `TO_INT
  | `ABS as s -> 

    (function [a] -> 
      Format.fprintf ppf
        "@[<hv 2>(%a@ %a)@]" 
        pp_print_symbol s 
        (pp_print_term_node safe) a

      | _ -> assert false)
  
  (* Unary and left-associative binary symbols *)
  | `MINUS as s ->
      
      (function 
        | [] -> assert false 
        | [a] ->

          Format.fprintf ppf
            "%a%a" 
            pp_print_symbol s 
            (pp_print_term_node safe) a

        | _ as l -> pp_print_app_left safe s ppf l)
        
    (* Binary left-associative symbols with two or more arguments *)
    | `AND
    | `OR
    | `XOR
    | `PLUS
    | `TIMES
    | `DIV
    | `INTDIV as s ->
      
      (function 
        | [] 
        | [_] -> assert false
        | _ as l -> pp_print_app_left safe s ppf l)
            
    (* Binary right-associative symbols *)
    | `IMPLIES as s -> pp_print_app_right safe s ppf
        
    (* Chainable binary symbols *)
    | `EQ
    | `LEQ
    | `LT
    | `GEQ
    | `GT as s -> pp_print_app_chain safe s ppf
              
    (* if-then-else *)
    | `ITE ->
      
      (function [p; l; r] ->

        Format.fprintf ppf
          "if %a then %a else %a" 
          (pp_print_term_node safe) p
          (pp_print_term_node safe) l
          (pp_print_term_node safe) r
          
        | _ -> assert false)
        
    (* Binary symbols *)
    | `MOD as s ->
      
      (function [l; r] ->

        Format.fprintf ppf 
          "@[<hv 2>(%a %a@ %a)@]" 
          (pp_print_term_node safe) l 
          pp_print_symbol s
          (pp_print_term_node safe) r
        
        | _ -> assert false)
        
    (* Divisibility *) 
    | `DIVISIBLE n -> 
      
      (function [a] -> 
        
        (* a divisble n becomes a mod n = 0 *)
        pp_print_app 
          safe 
          ppf
          `EQ
          [Term.T.mk_app 
             (Symbol.mk_symbol `MOD) 
             [a; Term.T.mk_const (Symbol.mk_symbol (`NUMERAL n))];
           Term.T.mk_const (Symbol.mk_symbol (`NUMERAL Numeral.zero))]
          
        | _ -> assert false)

    | `SELECT -> 

      (function 
        | [a; i] ->
        
          Format.fprintf ppf 
            "@[<hv 2>%a[%a]@]" 
            (pp_print_term_node safe) a 
            (pp_print_term_node safe) i
            
        | _ -> assert false)
        
        
    (* Unsupported functions symbols *)
    | `DISTINCT
(*
    | `CONCAT
    | `EXTRACT _
    | `BVNOT
    | `BVNEG
    | `BVAND
    | `BVOR
    | `BVADD
    | `BVMUL
    | `BVDIV
    | `BVUREM
    | `BVSHL
    | `BVLSHR
    | `BVULT
    | `STORE
*)
    | `IS_INT
    | `UF _ -> (function _ -> assert false)
      

(* Pretty-print a hashconsed term *)
let pp_print_expr safe ppf expr =
  pp_print_term_node safe ppf expr


(* Pretty-print a hashconsed term to the standard formatter *)
let print_expr safe = pp_print_expr safe Format.std_formatter 


(* Pretty-print a clocked and typed Lustre expression *)
let pp_print_lustre_expr safe ppf = function

  (* Same expression for initial state and following states *)
  | { expr_init; expr_step } when Term.equal expr_init expr_step -> 

    pp_print_expr safe ppf expr_step

  (* Print expression of initial state followed by expression for
     following states *)
  | { expr_init; expr_step } -> 

    Format.fprintf ppf 
      "@[<hv 1>(%a@ ->@ %a)@]" 
      (pp_print_expr safe) expr_init
      (pp_print_expr safe) expr_step


(* ********************************************************************** *)
(* Clocks                                                                 *)
(* ********************************************************************** *)


(* The base clock *)
let base_clock = ()


(* TODO: clock checking *)
let clock_check _ _ = true


(* ********************************************************************** *)
(* Predicates                                                             *)
(* ********************************************************************** *)


(* Return true if expression is a previous state variable *)
let has_pre_var zero_offset { expr_step } = 

  (* Previous state variables have negative offset *)
  match Term.var_offsets_of_term expr_step with 
    | Some n, _ when Numeral.(n <= zero_offset + pre_offset) -> true
    | _ -> false


(* Return true if there is an unguarded pre operator in the expression *)
let pre_is_unguarded { expr_init } = 

  (* Check if there is a pre operator in the init expression *)
  match Term.var_offsets_of_term expr_init with 
    | None, _ -> false
    | Some c, _ -> Numeral.(c < base_offset)


(* Return true if expression is a current state variable *)
let is_var_at_offset { expr_init; expr_step } (init_offset, step_offset) = 

  (* Term must be a free variable *)
  (Term.is_free_var expr_init) && 

  (* Get free variable of term *)
  (let var_init = Term.free_var_of_term expr_init in 

   (* Variable must be an instance of a state variable *)
   Var.is_state_var_instance var_init && 

   (* Variable must be at instant zero *)
   Numeral.(Var.offset_of_state_var_instance var_init = init_offset)) &&

  (* Term must be a free variable *)
  (Term.is_free_var expr_step) && 

  (* Get free variable of term *)
  (let var_step = Term.free_var_of_term expr_step in 

   (* Variable must be an instance of a state variable *)
   Var.is_state_var_instance var_step && 

   (* Variable must be at instant zero *)
   Numeral.(Var.offset_of_state_var_instance var_step = step_offset))



(* Return true if expression is a previous state variable *)
let is_var expr = is_var_at_offset expr (base_offset, cur_offset)


(* Return true if expression is a previous state variable *)
let is_pre_var expr = is_var_at_offset expr (pre_base_offset, pre_offset)


(* ********************************************************************** *)
(* Conversion to terms                                                    *)
(* ********************************************************************** *)

(* Instance of state variable at instant zero *)
let pre_base_var_of_state_var zero_offset state_var = 
  Var.mk_state_var_instance 
    state_var
    Numeral.(zero_offset + pre_base_offset)


(* Instance of state variable at instant zero *)
let base_var_of_state_var zero_offset state_var = 
  Var.mk_state_var_instance
    state_var
    Numeral.(zero_offset + base_offset)


(* Instance of state variable at current instant *)
let cur_var_of_state_var zero_offset state_var = 
  Var.mk_state_var_instance
    state_var
    Numeral.(zero_offset + cur_offset)


(* Instance of state variable at previous instant *)
let pre_var_of_state_var zero_offset state_var = 
  Var.mk_state_var_instance 
    state_var
    Numeral.(zero_offset + pre_offset)

    
(* Term of instance of state variable at previous instant *)
let pre_base_term_of_state_var zero_offset state_var = 
  Term.mk_var (pre_base_var_of_state_var zero_offset state_var)


(* Term of instance of state variable at previous instant *)
let base_term_of_state_var zero_offset state_var = 
  Term.mk_var (base_var_of_state_var zero_offset state_var)


(* Term of instance of state variable at current instant *)
let cur_term_of_state_var zero_offset state_var = 
  Term.mk_var (cur_var_of_state_var zero_offset state_var)


(* Term of instance of state variable at previous instant *)
let pre_term_of_state_var zero_offset state_var = 
  Term.mk_var (pre_var_of_state_var zero_offset state_var)


(* Term at instant zero *)
let base_term_of_expr zero_offset expr = 
  Term.bump_state Numeral.(zero_offset + base_offset) expr


(* Term at current instant *)
let cur_term_of_expr zero_offset expr =
  Term.bump_state Numeral.(zero_offset + cur_offset) expr


(* Term at previous instant *)
let pre_term_of_expr zero_offset expr = 
  Term.bump_state Numeral.(zero_offset + pre_offset) expr

(* Return the state variable of a variable *)
let state_var_of_expr ({ expr_init; expr_step } as expr) = 

  (* Initial value and step value must be identical *)
  if is_var expr || is_pre_var expr then

    try 
      
      (* Get free variable of term *)
      let var = Term.free_var_of_term expr_init in 
      
      (* Get instance of state variable *)
      Var.state_var_of_state_var_instance var
        
    (* Fail if any of the above fails *)
    with Invalid_argument _ -> raise (Invalid_argument "state_var_of_expr")

  else

    (* Fail if initial value is different from step value *)
    raise (Invalid_argument "state_var_of_expr")


(* Return all state variables *)
let state_vars_of_expr { expr_init; expr_step } = 

  (* State variables in initial state expression *)
  let state_vars_init = Term.state_vars_of_term expr_init in

  (* State variables in step state expression *)
  let state_vars_step = Term.state_vars_of_term expr_step in

  (* Join sets of state variables *)
  SVS.union state_vars_init state_vars_step


(* Return all state variables at the current instant *)
let cur_state_vars_of_expr { expr_init; expr_step } = 

  (* State variables in initial state expression *)
  let state_vars_init =
    Term.state_vars_at_offset_of_term
      base_offset
      (base_term_of_expr base_offset expr_init)
  in

  (* State variables in step state expression *)
  let state_vars_step = 
    Term.state_vars_at_offset_of_term
      cur_offset
      (cur_term_of_expr cur_offset expr_step)
  in

  (* Join sets of state variables *)
  SVS.union state_vars_init state_vars_step


(* Split a list of Lustre expressions into a list of pairs of
   expressions for the initial step and the transition steps,
   respectively *)
let split_expr_list list = 

  List.fold_left
    (fun (accum_init, accum_step) { expr_init; expr_step } -> 
       ((if expr_init == Term.t_true then 
           accum_init 
         else
           expr_init :: accum_init), 
        (if expr_step == Term.t_true then 
           accum_step
         else
           expr_step :: accum_step)))
    ([], [])
    list      



(* ********************************************************************** *)
(* Generic constructors                                                   *)
(* ********************************************************************** *)

(* These constructors take as arguments functions [eval] and [type_of]
   whose arity matches the arity of the constructors, where [eval]
   applies the operator and simplifies the expression, and [type_of]
   returns the type of the resulting expression or fails with
   {!Type_mismatch}. *)

(* Construct a unary expression *)
let mk_unary eval type_of expr = 

  let res_type = type_of expr.expr_type in

  { expr_init = eval expr.expr_init;
    expr_step = eval expr.expr_step;
    expr_type = res_type;
    expr_clock = expr.expr_clock } 


(* Construct a binary expression *)
let mk_binary eval type_of expr1 expr2 = 

  let res_clock = 
    if clock_check expr1.expr_clock expr2.expr_clock then 
      expr1.expr_clock
    else
      raise Clock_mismatch
  in  

  let res_type = 
    type_of expr1.expr_type expr2.expr_type 
  in

  { expr_init = eval expr1.expr_init expr2.expr_init;
    expr_step = eval expr1.expr_step expr2.expr_step;
    expr_type = res_type;
    expr_clock = res_clock } 


(* Construct a binary expression *)
let mk_ternary eval type_of expr1 expr2 expr3 = 

  let res_clock = 
    if 
      clock_check expr1.expr_clock expr2.expr_clock && 
      clock_check expr2.expr_clock expr3.expr_clock 
    then 
      expr1.expr_clock
    else
      raise Clock_mismatch
  in  

  let res_type = 
    type_of expr1.expr_type expr2.expr_type expr3.expr_type 
  in

  { expr_init = eval expr1.expr_init expr2.expr_init expr3.expr_init;
    expr_step = eval expr1.expr_step expr2.expr_step expr3.expr_step;
    expr_type = res_type;
    expr_clock = res_clock } 


(* ********************************************************************** *)
(* Constant constructors                                                  *)
(* ********************************************************************** *)
  

(* Boolean constant true on base clock *)
let t_true = 

  let expr = Term.t_true in

  { expr_init = expr; 
    expr_step = expr; 
    expr_type = Type.t_bool; 
    expr_clock = base_clock } 


(* Boolean constant false on base clock *)
let t_false =  

  let expr = Term.t_false in

  { expr_init = expr; 
    expr_step = expr; 
    expr_type = Type.t_bool; 
    expr_clock = base_clock } 


(* Integer constant on base clock *)
let mk_int d =  

  let expr = Term.mk_num d in

  { expr_init = expr; 
    expr_step = expr; 
    expr_type = Type.mk_int_range d d; 
    expr_clock = base_clock } 


(* Real constant on base clock *)
let mk_real f =  

  let expr = Term.mk_dec f in

  { expr_init = expr; 
    expr_step = expr; 
    expr_type = Type.t_real; 
    expr_clock = base_clock } 


(* Current state variable of state variable *)
let mk_var state_var expr_clock = 

  { expr_init = base_term_of_state_var base_offset state_var;
    expr_step = cur_term_of_state_var cur_offset state_var;
    expr_type = StateVar.type_of_state_var state_var;
    expr_clock = expr_clock } 


(* i-th index variable *)
let mk_index_var i = 

  (* Create state variable *)
  let state_var = 
    StateVar.mk_state_var
      ((I.push_index I.index_ident i) 
       |> I.string_of_ident false)
      []
      Type.t_int
  in

  (* Create expression of state variable *)
  mk_var state_var base_clock


(* ********************************************************************** *)
(* Type checking constructors                                             *)
(* ********************************************************************** *)

(* Generic type checking functions that fail with [Type_mismatch] or
   return a resulting type if the expressions match the required types. *)

(* Type check for bool -> bool *)
let type_of_bool_bool = function 
  | t when Type.is_bool t -> Type.t_bool
  | _ -> raise Type_mismatch


(* Type check for bool -> bool -> bool *)
let type_of_bool_bool_bool = function 
  | t when Type.is_bool t -> 
    (function 
      | t when Type.is_bool t -> Type.t_bool 
      | _ -> raise Type_mismatch)
  | _ -> raise Type_mismatch


(* Type check for int -> int -> int *)
let type_of_int_int_int = function 

  | t when Type.is_int t || Type.is_int_range t -> 
    (function 
      | t when Type.is_int t || Type.is_int_range t -> Type.t_int 
      | _ -> raise Type_mismatch)
  | _ -> raise Type_mismatch


(* Type check for real -> real -> real *)
let type_of_real_real_real = function 

  | t when Type.is_real t -> 
    (function 
      | t when Type.is_real t -> Type.t_real
      | _ -> raise Type_mismatch)
    
  | _ -> raise Type_mismatch


(* Type check for int -> int -> int, real -> real -> real *)
let type_of_num_num_num = function 

  | t when Type.is_int t || Type.is_int_range t -> 
    (function 
      | t when Type.is_int t || Type.is_int_range t -> Type.t_int 
      | _ -> raise Type_mismatch)

  | t when Type.is_real t -> 
    (function 
      | t when Type.is_real t -> Type.t_real
      | _ -> raise Type_mismatch)
    
  | _ -> raise Type_mismatch


(* Type check for 'a -> 'a -> 'a *)
let type_of_a_a_a type1 type2 = 

  (* If first type is subtype of second, choose second type *)
  if Type.check_type type1 type2 then type2 

  (* If second type is subtype of first, choose first type *)
  else if Type.check_type type2 type1 then type1 

  (* Extend integer ranges if one is not a subtype of the other *)
  else if Type.is_int_range type1 && Type.is_int_range type2 then Type.t_int 

  (* Fail if types are incompatible *)
  else raise Type_mismatch


(* Type check for 'a -> 'a -> bool *)
let type_of_a_a_bool type1 type2 = 

  if 

    (* One type must be subtype of the other *)
    Type.check_type type1 type2
    || Type.check_type type2 type1

    (* Extend integer ranges if one is not a subtype of the other *)
    || (Type.is_int_range type1 && Type.is_int_range type2) 

  then 

    (* Resulting type is Boolean *)
    Type.t_bool 

  (* Fail if types are incompatible *)
  else 

    raise Type_mismatch


(* Type check for int -> int -> bool, real -> real -> bool *)
let type_of_num_num_bool = function

  | t when Type.is_int t || Type.is_int_range t -> 
    (function 
      | t when Type.is_int t || Type.is_int_range t -> Type.t_bool 
      | _ -> raise Type_mismatch)

  | t when Type.is_real t -> 
    (function 
      | t when Type.is_real t -> Type.t_bool
      | _ -> raise Type_mismatch)
    
  | _ -> raise Type_mismatch


(* ********************************************************************** *)


(* Evaluate unary negation

   not true -> false
   not false -> true
*)
let eval_not = function 
  | t when t == Term.t_true -> Term.t_false
  | t when t == Term.t_false -> Term.t_true
  | expr -> Term.mk_not expr


(* Type of unary negation 

   not: bool -> bool 
*)
let type_of_not = type_of_bool_bool


(* Unary negation of expression *)
let mk_not expr = mk_unary eval_not type_of_not expr


(* ********************************************************************** *)


(* Evaluate unary minus

   -(c) -> (-c)
   -(-x) -> x
*)
let eval_uminus expr = match Term.destruct expr with 

  | Term.T.Const s when Symbol.is_numeral s -> 
    Term.mk_num Numeral.(- Symbol.numeral_of_symbol s)

  | Term.T.Const s when Symbol.is_decimal s -> 
    Term.mk_dec Decimal.(- Symbol.decimal_of_symbol s)

  | Term.T.App (s, [e]) when s == Symbol.s_minus -> e

  | _ -> Term.mk_minus [expr]


(* Type of unary minus 

   -: int -> int 
   -: int_range(l, u) -> int_range(-u, -l)
   -: real -> real 
*)
let type_of_uminus = function
  | t when Type.is_int t -> Type.t_int
  | t when Type.is_real t -> Type.t_real
  | t when Type.is_int_range t -> 
    let (ubound, lbound) = Type.bounds_of_int_range t in
    Type.mk_int_range Numeral.(- ubound) Numeral.(- lbound)
  | _ -> raise Type_mismatch


(* Unary negation of expression *)
let mk_uminus expr = mk_unary eval_uminus type_of_uminus expr


(* ********************************************************************** *)


(* Evaluate conversion to integer *)
let eval_to_int expr = match Term.destruct expr with 
  | Term.T.Const s when Symbol.is_decimal s -> 
    Term.mk_num
      (Numeral.of_big_int
         (Decimal.to_big_int
            (Symbol.decimal_of_symbol s)))

  | _ -> Term.mk_to_int expr


(* Type of conversion to integer  

   int: real -> int 
*)
let type_of_to_int = function
  | t when Type.is_real t -> Type.t_int
  | _ -> raise Type_mismatch


(* Conversion to integer *)
let mk_to_int expr = mk_unary eval_to_int type_of_to_int expr 


(* ********************************************************************** *)


(* Evaluate conversion to real *)
let eval_to_real expr = match Term.destruct expr with 
  | Term.T.Const s when Symbol.is_numeral s -> 
    Term.mk_dec
      (Decimal.of_big_int
         (Numeral.to_big_int
            (Symbol.numeral_of_symbol s)))

  | _ -> Term.mk_to_real expr

(* Type of conversion to real  

   real: int -> real 
*)
let type_of_to_real = function
  | t when Type.is_int t || Type.is_int_range t -> Type.t_real
  | _ -> raise Type_mismatch


(* Conversion to integer *)
let mk_to_real expr = mk_unary eval_to_real type_of_to_real expr 


(* ********************************************************************** *)


(* Evaluate Boolean conjunction

   true and e2 -> e2 
   false and e2 -> false
   e1 and true -> e1
   e1 and false -> false *)
let eval_and = function 
  | t when t == Term.t_true -> (function expr2 -> expr2)
  | t when t == Term.t_false -> (function expr2 -> Term.t_false)
  | expr1 -> 
    (function 
      | t when t == Term.t_true -> expr1
      | t when t == Term.t_false -> Term.t_false
      | expr2 -> Term.mk_and [expr1; expr2])


(* Type of Boolean conjunction 

   and: bool -> bool -> bool *)
let type_of_and = type_of_bool_bool_bool


(* Boolean conjunction *)
let mk_and expr1 expr2 = mk_binary eval_and type_of_and expr1 expr2 


(* ********************************************************************** *)


(* Evaluate Boolean disjunction

   true or e2 -> true
   false or e2 -> e2
   e1 or true -> true
   e1 or false -> e1 *)
let eval_or = function 
  | t when t == Term.t_true -> (function expr2 -> Term.t_true)
  | t when t == Term.t_false -> (function expr2 -> expr2)
  | expr1 -> 
    (function 
      | t when t == Term.t_true -> Term.t_true
      | t when t == Term.t_false -> expr1
      | expr2 -> Term.mk_or [expr1; expr2])


(* Type of Boolean disjunction 

   or: bool -> bool -> bool *)
let type_of_or = type_of_bool_bool_bool


(* Boolean disjunction *)
let mk_or expr1 expr2 = mk_binary eval_or type_of_or expr1 expr2 


(* ********************************************************************** *)


(* Evaluate Boolean exclusive disjunction

   true xor e2 -> not e2
   false xor e2 -> e2
   e1 xor true -> not e1
   e1 xor false -> e1 *)
let eval_xor = function 
  | t when t == Term.t_true -> (function expr2 -> eval_not expr2)
  | t when t == Term.t_false -> (function expr2 -> expr2)
  | expr1 -> 
    (function 
      | t when t == Term.t_true -> eval_not expr1
      | t when t == Term.t_false -> expr1
      | expr2 -> Term.mk_xor [expr1; expr2])


(* Type of Boolean exclusive disjunction 

   xor: bool -> bool -> bool *)
let type_of_xor = type_of_bool_bool_bool


(* Boolean exclusive disjunction *)
let mk_xor expr1 expr2 = mk_binary eval_xor type_of_xor expr1 expr2 


(* ********************************************************************** *)


(* Evaluate Boolean implication

   true => e2 -> e2
   false => e2 -> true
   e1 => true -> true
   e1 => false -> not e1 *)
let eval_impl = function 
  | t when t == Term.t_true -> (function expr2 -> expr2)
  | t when t == Term.t_false -> (function expr2 -> Term.t_true)
  | expr1 -> 
    (function 
      | t when t == Term.t_true -> Term.t_true
      | t when t == Term.t_false -> eval_not expr1
      | expr2 -> Term.mk_implies [expr1; expr2])


(* Type of Boolean implication 

   =>: bool -> bool -> bool *)
let type_of_impl = type_of_bool_bool_bool


(* Boolean implication *)
let mk_impl expr1 expr2 = mk_binary eval_impl type_of_impl expr1 expr2 


(* ********************************************************************** *)


(* Evaluate integer modulus *)
let eval_mod expr1 expr2 = 

  match Term.destruct expr1, Term.destruct expr2 with

    | Term.T.Const c1, Term.T.Const c2 when
        Symbol.is_numeral c1 && Symbol.is_numeral c2 -> 

      Term.mk_num 
        Numeral.(Symbol.numeral_of_symbol c1 mod 
                 Symbol.numeral_of_symbol c2) 

    | _ -> Term.mk_mod expr1 expr2


(* Type of integer modulus 

   If j is bounded by [l, u], then the result of i mod j is bounded by
   [0, (max(|l|, |u|) - 1)].

   mod: int -> int -> int *)
let type_of_mod = function 

  | t when Type.is_int t || Type.is_int_range t -> 
    (function 
      | t when Type.is_int t -> Type.t_int 
      | t when Type.is_int_range t -> 
        let l, u = Type.bounds_of_int_range t in 
        Type.mk_int_range Numeral.zero Numeral.(pred (max (abs l) (abs u)))
      | _ -> raise Type_mismatch)
  | _ -> raise Type_mismatch

(* Integer modulus *)
let mk_mod expr1 expr2 = mk_binary eval_mod type_of_mod expr1 expr2 


(* ********************************************************************** *)


(* Evaluate subtraction *)
let eval_minus expr1 expr2 = 
  
  match Term.destruct expr1, Term.destruct expr2 with
    
    | Term.T.Const c1, Term.T.Const c2 when
        Symbol.is_numeral c1 && Symbol.is_numeral c2 -> 
      
      Term.mk_num 
        Numeral.(Symbol.numeral_of_symbol c1 -
                 Symbol.numeral_of_symbol c2) 
        
    | Term.T.Const c1, Term.T.Const c2 when
        Symbol.is_decimal c1 && Symbol.is_decimal c2 -> 
      
      Term.mk_dec
        Decimal.(Symbol.decimal_of_symbol c1 -
                 Symbol.decimal_of_symbol c2) 
        
    | _ -> Term.mk_minus [expr1; expr2]
             

(* Type of subtraction 

   If both arguments are bounded, the difference is bounded by the
   difference of the lower bound of the first argument and the upper
   bound of the second argument and the difference of the upper bound
   of the first argument and the lower bound of the second argument.

   -: int -> int -> int
      real -> real -> real *)
let type_of_minus = function 
  | t when Type.is_int_range t -> 
    (function 
      | s when Type.is_int_range s -> 
        let l1, u1 = Type.bounds_of_int_range t in
        let l2, u2 = Type.bounds_of_int_range s in
        Type.mk_int_range Numeral.(l1 - u2) Numeral.(u1 - l2)
      | s -> type_of_num_num_num t s)
  | t -> type_of_num_num_num t



(* Subtraction *)
let mk_minus expr1 expr2 = mk_binary eval_minus type_of_minus expr1 expr2 


(* ********************************************************************** *)


(* Evaluate addition *)
let eval_plus expr1 expr2 = 

  match Term.destruct expr1, Term.destruct expr2 with

    | Term.T.Const c1, Term.T.Const c2 when
        Symbol.is_numeral c1 && Symbol.is_numeral c2 -> 

      Term.mk_num 
        Numeral.(Symbol.numeral_of_symbol c1 +
                 Symbol.numeral_of_symbol c2) 

    | Term.T.Const c1, Term.T.Const c2 when
        Symbol.is_decimal c1 && Symbol.is_decimal c2 -> 

      Term.mk_dec
        Decimal.(Symbol.decimal_of_symbol c1 +
                 Symbol.decimal_of_symbol c2) 

  | _ -> Term.mk_plus [expr1; expr2]


(* Type of addition 
   
   If both summands are bounded, the sum is bounded by the sum of the
   lower bound and the sum of the upper bounds.

   +: int -> int -> int
      real -> real -> real *)
let type_of_plus = function 
  | t when Type.is_int_range t -> 
    (function 
      | s when Type.is_int_range s -> 
        let l1, u1 = Type.bounds_of_int_range t in
        let l2, u2 = Type.bounds_of_int_range s in
        Type.mk_int_range Numeral.(l1 + l2) Numeral.(u1 + u2)
      | s -> type_of_num_num_num t s)
  | t -> type_of_num_num_num t


(* Addition *)
let mk_plus expr1 expr2 = mk_binary eval_plus type_of_plus expr1 expr2 


(* ********************************************************************** *)


(* Evaluate real division *)
let eval_div expr1 expr2 = 

  match Term.destruct expr1, Term.destruct expr2 with

    | Term.T.Const c1, Term.T.Const c2 when
        Symbol.is_decimal c1 && Symbol.is_decimal c2 -> 

      Term.mk_dec
        Decimal.(Symbol.decimal_of_symbol c1 /
                 Symbol.decimal_of_symbol c2) 

  | _ -> Term.mk_div [expr1; expr2]


(* Type of real division

   /: real -> real -> real *)
let type_of_div = type_of_real_real_real


(* Real division *)
let mk_div expr1 expr2 = mk_binary eval_div type_of_div expr1 expr2 


(* ********************************************************************** *)


(* Evaluate multiplication *)
let eval_times expr1 expr2 = 

  match Term.destruct expr1, Term.destruct expr2 with

    | Term.T.Const c1, Term.T.Const c2 when
        Symbol.is_numeral c1 && Symbol.is_numeral c2 -> 

      Term.mk_num 
        Numeral.(Symbol.numeral_of_symbol c1 *
                 Symbol.numeral_of_symbol c2) 

    | Term.T.Const c1, Term.T.Const c2 when
        Symbol.is_decimal c1 && Symbol.is_decimal c2 -> 

      Term.mk_dec
        Decimal.(Symbol.decimal_of_symbol c1 *
                 Symbol.decimal_of_symbol c2) 

  | _ -> Term.mk_times [expr1; expr2]


(* Type of multiplication

   *: int -> int -> int
      real -> real -> real *)
let type_of_times = type_of_num_num_num


(* Multiplication *)
let mk_times expr1 expr2 = mk_binary eval_times type_of_times expr1 expr2 


(* ********************************************************************** *)


(* Evaluate integer division *)
let eval_intdiv expr1 expr2 = 

  match Term.destruct expr1, Term.destruct expr2 with

    | Term.T.Const c1, Term.T.Const c2 when
        Symbol.is_numeral c1 && Symbol.is_numeral c2 -> 

      Term.mk_num
        Numeral.(Symbol.numeral_of_symbol c1 /
                 Symbol.numeral_of_symbol c2) 

  | _ -> Term.mk_intdiv [expr1; expr2]


(* Type of integer division

   div: int -> int -> int *)
let type_of_intdiv = type_of_int_int_int


(* Integer division *)
let mk_intdiv expr1 expr2 = mk_binary eval_intdiv type_of_intdiv expr1 expr2 


(* ********************************************************************** *)


(* Evaluate equality *)
let eval_eq expr1 expr2 = match expr1, expr2 with

  (* true = e2 -> e2 *)
  | t, _ when t == Term.t_true -> expr2

  (* false = e2 -> not e2 *)
  | t, _ when t == Term.t_false -> eval_not expr2

  (* e1 = true -> e1 *)
  | _, t when t == Term.t_true -> expr1

  (* e1 = false -> not e1 *)
  | _, t when t == Term.t_false -> eval_not expr1

  (* e = e -> true *)
  | _ when Term.equal expr1 expr2 -> Term.t_true

  | _ -> 

    match Term.destruct expr1, Term.destruct expr2 with
      
      | Term.T.Const c1, Term.T.Const c2 when
          Symbol.is_numeral c1 && 
          Symbol.is_numeral c2 -> 
    
        if Numeral.(Symbol.numeral_of_symbol c1 =
                    Symbol.numeral_of_symbol c2) then 

          Term.t_true

        else

          Term.t_false

      | Term.T.Const c1, Term.T.Const c2 when
          Symbol.is_decimal c1 && 
          Symbol.is_decimal c2 -> 
    
        if Decimal.(Symbol.decimal_of_symbol c1 =
                    Symbol.decimal_of_symbol c2) then 

          Term.t_true

        else

          Term.t_false


      | _ -> Term.mk_eq [expr1; expr2]


(* Type of equality

   =: 'a -> 'a -> bool *)
let type_of_eq = type_of_a_a_bool


(* Equality *)
let mk_eq expr1 expr2 = mk_binary eval_eq type_of_eq expr1 expr2 


(* ********************************************************************** *)

(* Evaluate disequality *)
let eval_neq expr1 expr2 = eval_not (eval_eq expr1 expr2)

(* Type of disequality

   <>: 'a -> 'a -> bool *)
let type_of_neq = type_of_a_a_bool


(* Disequality *)
let mk_neq expr1 expr2 = mk_binary eval_neq type_of_neq expr1 expr2 


(* ********************************************************************** *)


(* Evaluate inequality *)
let eval_lte expr1 expr2 = 

  match Term.destruct expr1, Term.destruct expr2 with

    | Term.T.Const c1, Term.T.Const c2 when
        Symbol.is_numeral c1 && 
        Symbol.is_numeral c2 -> 

      if Numeral.(Symbol.numeral_of_symbol c1 <=
                  Symbol.numeral_of_symbol c2) then 

        Term.t_true

      else

        Term.t_false

    | Term.T.Const c1, Term.T.Const c2 when
        Symbol.is_decimal c1 && 
        Symbol.is_decimal c2 -> 

      if Decimal.(Symbol.decimal_of_symbol c1 <=
                  Symbol.decimal_of_symbol c2) then 

        Term.t_true

      else

        Term.t_false


    | _ -> Term.mk_leq [expr1; expr2]


(* Type of inequality

   <=: int -> int -> bool
       real -> real -> bool *)
let type_of_lte = type_of_num_num_bool


(* Disequality *)
let mk_lte expr1 expr2 = mk_binary eval_lte type_of_lte expr1 expr2 


(* ********************************************************************** *)


(* Evaluate inequality *)
let eval_lt expr1 expr2 = 

  match Term.destruct expr1, Term.destruct expr2 with

    | Term.T.Const c1, Term.T.Const c2 when
        Symbol.is_numeral c1 && 
        Symbol.is_numeral c2 -> 

      if Numeral.(Symbol.numeral_of_symbol c1 <
                  Symbol.numeral_of_symbol c2) then 

        Term.t_true

      else

        Term.t_false

    | Term.T.Const c1, Term.T.Const c2 when
        Symbol.is_decimal c1 && 
        Symbol.is_decimal c2 -> 

      if Decimal.(Symbol.decimal_of_symbol c1 <
                  Symbol.decimal_of_symbol c2) then 

        Term.t_true

      else

        Term.t_false


    | _ -> Term.mk_lt [expr1; expr2]


(* Type of inequality

   <: int -> int -> bool
      real -> real -> bool *)
let type_of_lt = type_of_num_num_bool


(* Disequality *)
let mk_lt expr1 expr2 = mk_binary eval_lt type_of_lt expr1 expr2 


(* ********************************************************************** *)


(* Evaluate inequality *)
let eval_gte expr1 expr2 = 

  match Term.destruct expr1, Term.destruct expr2 with

    | Term.T.Const c1, Term.T.Const c2 when
        Symbol.is_numeral c1 && 
        Symbol.is_numeral c2 -> 

      if Numeral.(Symbol.numeral_of_symbol c1 >=
                  Symbol.numeral_of_symbol c2) then 

        Term.t_true

      else

        Term.t_false

    | Term.T.Const c1, Term.T.Const c2 when
        Symbol.is_decimal c1 && 
        Symbol.is_decimal c2 -> 

      if Decimal.(Symbol.decimal_of_symbol c1 >=
                  Symbol.decimal_of_symbol c2) then 

        Term.t_true

      else

        Term.t_false


    | _ -> Term.mk_geq [expr1; expr2]


(* Type of inequality

   >=: int -> int -> bool
       real -> real -> bool *)
let type_of_gte = type_of_num_num_bool


(* Disequality *)
let mk_gte expr1 expr2 = mk_binary eval_gte type_of_gte expr1 expr2 


(* ********************************************************************** *)


(* Evaluate inequality *)
let eval_gt expr1 expr2 = 

  match Term.destruct expr1, Term.destruct expr2 with

    | Term.T.Const c1, Term.T.Const c2 when
        Symbol.is_numeral c1 && 
        Symbol.is_numeral c2 -> 

      if Numeral.(Symbol.numeral_of_symbol c1 >
                  Symbol.numeral_of_symbol c2) then 

        Term.t_true

      else

        Term.t_false

    | Term.T.Const c1, Term.T.Const c2 when
        Symbol.is_decimal c1 && 
        Symbol.is_decimal c2 -> 

      if Decimal.(Symbol.decimal_of_symbol c1 >
                  Symbol.decimal_of_symbol c2) then 

        Term.t_true

      else

        Term.t_false


    | _ -> Term.mk_gt [expr1; expr2]


(* Type of inequality

   >=: int -> int -> bool
       real -> real -> bool *)
let type_of_gt = type_of_num_num_bool


(* Disequality *)
let mk_gt expr1 expr2 = mk_binary eval_gt type_of_gt expr1 expr2 




(* ********************************************************************** *)


(* Evaluate if-then-else *)
let eval_ite = function 
  | t when t == Term.t_true -> (function expr2 -> (function _ -> expr2))
  | t when t == Term.t_false -> (function _ -> (function expr3 -> expr3))
  | expr1 -> 
    (function expr2 -> 
      (function expr3 -> 
        if Term.equal expr2 expr3 then 
          expr2 
        else
          (Term.mk_ite expr1 expr2 expr3))) 


(* Type of if-then-else

   If both the second and the third argument are bounded, the result
   is bounded by the smaller of the two lower bound and the greater of
   the upper bounds.

   ite: bool -> 'a -> 'a -> 'a *)
let type_of_ite = function 
  | t when t = Type.t_bool -> 

    (function type2 -> function type3 ->

       (* If first type is subtype of second, choose second type *)
       if Type.check_type type2 type3 then type3 else 

         (* If second type is subtype of first, choose first type *)
       if Type.check_type type3 type2 then type2 else 

         (* Extend integer ranges if one is not a subtype of the other *)
         (match type2, type3 with 
           | s, t 
             when (Type.is_int_range s && Type.is_int t) ||
                  (Type.is_int s && Type.is_int_range t) -> Type.t_int

           | s, t 
             when (Type.is_int_range s && Type.is_int_range t) -> 

             let l1, u1 = Type.bounds_of_int_range s in
             let l2, u2 = Type.bounds_of_int_range t in
             
             Type.mk_int_range Numeral.(min l1 l2) Numeral.(max u1 u2)


           | _ -> raise Type_mismatch))

  | _ -> (function _ -> function _ -> raise Type_mismatch)


(* If-then-else *)
let mk_ite expr1 expr2 expr3 = 
  mk_ternary eval_ite type_of_ite expr1 expr2 expr3


(* ********************************************************************** *)


(* Type of ->

   If both the arguments are bounded, the result is bounded by the
   smaller of the two lower bound and the greater of the upper bounds.

   ->: 'a -> 'a -> 'a *)
let type_of_arrow type1 type2 =

  (* Extend integer ranges if one is not a subtype of the other *)
  (match type1, type2 with 
    | s, t 
      when (Type.is_int_range s && Type.is_int_range t) -> 
      
      let l1, u1 = Type.bounds_of_int_range s in
      let l2, u2 = Type.bounds_of_int_range t in
      
      Type.mk_int_range Numeral.(min l1 l2) Numeral.(max u1 u2)

    | _ -> type_of_a_a_a type1 type2)


(* Followed by expression *)
let mk_arrow expr1 expr2 = 

  (* Streams must be on the same clock, pick the first *)
  let res_clock = 
    if clock_check expr1.expr_clock expr2.expr_clock then 
      expr1.expr_clock
    else
      raise Clock_mismatch
  in  

  (* Types of expressions must be compatible *)
  let res_type = 
    type_of_arrow expr1.expr_type expr2.expr_type 
  in

  { expr_init = expr1.expr_init;
    expr_step = expr2.expr_step;
    expr_type = res_type;
    expr_clock = res_clock } 
  

(* ********************************************************************** *)


(* Pre expression *)
let mk_pre 
    mk_state_var_for_expr
    ctx
    ({ expr_init; expr_step; expr_type; expr_clock } as expr) = 

  (* Apply pre to initial state expression *)
  let expr_init', ctx' = match expr_init with 

    (* Expression is a variable at the current instant *)
    | t when 
        Term.is_free_var t && 
        Numeral.(Var.offset_of_state_var_instance (Term.free_var_of_term t) = 
                 base_offset)  -> 
      
      (Term.bump_state Numeral.(- one) t, ctx)

    (* Expression is a constant *)
    | t when 
        t == Term.t_true || 
        t == Term.t_false || 
        (match Term.destruct t with 
          | Term.T.Const c1 when 
              Symbol.is_numeral c1 || Symbol.is_decimal c1 -> true
          | _ -> false) -> (expr_init, ctx)

    (* Expression is not constant and not a variable at the current
       instant *)
    | _ -> 
      
      (* Fresh state variable for identifier *)
      let state_var, ctx' = mk_state_var_for_expr ctx expr in 

      (* Variable at previous instant *)
      let var = Var.mk_state_var_instance state_var pre_base_offset in

      (* Return term and new definitions *)
      (Term.mk_var var, ctx')
      
  in

  (* Apply pre to step state expression *)
  let expr_step', ctx'' = match expr_step with 

    (* Expression is identical to initial state *)
    | _ when Term.equal expr_step expr_init -> 

      (* Re-use abstraction for initial state *)
      (expr_init', ctx')

    (* Expression is a variable at the current instant *)
    | t when 
        Term.is_free_var t && 
        Numeral.(Var.offset_of_state_var_instance (Term.free_var_of_term t) = 
                 cur_offset)-> 

      (Term.bump_state Numeral.(- one) t, ctx')

    (* Expression is not constant and no variable *)
    | _ -> 
      
      (* Fresh state variable for expression *)
      let state_var, ctx' = mk_state_var_for_expr ctx' expr in

      (* Variable at previous instant *)
      let var = Var.mk_state_var_instance state_var Numeral.(- one) in

      (* Return term and new definitions *)
      (Term.mk_var var, ctx')
      
  in

  (* Return expression and new definitions *)
  ({ expr with expr_init = expr_init'; expr_step = expr_step' }, 
   ctx'') 


(* ********************************************************************** *)


(* Evaluate select from array 

   Nothing to simplify here *)
let eval_select = Term.mk_select 


(* Type of A[k]

   A[k]: array 'a 'b -> 'a -> 'b *)
let type_of_select = function 

  (* First argument must be an array type *)
  | s when Type.is_array s -> 

    (function t -> 

      (* Second argument must match index type of array *)
      if Type.check_type (Type.index_type_of_array s) t then 

        (* Return type of array elements *)
        Type.elem_type_of_array s

      else

        (* Type of indexes do not match*)
        raise Type_mismatch)

  (* Not an array type *)
  | _ -> raise Type_mismatch


(* Select from an array *)
let mk_select expr1 expr2 = 

  (* Streams must be on the same clock, pick the first *)
  let res_clock = 
    if clock_check expr1.expr_clock expr2.expr_clock then 
      expr1.expr_clock
    else
      raise Clock_mismatch
  in  

  (* Types of expressions must be compatible *)
  let res_type = 
    type_of_select expr1.expr_type expr2.expr_type 
  in

  mk_binary eval_select type_of_select expr1 expr2
  

(* ********************************************************************** *)

(* Apply let binding to expression *)
let mk_let substs ({ expr_init; expr_step } as expr) = 

  (* Split substitutions for initial state and step state *)
  let substs_init, substs_step = 
    let i, s = 
      List.fold_left
        (fun (substs_init, substs_step) (v, { expr_init; expr_step }) -> 
           ((v, expr_init) :: substs_init, (v, expr_step) :: substs_step))
        ([], [])
        substs
    in
    List.rev i, List.rev s
  in
  
  (* Apply substitutions separately *)
  { expr with 
      expr_init = Term.mk_let substs_init expr_init; 
      expr_step = Term.mk_let substs_step expr_step }

(* ********************************************************************** *)

(* Return expression of a numeral *)
let mk_int_expr n = Term.mk_num n


let mk_of_expr expr = 
  
  { expr_init = expr; 
    expr_step = expr; 
    expr_type = Term.type_of_term expr; 
    expr_clock = base_clock } 

(* 
   Local Variables:
   compile-command: "make -k -C .."
   indent-tabs-mode: nil
   End: 
*)
  
