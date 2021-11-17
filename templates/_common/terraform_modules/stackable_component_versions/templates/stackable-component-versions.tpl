---
%{ if length(stackable_component_versions) == 0 ~}
stackable_component_versions: {}
%{ else ~}
stackable_component_versions:
%{ for component in stackable_component_versions ~}
  ${component.name}:
    repository: stackable-${component.repository}
    version: ${component.version}%{ endfor ~}
%{ endif ~}