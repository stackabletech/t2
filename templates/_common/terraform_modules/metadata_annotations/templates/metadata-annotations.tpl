---
metadata:
%{ if length(annotations) == 0 ~}
  annotations: {}
%{ else ~}
  annotations:
%{ for annotation in annotations ~}
    ${annotation.key}: "${annotation.value}"
%{ endfor ~}
%{ endif ~}