[Interface]
Address = 10.11.12.1/24
ListenPort = 52888
PrivateKey = ${wg_nat_private_key}

%{ for index, public_key in wg_client_public_keys ~}
[Peer]
PublicKey = ${public_key}
AllowedIPs = 10.11.12.${index+2}/32

%{ endfor ~}
