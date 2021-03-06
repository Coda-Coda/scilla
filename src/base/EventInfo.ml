open Core_kernel
open! Int.Replace_polymorphic_compare
open Result.Let_syntax
open TypeUtil
open Identifier
open Type
open Syntax
open ContractUtil.MessagePayload
open MonadUtil

module ScillaEventInfo
    (SR : Rep) (ER : sig
      include Rep

      val get_type : rep -> PlainTypes.t inferred_type
    end) =
struct
  module SER = SR
  module EER = ER
  module EISyntax = ScillaSyntax (SR) (ER)
  module TU = TypeUtilities
  module SCU = ContractUtil.ScillaContractUtil (SR) (ER)
  open EISyntax
  open TU
  open SCU

  (* Given a contract, return a list of events it may create,
   * and the parameter types of the event. *)
  let event_info (cmod : cmodule) =
    (* Given a message and a current list of event info, extract
     * info from message and append to the list. *)
    let extract_from_message bloc m acc =
      (* Check if this is for an event. *)
      match List.Assoc.find m eventname_label ~equal:String.( = ) with
      | Some epld -> (
          let emsg = "Error determining event name\n" in
          let%bind eventname =
            match epld with
            | MLit l -> (
                match l with StringLit s -> pure s | _ -> fail1 emsg bloc )
            (* Variables are not allowed for eventname_label to ensure that
               all possible events can be determined statically. *)
            | MVar _ -> fail1 emsg bloc
          in
          (* Get the type of the event parameters. *)
          let filtered_m =
            List.filter m ~f:(fun (label, _) ->
                not String.(label = eventname_label))
          in
          let%bind m_types =
            mapM
              ~f:(fun (fname, pl) ->
                let%bind t =
                  match pl with
                  | MLit l -> literal_type l
                  | MVar v ->
                      let t' = ER.get_type (get_rep v) in
                      pure t'.tp
                in
                pure (fname, t))
              filtered_m
          in
          (* If we already have an entry for "eventname" in "acc",
             * check that the type matches. Add entry otherwise. *)
          match List.Assoc.find acc eventname ~equal:String.( = ) with
          | Some tlist ->
              (* verify types match *)
              let printer tplist =
                "["
                ^ ( List.map tplist ~f:(fun (n, t) ->
                        Printf.sprintf "(%s : %s); " n (pp_typ t))
                  |> String.concat ~sep:"" )
                ^ "]"
              in
              let matcher m_types tlist =
                List.length m_types = List.length tlist
                && (* Check that each entry in tlist is equal to the same entry in m_types. *)
                List.for_all tlist ~f:(fun (n1, t1) ->
                    List.exists m_types ~f:(fun (n2, t2) ->
                        String.(n1 = n2) && [%equal: Type.t] t2 t1))
              in
              if not @@ matcher m_types tlist then
                fail1
                  (Printf.sprintf "Parameter mismatch for event %s. %s vs %s\n"
                     eventname (printer tlist) (printer m_types))
                  bloc
              else pure acc
          | None ->
              (* No entry. *)
              let entry = (eventname, m_types) in
              pure (entry :: acc) )
      | None -> (* Not for an event. *) pure acc
    in

    fold_over_messages cmod ~init:[] ~f:extract_from_message
end
