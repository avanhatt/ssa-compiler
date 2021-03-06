open Partition
open Emit_utils
open Llvm
open Llvm_shared
open Llvm_analysis

let context = global_context ()
let void_type = void_type context
let void_pt_type = pointer_type (i8_type context)
let bool_type = i1_type context
let int_type = i32_type context
let float_type = float_type context
let double_type = double_type context
let const_i32 = const_int int_type
let cores_module = create_module context "cores_module"
let comms_module = create_module context "comms_module"
let init_name = "init"
let send_name = "send"
let receive_name = "receive"
let free_name = "free_comms"
let send_arg_name = "send_argument"
let receive_arg_name = "receive_argument"
let retrieve_global_name = "retrieve_global"
let send_token_name = "send_token"
let receive_token_name = "receive_token"
let send_return_name = "send_return"
let receive_return_name = "receive_return"
let call_partitioned_name = "call_partitioned_functions"
let join_name = "join_partitioned_functions"
let address_name = "address_for_symbol"
let start_execution_name = "start_device_execution"
let end_execution_name = "end_device_execution"
let device_execute_name = "device_execute"
let print_int_name = "print_int"
let debug = ref false
let comms_id = ref 0
let i = ref 0
let target = ref PThreads

let target_ptr_type () =
  begin match !target with
  | PThreads -> i64_type context
  | BSGManycore -> i32_type context
  end

let set_metadata_string (s : string) inst =
  let s_id = mdkind_id context "reason" in
  let v = mdstring context s in
  let m = mdnode context [| v |] in
  set_metadata inst s_id m

let lookup_function_in name md =
  let callee = match lookup_function name md with
  | Some callee -> callee
  | None -> failwith ("unknown function referenced: " ^ name)
  in
  callee

let builder_and_fun partition block mappings =
  let new_block = get_block mappings partition block in
  let new_builder = builder_at_end context new_block in
  let new_fun = block_parent new_block in
  (new_builder, new_fun)

let add_debug_call builder =
  let print_int = lookup_function_in print_int_name cores_module in
  build_call print_int [| const_i32 !i |] "" builder |> ignore;
  i := !i + 1

let add_debug_calls v partitions mappings =
  let per_partition p =
    let builder, _ = builder_and_fun p (instr_parent v) mappings in
    add_debug_call builder
  in
  List.iter per_partition partitions

let new_addr_with_name name ty : llvalue =
  (* Allocate memory for this communication and a ready flag based on type *)
  let value = const_null ty in
  let ready_flag = const_null bool_type in
  let padding = const_null int_type in
  let comms_struct = const_struct context [| value; ready_flag; padding |] in

  (* Define the struct of { value, ready_flag, padding } as a global *)
  let global = define_global name comms_struct comms_module in

  (* Return the pointer to this global *)
  let gep = const_gep global [| const_i32 0 |] in
  const_ptrtoint gep (target_ptr_type ())

let new_comms_addr ty : llvalue =
  let id = !comms_id in
  comms_id := !comms_id + 1;
  new_addr_with_name ("comms_" ^ (string_of_int id)) ty

let new_arg_addr_name ty : (llvalue * string) =
  let id = !comms_id in
  comms_id := !comms_id + 1;
  let name = "arg_" ^ (string_of_int id) ^ "\x00" in
  let addr = new_addr_with_name name ty in
  (addr, name)

let size_of_ty ty =
  const_trunc (size_of ty) (target_ptr_type ())

let call_init builder md =
  let init = lookup_function_in init_name md in
  build_call init [||] "" builder

let call_partitioned_funs builder md ctx new_fun_set =
  let funs = Array.of_list (to_list new_fun_set) in
  let replace_funs_t = pointer_type (function_type void_type [| void_pt_type |]) in
  let funs_arg = const_array replace_funs_t funs in
  let funs_global = define_global "funs" funs_arg md in
  let funs_len = Array.length funs in
  let indices = [| const_i32 0; const_i32 0 |] in
  let gep = build_in_bounds_gep funs_global indices "funs" builder in
  let call_partitioned = lookup_function_in call_partitioned_name md in
  let args = [| const_i32 funs_len; gep; ctx |] in
  build_call call_partitioned args call_partitioned_name builder


let function_for_value value =
  match classify_value value with
  | Argument -> param_parent value
  | _ -> block_parent (instr_parent value)

(* Insert alloca's in order at the beginning of the entry block*)
let rec find_with_opcode_test (opcode_test : Opcode.t -> bool)  position =
  match position with
  | Before v ->
    if (opcode_test (instr_opcode v))
      then position
      else find_with_opcode_test opcode_test (instr_succ v)
  | At_end _ -> position

let value_to_value_ptr value reason builder =
  let ty = (type_of value) in
  let value_ptr, to_replace = match classify_type ty with
  | TypeKind.Double | TypeKind.Integer | TypeKind.Pointer ->

    (* alloca instruction need to be in the entry block, use the beginning *)
    let value_fun = function_for_value value in
    let entry_begin = instr_begin (entry_block value_fun) in
    let insert_at = find_with_opcode_test ((!=) Opcode.Alloca) entry_begin in
    let alloca_builder = builder_at context insert_at in
    let alloca = build_alloca ty "send_alloca" alloca_builder in

    (* bitcasts can also happen once in entry*)
    let o_test o = (o != Opcode.Alloca) && (o != Opcode.BitCast) in
    let cast_at = find_with_opcode_test o_test insert_at in
    let cast_builder = builder_at context cast_at in
    let bitcast = build_bitcast alloca void_pt_type "send_cast" cast_builder in

    (* store in the current builder *)
    let store = build_store value alloca builder in
    List.iter (set_metadata_string reason) [alloca; store; bitcast];
    bitcast, store
  | _ ->
    value, value
  in
  let size = size_of_ty ty in
  (value_ptr, size, to_replace)

let call_send_variant variant value reason (to_partition : int) id builder ctx md =
  let value_ptr, size, to_replace = value_to_value_ptr value reason builder in
  let send = lookup_function_in variant md in
  let destination = const_i32 to_partition in
  let args = [| value_ptr; size; destination; id; ctx |] in
  let send = build_call send args "" builder in
  set_metadata_string reason send;
  if !debug then add_debug_call builder;
  to_replace

let call_send_return value reason builder ctx =
  let value_ptr, size, to_replace = value_to_value_ptr value reason builder in
  let send = lookup_function_in send_return_name cores_module in
  let args = [| value_ptr; size; ctx |] in
  let send = build_call send args "" builder in
  set_metadata_string reason send;
  to_replace

let call_receive_variant variant variant_module name reason (ty : lltype) from_partition id builder ctx =
  let receive = lookup_function_in variant variant_module in
  let size = size_of_ty ty in
  let args = match (from_partition, id) with
  | Some p, Some i -> [| size; (const_i32 p); i; ctx |]
  | None, Some i -> [| size; i; ctx |]
  | _ -> [| size; ctx |]
  in
  let value = build_call receive args name builder in
  let bitcast = build_bitcast value (pointer_type ty) "bitcast" builder in
  let load = build_load bitcast "receive_load" builder in
  begin match (from_partition, id) with
  | Some _, Some i ->
    let free = lookup_function_in free_name cores_module in
    let call_free = build_call free [| i; size; ctx |] "" builder in
    set_metadata_string reason call_free
  | _ -> ()
  end;
  List.iter (set_metadata_string reason) [value; bitcast; load];
  if !debug then add_debug_call builder;
  load

let call_receive name reason (ty : lltype) (from_partition : int) id builder ctx =
  call_receive_variant receive_name cores_module name reason ty (Some from_partition) (Some id) builder ctx

let call_receive_arg name reason (ty : lltype) id builder ctx =
  call_receive_variant receive_arg_name cores_module name reason ty None (Some id) builder ctx

let call_receive_return name reason (ty : lltype) builder ctx host_md =
  call_receive_variant receive_return_name host_md name reason ty None None builder ctx

let broadcast_value value from_partition branches block block_map builder ctx =
  let value_ptr, size, _ = value_to_value_ptr value "broadcast" builder in
  let send_fun = lookup_function_in send_name cores_module in
  let insert_comms (p, br) =
    if (p != from_partition) then begin
      let id = new_comms_addr (type_of value) in
      let destination = const_i32 p in
      let args = [| value_ptr; size;  destination; id; ctx |] in
      let send = build_call send_fun args "" builder in
      set_metadata_string "broadcast" send;

      let dest_builder, _ = builder_and_fun p block block_map in
      let receive = call_receive "broadcast" receive_name (type_of value) from_partition id dest_builder ctx in
      set_operand br 0 receive
    end
  in
  List.iter insert_comms branches

let declare_external_functions host_md mappings =

  let declare_external name ty md =
    let f = declare_function name ty md in
    set_linkage External_weak f
  in
  (* TODO: we should be able to import external functions from a header *)
  (* declare init, send*, receive*, replace, join *)
  let ptr_ty = target_ptr_type () in
  let send_t = function_type void_type [| void_pt_type; ptr_ty; int_type; ptr_ty; void_pt_type |] in
  declare_external send_name send_t cores_module;
  let receive_t = function_type void_pt_type [| ptr_ty; int_type; ptr_ty; void_pt_type |] in
  declare_external receive_name receive_t cores_module;
  let send_arg_t = function_type void_type [| void_pt_type; ptr_ty; int_type; ptr_ty; void_pt_type |] in
  declare_external send_arg_name send_arg_t host_md;
  let free_t = function_type void_type [| ptr_ty; ptr_ty; void_pt_type |] in
  declare_external free_name free_t cores_module;
  let receive_arg_t = function_type void_pt_type [| ptr_ty; ptr_ty; void_pt_type |] in
  declare_external receive_arg_name receive_arg_t cores_module;
  declare_external receive_arg_name receive_arg_t host_md;
  let retrieve_global_t = function_type void_type [| void_pt_type; ptr_ty; ptr_ty; void_pt_type |] in
  declare_external retrieve_global_name retrieve_global_t host_md;
  let send_token_t = function_type void_type [| int_type; ptr_ty; void_pt_type |] in
  declare_external send_token_name send_token_t cores_module;
  let receive_token_t = function_type void_pt_type [| ptr_ty; void_pt_type |] in
  declare_external receive_token_name receive_token_t cores_module;
  let send_return_t = function_type void_type [| void_pt_type; ptr_ty; void_pt_type |] in
  declare_external send_return_name send_return_t cores_module;
  let receive_return_t = function_type void_pt_type [| ptr_ty; void_pt_type |] in
  declare_external receive_return_name receive_return_t host_md;
  let init_t = function_type void_pt_type [||] in
  declare_external init_name init_t host_md;
  let call_partitioned_funs_t = pointer_type (pointer_type (function_type void_type [| void_pt_type |])) in
  let call_partitioned_t = function_type void_pt_type [| int_type; call_partitioned_funs_t; void_pt_type |] in
  declare_external call_partitioned_name call_partitioned_t cores_module;
  declare_external call_partitioned_name call_partitioned_t host_md;
  let join_t = function_type void_type [| int_type; void_pt_type |] in
  declare_external join_name join_t host_md;

  begin match !target with
  | PThreads -> ()
  | BSGManycore ->
    let address_t = function_type int_type [| void_pt_type; void_pt_type |] in
    declare_function address_name address_t host_md |> ignore;
    let execute_t = function_type void_type [| |] in
    declare_function start_execution_name execute_t host_md |> ignore;
    declare_function end_execution_name execute_t host_md |> ignore;
    let print_int_t = function_type void_type [| ptr_ty |] in
    declare_function print_int_name print_int_t cores_module |> ignore
  end;

  let declare_function (f : llvalue) =
    if (is_declaration f) then
      declare_function (value_name f) (element_type (type_of f)) cores_module |> ignore
  in
  iter_functions declare_function host_md;

  (* Copy globals from host to device DRAM *)
  let define_global (g : llvalue) =
    match !target with
    | BSGManycore ->
      let g' = define_global (value_name g) (global_initializer g) cores_module in
      set_section ".dram" g';
      add_global mappings g g';
      add_instr mappings g g'
    | PThreads ->
      set_linkage External g;
      declare_global (element_type (type_of g)) (value_name g) cores_module |> ignore;
  in
  iter_globals define_global host_md

(* Construct/find the new and replace/host builder and function *)
let builders_from_block block p mappings host_md =
  let new_builder, new_fun = builder_and_fun p block mappings in
  let parent = block_parent block in
  let replace_opt = get_fun_opt mappings parent in
  let replace_builder, ctx = match replace_opt with
  | Some (b, c, vs) ->
    add_value vs new_fun;
    (b, c)
  | None ->
    (* clone function to new function *)
    let fun_type = element_type (type_of parent) in
    let replace_name = "replace_" ^ (value_name parent) in
    let part_fun = define_function replace_name fun_type host_md in
    let fun_begin = instr_begin (entry_block part_fun) in
    let builder = builder_at context fun_begin in
    let ctx = call_init builder host_md in
    add_fun mappings parent builder ctx new_fun;

    (* map function args to clone args *)
    let old_args = params parent in
    let new_args = params part_fun in
    Array.iter2 (add_instr mappings) old_args new_args;

    (builder, ctx)
  in

  (new_builder, new_fun, replace_builder, ctx)

let is_alloca v =
  match instr_opcode v with
  | Alloca -> true
  | _ -> false

let lookup_address builder name ctx host_md =
    let address_lookup = lookup_function_in address_name host_md in
    let name_value = const_string context name in
    let name_global = define_global name name_value host_md in
    let bitcast = build_bitcast name_global void_pt_type "arg_cast" builder in
    let args = [| bitcast; ctx; |] in
    build_call address_lookup args name builder

let host_argument_address builder addr name ctx host_md =
  match !target with
  | PThreads -> addr
  | BSGManycore -> lookup_address builder name ctx host_md

let receive_arg_from_host old_arg block partition mappings host_md =
  match (get_arg_opt mappings partition old_arg) with
  | Some new_arg -> new_arg
  | None ->
    begin match (!target, classify_type (type_of old_arg)) with
    | (BSGManycore, Pointer) ->
      failwith "Pointer arguments for BSGManycore target not implemented yet"
    | _ ->
      (* Send argument from host to device SRAM, receive in the entry block *)
      let _, new_fun, replace_builder, r_ctx = builders_from_block block partition mappings host_md in
      let entry = entry_block new_fun in
      let entry_builder = builder_at context (instr_begin entry) in
      let ctx = param new_fun 0 in
      let replace_op = get_instr mappings old_arg in
      let addr, name = new_arg_addr_name (type_of old_arg) in
      let host_addr = host_argument_address replace_builder addr name r_ctx host_md in
      let call = call_receive_arg "argument" "replace argument" (type_of old_arg) addr entry_builder ctx in
      call_send_variant send_arg_name replace_op "replace argument" partition host_addr replace_builder r_ctx host_md |> ignore;
      add_arg mappings partition old_arg call;
      call
    end

let replace_operand idx inst block partition builder find_partition mappings host_md =
  let op = operand inst idx in
  match (get_instr_opt mappings op) with
  | Some new_op ->
    (* If the value is an argument, send/receive as needed *)
    begin match (classify_value op) with
    | Argument ->
      let new_arg = receive_arg_from_host op block partition mappings host_md in
      set_operand inst idx new_arg
    | _ -> (* Non-argument value *)
    (* If the operand is a global, check whether it can write to memory *)
    (* If the operand is on a different partition, insert send/receive *)
    let op_partition = find_partition op in
    if (partition != op_partition) && not (is_alloca op) then
      let op_builder, op_fun = builder_and_fun op_partition block mappings in
      let _, cur_fun = builder_and_fun partition block mappings in
      let id = new_comms_addr (type_of new_op) in
      let ctx = param cur_fun 0 in
      let op_ctx = param op_fun 0 in
      let receive = call_receive receive_name "replace mapped op" (type_of new_op) op_partition id builder ctx in
      call_send_variant send_name new_op "replace mapped op" partition id op_builder op_ctx cores_module |> ignore;
      set_operand inst idx receive
    else
      set_operand inst idx new_op
    end
  | None -> (* do nothing for literal/constant values *) ()

let replace_operands inst block partition builder find_partition mappings host_md =
  let replace_op idx =
     replace_operand idx inst block partition builder find_partition mappings host_md
  in
  let arity = num_operands inst in
  let arity_range = Core.List.range 0 arity in
  List.iter replace_op arity_range

let repair_phi_node find_partition mappings host_md phi : unit =
  let map_incoming partition (v, block) =
    let prev_block = get_block mappings partition block in
    match (get_instr_opt mappings v) with
    | Some new_val ->
      begin match classify_value v with
      | Argument ->
        (* If the operand is an argument, look it up or fetch on the previous
         block *)
        let new_arg = receive_arg_from_host v block partition mappings host_md in
        (new_arg, prev_block)
      | _ ->
        let op_partition = find_partition v in
        (* If the operand is on a different partition, insert send/receive
           on the SOURCE block, not the current block *)
        if partition != op_partition then begin
          let op_block = get_block mappings op_partition block in
          let op_builder = builder_at_end context op_block in
          let prev_block_builder = builder_at_end context prev_block in
          let id = new_comms_addr (type_of new_val) in
          let ctx = param (block_parent op_block) 0 in
          call_send_variant send_name new_val "repair_phi" partition id op_builder ctx cores_module |> ignore;
          let receive = call_receive "repair_phi" receive_name (type_of new_val) op_partition id prev_block_builder ctx in
          (receive, prev_block)
        end
        else
          (new_val, prev_block)
      end
    | None ->
      (v, prev_block)
  in
  match (instr_opcode phi) with
  | PHI ->
    let partition = find_partition phi in
    let new_incoming = List.map (map_incoming partition) (incoming phi) in
    let new_phi = get_instr mappings phi in
    List.iter (fun inc -> add_incoming inc new_phi) new_incoming
  | _ -> ()

let set_branch_destination br destinations p block mappings =
  let per_destination (idx, dest) =
    let new_dest = get_block mappings p dest in
    set_operand br idx (value_of_block new_dest)
  in
  List.iter per_destination destinations;
  let builder, _ = builder_and_fun p block mappings in
  insert_into_builder br "" builder

let add_branch_instructions v block find_partition partitions mappings host_md =
  match get_branch v with
  | Some (`Conditional (v0, _, _)) ->
    (* Note: cannot get these from the pattern match above, because the order
    may not match the operand indexing *)
    let b1 = operand v 1 |> block_of_value in
    let b2 = operand v 2 |> block_of_value in
    let p0 = find_partition v0 in
    let p0_builder, p0_f = builder_and_fun p0 block mappings in
    let ctx = param p0_f 0 in
    let v0' = ref v0 in
    let per_partition p : (int * llvalue) =
      let br = instr_clone v in
      (* Send v0 to every core but the one it's already on *)
      if (p == p0) then begin
        replace_operand 0 br block p p0_builder find_partition mappings host_md;
        v0' := operand br 0
      end;
      (p, br)
    in
    let branches = List.map per_partition partitions in
    if (List.length branches > 1) then
    broadcast_value !v0' p0 branches block mappings p0_builder ctx;

    (* Set branching destinations to mapped blocks per paritition *)
    let dests = [(1, b1); (2, b2)] in
    List.iter (fun (p, br) -> set_branch_destination br dests p block mappings) branches
  | Some (`Unconditional old_dest) ->
    let per_partition p =
      let br = instr_clone v in
      set_branch_destination br [(0, old_dest)] p block mappings
    in
    List.iter per_partition partitions
  | None -> failwith "Instruction must be branch"

let repair_branch find_partition mappings partitions host_md br =
  match (instr_opcode br) with
  | Br ->
    let block = instr_parent br in
    add_branch_instructions br block find_partition partitions mappings host_md
  | _ -> ()

let clone_blocks_per_partition host_md partitions mappings =
  (* Get all the basic blocks, and map them to new blocks per partition *)
  let per_block partition old_fun new_fun old_block =
    let new_block = if old_block == entry_block old_fun
      then entry_block new_fun
      else append_block context "l" new_fun
    in
    add_block mappings partition old_block new_block
  in

  let per_partition fn partition =
    let fun_type = function_type void_type [| void_pt_type |] in
    let new_name = (value_name fn) ^ "_" ^ (string_of_int partition) in
    let new_fun = define_function new_name fun_type cores_module in
    let decl = declare_function new_name fun_type host_md in
    set_linkage External new_fun;
    set_linkage External_weak decl;

    iter_blocks (per_block partition fn new_fun) fn
  in
  let per_function fn = List.iter (per_partition fn) partitions in
  iter_included_functions per_function host_md

let get_nonempty_partitions (dfg : placement ValueMap.t) : int list =
  ValueMap.bindings dfg |>
   List.map (fun (_, p) -> p.partition) |> List.sort_uniq compare

let insert_ret_void block block_map partition =
  let builder, _ = builder_and_fun partition block block_map in
  build_ret_void builder |> ignore

let add_return_allocation fn =
  (* Allocate a return struct *)
  let fn_type = return_type (element_type (type_of fn)) in
  if fn_type != void_type then
    new_addr_with_name "return_struct" fn_type |> ignore
  else
    (* If the type is void, allocate a bool in the struct for now *)
    new_addr_with_name "return_struct" bool_type |> ignore;

  match lookup_global "return_struct" comms_module with
  | Some g ->
    begin match !target with
    | BSGManycore -> set_section ".dram" g
    | PThreads -> ()
    end
  | _ -> ()

let add_alloca_instructions v mappings =
  let ty = type_of v in
  let global = define_global "alloca" (const_null (element_type ty)) cores_module in
  if (!target = BSGManycore) then set_section ".dram" global;
  set_volatile true global;
  set_alignment (alignment v) global;
  add_instr mappings v global

let add_load_store_synchronization v p _block mappings =
  let global = match (instr_opcode v) with
  | Load -> operand v 0
  | Store -> operand v 1
  | _ -> failwith "Expected load or store"
  in
  begin match (get_global_last_access_opt mappings global) with
  | Some p' ->
    (* Last access is on a different partition, insert synchronization *)
    if p != p' then begin
      (* TODO: rethink this! *)
    end
  | None -> ()
  end;
  set_global_last_access mappings global p

let add_straightline_instructions v block placement find_partition partitions mappings host_md =
  let p = placement.partition in
  let new_builder, new_fun, _, _ = builders_from_block block p mappings host_md in
  let ctx = param new_fun 0 in
  match (instr_opcode v) with
  | Ret ->
    (* If it's not a void return, it needs to be sent back to the host;
    there may be multiple returns per function, so we'll insert the receive
    once, later. *)
    if (num_operands v) > 0 then begin
      let clone = instr_clone v in
      replace_operands clone block p new_builder find_partition mappings host_md;
      let ret = operand clone 0 in
      let call = call_send_return ret "return" new_builder ctx in
      set_metadata_string "return" call
    end;
    (* Insert void return at this block for all partitions *)
    List.iter (insert_ret_void block mappings) partitions
  | PHI ->
    let clone = build_empty_phi (type_of v) "new_phi" new_builder in
    add_instr mappings v clone
  | _ ->
    let clone = instr_clone v in
    add_instr mappings v clone;
    replace_operands clone block p new_builder find_partition mappings host_md;
    insert_into_builder clone "" new_builder

let insert_called_function_if_needed f =
  (* TODO: check for memory writes/side effects, deep clone*)
  let partitioned = include_function f in
  let ext_defined = is_declaration f in
  if (not partitioned && not ext_defined) then
    failwith ("Partitioned function references unavailable function: " ^
      (string_of_llvalue f))

let rec find_init position =
  match position with
  | Before v ->
    if (instr_opcode v == Call) then instr_succ v else find_init (instr_succ v)
  | At_end _ -> failwith "builder should be after init"

let replace_fun mappings host_md old_fun (_, ctx, new_fun_set) =
  let old_name = value_name old_fun in
  let new_fun = lookup_function_in ("replace_" ^ old_name) host_md in
  let return_t = return_type (element_type (type_of old_fun)) in
  replace_all_uses_with old_fun new_fun;
  let after_init = find_init (instr_begin (entry_block new_fun)) in

  let builder = builder_at context after_init in
  let end_builder = builder_at_end context (entry_block new_fun) in

  let after_execute =
    match !target with
    | PThreads ->
      (* For pthreads, we need to call the partitioned functions, then later
      join the threads*)
      let threads = call_partitioned_funs builder host_md ctx new_fun_set in

      (* After execution function (timing depends on return type) *)
      fun _ ->
        let join = lookup_function_in join_name host_md in
        let funs_len = size new_fun_set in
        build_call join [| const_i32 funs_len; threads |] "" end_builder |> ignore
    | BSGManycore ->
      (* For manycore, we need the host to call the host's start_device_execution
      function, which will call device_execute and call_partitioned_funs
      device-side. *)

      (* Define the device-side device_execute function, which will get called
      from C-defined host code using the BSG API *)
      let fun_ty = function_type void_type [| |] in
      let device_exec = define_function device_execute_name fun_ty cores_module in
      let device_builder = builder_at context (instr_begin (entry_block device_exec)) in
      let null_ctx = const_null (void_pt_type) in
      call_partitioned_funs device_builder cores_module null_ctx new_fun_set |> ignore;
      build_ret_void device_builder |> ignore;

      (* Call start_device_execution which envokes BSG API calls *)
      let start_exec = lookup_function_in start_execution_name host_md in
      build_call start_exec [| |] "" end_builder |> ignore;

      (* After execution function (timing depends on return type) *)
      fun _ ->
        (* Copy used global values back over from DRAM, delete unused globals *)
        let retrieve_global host_g device_g =
          match use_begin device_g with
          | Some _ ->
            let host_ptr = const_gep host_g [| const_i32 0 |] in
            let bitcast = build_bitcast host_ptr void_pt_type "" end_builder in
            let size = size_of_ty (element_type (type_of host_g)) in
            let name = (value_name device_g) ^ "\x00" in
            let addr = lookup_address end_builder name ctx host_md in
            let retrieve = lookup_function_in retrieve_global_name host_md in
            let args = [| bitcast; size; addr; ctx|] in
            build_call retrieve args "" end_builder |> ignore
          | None ->
            delete_global device_g
        in

        iter_mapped_globals mappings retrieve_global;

        (* Call end_device_execution which envokes BSG API calls *)
        let end_exec = lookup_function_in end_execution_name host_md in
        build_call end_exec [| |] "" end_builder |> ignore
  in

  if return_t == void_type then begin
    after_execute ();
    build_ret_void end_builder |> ignore
  end
  else begin
    let return = call_receive_return "return" "return" return_t end_builder ctx host_md in
    after_execute ();
    build_ret return end_builder |> ignore
  end

let set_target_specific_data_layout host_md =
  match !target with
  | PThreads ->
    set_data_layout "e-m:o-i64:64-f80:128-n8:16:32:64-S128" cores_module
  | BSGManycore ->
    set_target_triple "riscv32-unknown-elf" host_md;
    set_target_triple "riscv32-unknown-elf" cores_module;
    set_data_layout "e-m:e-p:32:32-i64:64-n32-S128" host_md;
    set_data_layout "e-m:e-p:32:32-i64:64-n32-S128" cores_module;
    (* TODO: don't map if only used by one core *)
    (* Map globals to DRAM *)
    let set g = if (is_externally_initialized g)
      then set_section ".dram" |> ignore
    in
    iter_globals set cores_module

let emit_llvm tg filename (dfg : placement ValueMap.t) (host_md : llmodule) db =
  print_endline "\nStarting to emit LLVM";
  target := tg;
  debug := db;

  let mappings = init_mappings () in
  declare_external_functions host_md mappings;
  let partitions = get_nonempty_partitions dfg in

  let find_partition_opt v =
    match ValueMap.find_opt v dfg with
    | Some p -> Some p.partition
    | None -> None
  in
  clone_blocks_per_partition host_md partitions mappings;

  let add_instructions (v : llvalue) =
    let op = instr_opcode v in
    let block = instr_parent v in
    let add_straightline () =
      let placement = ValueMap.find v dfg in
      let find_partition_default v' = match find_partition_opt v' with
      | Some p' -> p'
      | None -> placement.partition
      in
      add_straightline_instructions v block placement find_partition_default partitions mappings host_md
    in
    begin match (op : Opcode.t) with
    | Alloca -> add_alloca_instructions v mappings
    | Call ->
      insert_called_function_if_needed (function_from_call v);
      add_straightline ()
    | Br -> () (* To be repaired later *)
    | _ -> add_straightline ()
    end;
   if !debug then begin match (op : Opcode.t) with
    | Ret | PHI -> ()
    | _ -> add_debug_calls v partitions mappings
    end

  in
  let per_function f fn =
    let blocks = fold_left_blocks (fun bs b -> b::bs) [] fn in
    let sorted = Sort_basic_blocks.sort_blocks (List.rev blocks) in
    List.iter (iter_instrs f) sorted
  in

  let find_partition v = match (ValueMap.find_opt v dfg) with
  | Some p -> p.partition
  | None -> failwith (string_of_llvalue v)
  in
  iter_included_functions (per_function add_instructions) host_md;
  let repair_phi = repair_phi_node find_partition mappings host_md in
  iter_included_functions (per_function repair_phi) host_md;

  let repair_branch = repair_branch find_partition mappings partitions host_md in
  iter_included_functions (per_function repair_branch) host_md;

  iter_included_functions add_return_allocation host_md;
  iter_funs mappings (replace_fun mappings host_md);
  set_target_specific_data_layout host_md;

  let per_global g =
    let ty = element_type (type_of g) in
    declare_global ty (value_name g) cores_module |> ignore;
    declare_global ty (value_name g) host_md |> ignore
  in
  iter_globals per_global comms_module;

  print_module (filename ^ "_cores.ll") cores_module;
  print_module (filename ^ "_host.ll") host_md;
  print_module (filename ^ "_comms.ll") comms_module;

  match verify_module cores_module with
  | Some _s -> ()
  | None -> ()
