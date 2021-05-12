---
ssh_client_keys:
%{ for key in ssh_client_keys ~}
    - ${key}
%{ endfor ~}
stackable_versions:
%{ for key,value in stackable_versions ~}
    ${key}: "${value}"
%{ endfor ~}

