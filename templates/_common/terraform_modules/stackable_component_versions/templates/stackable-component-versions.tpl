---
stackable_component_versions:
%{ for component in stackable_component_versions ~}
  ${component.name}:
    repository: stackable-${component.repository}
    version: ${component.version}%{ endfor ~}