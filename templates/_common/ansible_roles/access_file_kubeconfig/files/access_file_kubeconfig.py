import yaml

def read_kubeconfig():
    with open ("kubeconfig", "r") as f:
        return f.read()

if __name__ == "__main__":

    readme_txt = """#  To access the cluster, use the kubeconfig which is contained in this file as .kubeconfig.
#  It is self-contained, so you do not need further credentials or tools.
#
"""

    access_yaml = { 'kubeconfig': read_kubeconfig() }

    with open ("resources/access.yaml", "w") as f:
        f.write(readme_txt)
        f.write("---\n")
        f.write(yaml.safe_dump(access_yaml , default_flow_style=False, default_style="|", allow_unicode=True))
        f.close()
