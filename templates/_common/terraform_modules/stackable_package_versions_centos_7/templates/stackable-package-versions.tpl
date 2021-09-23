---
stackable_package_versions:
%{ for package in stackable_package_versions ~}
    ${package.name}: ${package.name_with_version}%{ endfor ~}