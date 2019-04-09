open Dfg
open Ast
open Partition

let compare_partition_funs (p1, f1) (p2, f2) =
  let same_partitions = compare p1 p2 in
  if same_partitions != 0 then same_partitions else compare f1 f2

module NewFunctionMap =
  Map.Make(struct type t = int * Llvm.llvalue;; let compare = compare_partition_funs end)

let format_partition (p, (t1, t2)) =
  (string_of_int p) ^ ", ("  ^ (string_of_int t1) ^ ", " ^ (string_of_int t2) ^ ")"

let emit_llvm (dfg : partitioning) (llvm_to_ast : (Llvm.llvalue * com) list) (node_map : node ComMap.t) =
  let partition_for_com (c : com) =
    let node = ComMap.find c node_map in
    let (_, p, (t1, t2)) = List.find (fun (n, _, _) -> node == n) dfg in
    (p, (t1, t2))
  in
  let partitions = List.map (fun (v, c) -> (v, partition_for_com c)) llvm_to_ast in
  let sort_by (_, (p1, _)) (_, (p2, _)) = compare p1 p2 in
  let sorted = List.stable_sort sort_by partitions in

  let context = (Llvm.create_context ()) in
  let new_module = Llvm.create_module context "new_module" in
  let new_funs = ref NewFunctionMap.empty in

  let add_instruction (v, (p, (_, _))) =
    match (Llvm.classify_value v) with
    | Instruction _ ->
      let parent_fun = (Llvm.block_parent (Llvm.instr_parent v)) in
      let key = (p, parent_fun) in
      let insts_opt = NewFunctionMap.find_opt key !new_funs in
      let insts = begin match insts_opt with | Some l -> l | None -> [] end in
      new_funs := NewFunctionMap.add key (v::insts) !new_funs
    | _ -> Printf.printf "not instruction: %s\n" (Llvm.string_of_llvalue v);
  in

  List.iter add_instruction sorted;

  let construct_new_functions (p, f) insts =
    let t = Llvm.type_of f in
    let fun_type = Llvm.function_type (Llvm.return_type t) (Llvm.param_types t) in
    let new_name = (Llvm.value_name f) ^ "_" ^ (string_of_int p) in
    let part_fun = Llvm.define_function new_name fun_type new_module in
    let fun_begin = Llvm.instr_begin (Llvm.entry_block part_fun) in
    let builder = Llvm.builder_at context fun_begin in
    List.iter (fun i -> Llvm.insert_into_builder (Llvm.instr_clone i) "" builder) (List.rev insts);
  in

  NewFunctionMap.iter construct_new_functions !new_funs;

  Llvm.print_module "llvm_out.ll" new_module

(*

        Llvm.insert_into_builder (Llvm.instr_clone v) "" builder;

val define_function : string -> lltype -> llmodule -> llvalue
val create_module : llcontext -> string -> llmodule
val create_context : unit -> llcontext
val function_type : lltype -> lltype array -> lltype
val print_module : string -> llmodule -> unit

val insert_into_builder : llvalue -> string -> llbuilder -> unit
insert_into_builder i name b inserts the specified instruction i at the position specified by the instruction builder b. See the method llvm::LLVMBuilder::Insert.

val builder_at_end : llcontext -> llbasicblock -> llbuilder
builder_at_end bb creates an instruction builder positioned at the end of the basic block bb. See the constructor for llvm::LLVMBuilder.

val function_begin : llmodule -> (llmodule, llvalue) llpos

val builder_at : llcontext ->
       (llbasicblock, llvalue) llpos -> llbuilder
builder_at ip creates an instruction builder positioned at ip. See the constructor for llvm::LLVMBuilder.
*)