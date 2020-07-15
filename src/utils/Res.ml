(* This file is part of the Kind 2 model checker.

   Copyright (c) 2015 by the Board of Trustees of the University of Iowa

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

(** A result for some computation. [Ok] or [Error] of [Format.formatter]*)
type 'a res = ('a, Format.formatter -> unit) result

let ok v = Ok v

let error e = Error e

let bind r f = match r with Ok v -> f v | Error _ as e -> e

let join = function Ok r -> r | Error _ as e -> e

let map f = function Ok v -> Ok (f v) | Error _ as e -> e

let rec seq: ('a, 'e) result list -> ('a list, 'e) result  = function
  | [] -> ok []
  | h :: t -> bind h (fun h' -> 
                  bind (seq t) (fun t' ->
                      ok (h' :: t')))
       
(** Unwraps a result. *)
let unwrap = function
  | Ok arg -> arg
  | Error err ->
    Format.printf "%t" err ;
    Invalid_argument "Res.unwrap" |> raise

(** Maps functions to [Ok] or [Err]. *)
let map_res f_ok f_err = function
  | Ok arg -> Ok (f_ok arg)
  | Error err -> Error (f_err err)

(** Maps a function to a result if it's [Ok]. *)
let map f = map_res f identity

(** Maps a function to a result if it's [Error]. *)
let map_err f = map_res identity f

(** Feeds a result to a function returning a result, propagates if argument's
an error. *)
let chain ?fmt:(fmt = identity) f = function
  | Ok arg -> f arg |> map_err fmt
  | Error err -> Error err

(** Fold over a list of results. *)
let l_fold ?fmt:(fmt = identity) f init =
  let rec loop acc = function
    | head :: tail -> (
      match f acc head with
      | Ok acc -> loop acc tail
      | Error err -> Error (fmt err)
    )
    | [] -> Ok acc
  in
  loop init

(** Map over a list with a result-producing function. *)
let l_map ?fmt:(fmt = identity) f =
  let rec loop pref = function
    | head :: tail -> (
      match f head with
      | Ok res -> loop (res :: pref) tail
      | Error err -> Error (fmt err)
    )
    | [] -> Ok (List.rev pref)
  in
  loop []

(** Iterate over a list with a result-producing function. *)
let l_iter ?fmt:(fmt = identity) f =
  let rec loop = function
    | head :: tail -> (
      match f head with
      | Ok () -> loop tail
      | Error err -> Error (fmt err)
    )
    | [] -> Ok ()
  in
  loop

(* 
   Local Variables:
   compile-command: "make -C .. -k"
   tuareg-interactive-program: "./kind2.top -I ./_build -I ./_build/SExpr"
   indent-tabs-mode: nil
   End: 
*)
