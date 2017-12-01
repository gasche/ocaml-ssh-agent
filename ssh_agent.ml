(* Angstrom helpers *)
let take32 n =
  Angstrom.take (Int32.to_int n)

let count32 n =
  Angstrom.count (Int32.to_int n)

let parse_lift p1 p2 =
  let open Angstrom in
  p1 >>= fun s ->
  match parse_string p2 s with
  | Ok a -> Angstrom.return a
  | Error e -> Angstrom.fail e

let with_faraday (f : Faraday.t -> unit) : string =
  let buf = Faraday.create 1024 in
  f buf;
  Faraday.serialize_to_string buf

module Pubkey = struct
  type ssh_dss = Nocrypto.Dsa.pub

  type ssh_rsa = Nocrypto.Rsa.pub

  type t =
    | Ssh_dss of ssh_dss
    | Ssh_rsa of ssh_rsa
    | Blob of {
        key_type : string;
        key_blob : string;
      }

  let type_name = function
    | Ssh_dss _ -> "ssh-dss"
    | Ssh_rsa _ -> "ssh-rsa"
    | Blob { key_type; _ } -> key_type

  let ssh_dss =
    let open Angstrom in
    Wire.mpint >>= fun p ->
    Wire.mpint >>= fun q ->
    Wire.mpint >>= fun gg ->
    Wire.mpint >>= fun y ->
    return (Ssh_dss { p; q; gg; y })

  let ssh_rsa =
    let open Angstrom in
    Wire.mpint >>= fun e ->
    Wire.mpint >>= fun n ->
    return (Ssh_rsa { e; n })

  let blob key_type =
    Angstrom.(take_while (fun _ -> true) >>= fun key_blob ->
              return @@ Blob { key_type; key_blob; })

  let pubkey =
    let open Angstrom in
    Wire.string >>= function
    | "ssh-dss" ->
      ssh_dss
    | "ssh-rsa" ->
      ssh_rsa
    | key_type ->
      blob key_type

  let comment = Wire.string

  type identity = {
    pubkey : t;
    comment : string;
  }

  let write_pubkey t pubkey =
    match pubkey with
    | Ssh_dss { p; q; gg; y } ->
      Wire.write_string t "ssh-dss";
      Wire.write_mpint t p;
      Wire.write_mpint t q;
      Wire.write_mpint t gg;
      Wire.write_mpint t y
    | Ssh_rsa { e; n } ->
      Wire.write_string t "ssh-rsa";
      Wire.write_mpint t e;
      Wire.write_mpint t n
    | Blob { key_type; key_blob } ->
      Wire.write_string t key_type;
      Faraday.write_string t key_blob

  let to_cstruct pubkey =
    let ( <+> ) = Cstruct.append in
    match pubkey with
    | Ssh_dss { p; q; gg; y } ->
      Wire.cstruct_of_string "ssh-dss" <+>
      Wire.cstruct_of_mpint p <+>
      Wire.cstruct_of_mpint q <+>
      Wire.cstruct_of_mpint gg <+>
      Wire.cstruct_of_mpint y
    | Ssh_rsa { e; n } ->
      Wire.cstruct_of_string "ssh-rsa" <+>
      Wire.cstruct_of_mpint e <+>
      Wire.cstruct_of_mpint n
    | Blob { key_type; key_blob } ->
      Wire.cstruct_of_string key_type <+>
      Cstruct.of_string key_blob

end

(** XXX: Empty type - only as a placeholder *)
type void = { elim_empty : 'a. 'a }

type ssh_agent_request_type = [
  | `Ssh_agentc_request_identities
  | `Ssh_agentc_sign_request
  | `Ssh_agentc_add_identity
  | `Ssh_agentc_remove_identity
  | `Ssh_agentc_remove_all_identities
  | `Ssh_agentc_add_smartcard_key
  | `Ssh_agentc_remove_smartcard_key
  | `Ssh_agentc_lock
  | `Ssh_agentc_unlock
  | `Ssh_agentc_add_id_constrained
  | `Ssh_agentc_add_smartcard_key_constrained
  | `Ssh_agentc_extension
]

type _ ssh_agent_request =
  | Ssh_agentc_request_identities :
      [`Ssh_agentc_request_identities] ssh_agent_request
  | Ssh_agentc_sign_request :
      Pubkey.t * string * Protocol_number.sign_flag list
    -> [`Ssh_agentc_sign_request] ssh_agent_request
  | Ssh_agentc_add_identity :
      { key_type : string; key_contents : string; key_comment : string }
    -> [`Ssh_agentc_add_identity] ssh_agent_request
  | Ssh_agentc_remove_identity :
      Pubkey.t
    -> [`Ssh_agentc_remove_identity] ssh_agent_request
  | Ssh_agentc_remove_all_identities :
      [`Ssh_agentc_remove_all_identities] ssh_agent_request
  | Ssh_agentc_add_smartcard_key :
      void
    -> [`Ssh_agentc_add_smartcard_key] ssh_agent_request
  | Ssh_agentc_remove_smartcard_key :
      void
    -> [`Ssh_agentc_remove_smartcard_key] ssh_agent_request
  | Ssh_agentc_lock :
      string
    -> [`Ssh_agentc_lock] ssh_agent_request
  | Ssh_agentc_unlock :
      string
    -> [`Ssh_agentc_unlock] ssh_agent_request
  | Ssh_agentc_add_id_constrained :
      void
    -> [`Ssh_agentc_add_id_constrained] ssh_agent_request
  | Ssh_agentc_add_smartcard_key_constrained :
      void
    -> [`Ssh_agentc_add_smartcard_key_constrained] ssh_agent_request
  | Ssh_agentc_extension :
      string * string
    -> [`Ssh_agentc_extension] ssh_agent_request
  (** extension type * extension contents *)

type _ ssh_agent_response =
  | Ssh_agent_failure : 'a ssh_agent_response
  | Ssh_agent_success : 'a ssh_agent_response
        (* TODO: refine when success can happen *)
  | Ssh_agent_extension_failure : [`Ssh_agentc_extension] ssh_agent_response
  | Ssh_agent_identities_answer : Pubkey.identity list
    -> [`Ssh_agentc_request_identities] ssh_agent_response
  | Ssh_agent_sign_response : string
    -> [`Ssh_agentc_sign_request] ssh_agent_response

type any_ssh_agent_response =
  Any : 'a ssh_agent_response -> any_ssh_agent_response

let id_entry =
  let open Angstrom in
  parse_lift Wire.string Pubkey.pubkey >>= fun pubkey ->
  Wire.string >>= fun comment ->
  return { Pubkey.pubkey; comment }

let ssh_agent_identities_answer =
  let open Angstrom in
  BE.int32 >>= fun nkeys ->
  count32 nkeys id_entry

let ssh_agent_sign_response =
  let open Angstrom in
  Wire.string >>= fun signature ->
  return (Ssh_agent_sign_response signature)

let ssh_agent_message_type =
  let open Angstrom in
  Angstrom.any_uint8 >>|
  Protocol_number.int_to_ssh_agent >>=
  let open Protocol_number in function
  | Some SSH_AGENT_FAILURE ->
    return (Any Ssh_agent_failure)
  | Some SSH_AGENT_SUCCES ->
    return (Any Ssh_agent_success)
  | Some SSH_AGENT_IDENTITIES_ANSWER ->
    ssh_agent_identities_answer >>| fun identities ->
    Any (Ssh_agent_identities_answer identities)
  | Some SSH_AGENT_SIGN_RESPONSE ->
    ssh_agent_sign_response >>| fun r ->
    Any r
  | Some protocol_number ->
    fail ("Unimplemeted protocol number: " ^
          ssh_agent_to_string protocol_number)
  | None ->
    fail "Unknown ssh-agent protocol number"


let ssh_agent_message =
  let open Angstrom in
  BE.int32 >>= fun msg_len ->
  parse_lift (take32 msg_len)
    ssh_agent_message_type

let write_ssh_agent t n =
  let n = Protocol_number.ssh_agent_to_int n in
  Faraday.write_uint8 t n

let write_ssh_agent_request t (type a) (req : a ssh_agent_request) =
  let message = with_faraday (fun t ->
      match req with
      | Ssh_agentc_request_identities ->
        Protocol_number.(write_ssh_agent t SSH_AGENTC_REQUEST_IDENTITIES)
      | Ssh_agentc_sign_request (pubkey, data, flags) ->
        Protocol_number.(write_ssh_agent t SSH_AGENTC_SIGN_REQUEST);
        Wire.write_string t (with_faraday (fun t -> Pubkey.write_pubkey t pubkey));
        Wire.write_string t data;
        Protocol_number.write_sign_flags t flags
      | Ssh_agentc_remove_all_identities ->
        Protocol_number.(write_ssh_agent t SSH_AGENTC_REMOVE_ALL_IDENTITIES)
      | Ssh_agentc_remove_identity pubkey ->
        Protocol_number.(write_ssh_agent t SSH_AGENTC_REMOVE_IDENTITY);
        Wire.write_string t (with_faraday (fun t -> Pubkey.write_pubkey t pubkey))
      | Ssh_agentc_lock passphrase ->
        Protocol_number.(write_ssh_agent t SSH_AGENTC_LOCK);
        Faraday.write_string t passphrase
      | Ssh_agentc_unlock passphrase ->
        Protocol_number.(write_ssh_agent t SSH_AGENTC_UNLOCK);
        Faraday.write_string t passphrase
      | _ ->
        failwith "Not implemented"
    ) in
  Wire.write_uint32 t (Int32.of_int (String.length message));
  Faraday.write_string t message

module Wire = Wire
module Protocol_number = Protocol_number
