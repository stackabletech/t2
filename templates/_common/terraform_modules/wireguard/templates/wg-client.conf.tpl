[Interface]
PrivateKey = ${client_private_key}
Address = 10.11.12.${index+2}
DNS = 10.11.12.1

[Peer]
PublicKey = ${wg_server_public_key}
AllowedIPs = 10.11.12.0/24%{ for ip in allowed_ips ~},${ip}/32%{ endfor ~}

Endpoint=${endpoint_ip}:52888
PersistentKeepAlive=20
