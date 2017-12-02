[%%cenum
type ssh_agent =
  | SSH_AGENT_reserved1 [@id 1]
  | SSH_AGENT_reserved2 [@id 2]
  | SSH_AGENT_reserved3 [@id 3]
  | SSH_AGENT_reserved4 [@id 4]
  | SSH_AGENT_FAILURE [@id 5]
  | SSH_AGENT_SUCCES [@id 6]
  | SSH_AGENT_reserved7 [@id 7]
  | SSH_AGENT_reserved8 [@id 8]
  | SSH_AGENT_reserved9 [@id 9]
  | SSH_AGENT_reserved10 [@id 10]
  | SSH_AGENTC_REQUEST_IDENTITIES [@id 11]
  | SSH_AGENT_IDENTITIES_ANSWER [@id 12]
  | SSH_AGENTC_SIGN_REQUEST [@id 13]
  | SSH_AGENT_SIGN_RESPONSE [@id 14]
  | SSH_AGENTC_ADD_IDENTITY [@id 17]
  | SSH_AGENTC_REMOVE_IDENTITY [@id 18]
  | SSH_AGENTC_REMOVE_ALL_IDENTITIES [@id 19]
  | SSH_AGENTC_ADD_SMARTCARD_KEY [@id 20]
  | SSH_AGENTC_REMOVE_SMARTCARD_KEY [@id 21]
  | SSH_AGENTC_LOCK [@id 22]
  | SSH_AGENTC_UNLOCK [@id 23]
  | SSH_AGENT_reserved24 [@id 24]
  | SSH_AGENTC_ADD_ID_CONSTRAINED [@id 25]
  | SSH_AGENTC_ADD_SMARTCARD_KEY_CONSTRAINED [@id 26]
  | SSH_AGENTC_EXTENSION [@id 27]
  | SSH_AGENT_EXTENSION_FAILURE [@id 28]
[@@uint8_t][@@sexp]]

let write_ssh_agent t ssh_agent =
  Wire.write_byte t (ssh_agent_to_int ssh_agent)

let cstruct_of_ssh_agent ssh_agent =
  ssh_agent_to_int ssh_agent |> Wire.cstruct_of_byte

[%%cenum
type sign_flag =
  | SSH_AGENT_RSA_SHA2_256 [@id 2]
  | SSH_AGENT_RSA_SHA2_512 [@id 4]
[@@uint8_t][@@sexp]]

let mask_to_sign_flags mask =
  let mask_test mask flag =
    if sign_flag_to_int flag land mask <> 0
    then [flag]
    else [] in
  List.concat (List.map (mask_test mask) [SSH_AGENT_RSA_SHA2_256; SSH_AGENT_RSA_SHA2_512])

let write_sign_flags t sign_flags =
  let flags = List.fold_left (fun acc sign_flag ->
      sign_flag_to_int sign_flag lor acc)
      0 sign_flags in
  flags |> Int32.of_int |> Wire.write_uint32 t

let cstruct_of_sign_flags sign_flags =
  let flags = List.fold_left (fun acc sign_flag ->
      sign_flag_to_int sign_flag lor acc)
      0 sign_flags in
  flags |> Int32.of_int |> Wire.cstruct_of_uint32

(* TODO: constraint types *)
type key_constraint = {
  constraint_type : int;
  constraint_data : string;
}

let write_key_constraints t constraints =
  List.iter (fun { constraint_type; constraint_data } ->
      Faraday.write_uint8 t constraint_type;
      Faraday.write_string t constraint_data)
    constraints
