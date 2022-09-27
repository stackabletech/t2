import yaml

def read_kubeconfig():
    with open ("kubeconfig", "r") as f:
        return f.read()

if __name__ == "__main__":

    readme_txt = """To access the cluster, use the kubeconfig which is contained in this file as .resources.kubeconfig.
It is self-contained, so you do not need further credentials or tools.
"""

    access_yaml = { 'readme': readme_txt, 'resources': { 'kubeconfig': read_kubeconfig() } }

    with open ("resources/access.yaml", "w") as f:
        f.write(yaml.safe_dump(access_yaml , default_flow_style=False, default_style="|"))
        f.close()
