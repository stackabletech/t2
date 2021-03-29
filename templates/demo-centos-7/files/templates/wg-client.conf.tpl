[Interface]
PrivateKey = ${wg_client_private_key}
Address = 10.11.12.${index+2}
DNS = 10.11.12.1

[Peer]
PublicKey = ${wg_nat_public_key}
AllowedIPs = 10.11.12.0/24%{ for nodetype in nodes ~}%{ for node in nodetype ~},${node.primary_ip}/32%{ endfor ~}%{ endfor ~},${orchestrator_ip}/32

Endpoint=${nat_public_ip}:52888
PersistentKeepAlive=20
