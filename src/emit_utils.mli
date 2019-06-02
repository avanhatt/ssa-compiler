open Llvm

type mappings
type valueset

(* Make a new empty state. *)
val init_mappings : unit -> mappings

val add_instr : mappings -> llvalue -> llvalue -> unit
val get_instr :  mappings -> llvalue -> llvalue
val get_instr_opt :  mappings -> llvalue -> (llvalue option)

val add_arg : mappings -> int -> llvalue -> llvalue -> unit
val get_arg_opt :  mappings -> int -> llvalue -> llvalue option

val add_block : mappings -> int -> llbasicblock -> llbasicblock -> unit
val get_block : mappings -> int -> llbasicblock -> llbasicblock

(* (m : mappings) (k : llvalue) (b : llbuilder) (ctx: llvalue) (new_fun : llvalue) *)
val add_fun : mappings -> llvalue -> llbuilder -> llvalue -> llvalue -> unit
val get_fun : mappings -> llvalue -> (llbuilder * llvalue * valueset)
val get_fun_opt : mappings -> llvalue -> ((llbuilder * llvalue * valueset) option)
val iter_funs : mappings -> (llvalue -> (llbuilder * llvalue * valueset) -> unit) -> unit

val add_value : valueset -> llvalue -> unit
val to_list : valueset -> llvalue list