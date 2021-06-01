---
ssh_client_keys:
%{ for key in ssh_client_keys ~}
    - ${key}
%{ endfor ~}
