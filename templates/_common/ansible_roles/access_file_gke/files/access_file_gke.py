import yaml

def read_gke_coordinates():
    with open ("gke_coordinates.yaml", "r") as f:
        return yaml.load(f.read(), Loader=yaml.FullLoader)

def read_gcloud_credentials():
    with open ("gcloud_credentials.json", "r") as f:
        return f.read()

README_TXT_TEMPLATE = """#  This file describes how to access a T2 Kubernetes cluster which runs on Google Cloud GKE
#
#  The Kubernetes cluster was created together with an individual admin account which can access the cluster.
#
#  Please configure your GCloud CLI to use this admin account:
#
#      gcloud auth login --cred-file=</path/to/credentials.json>
#
#  (You find the credentials file under .data.gcloud_credentials in this YAML file)
#
#  Warning! Make sure not to overwrite your existing GCloud CLI account settings accidentally.
#
#  After you successfully logged in using the GCloud CLI, you have to create a kubeconfig file to access the cluster.
#  This command creates the config for you:
#
#      gcloud container clusters get-credentials {cluster_name} --zone {zone} --project {project}
#
#  If you already have a config at the default location (most probably ~/.kube/config), the command will merge the new
#  config into the existing one as a so called context. To specify a different location, you can set the KUBECONFIG
#  environment variable to contain the config path.
#
#  Please refer to the GCloud CLI help for details:
#  https://cloud.google.com/sdk/gcloud/reference/container/clusters/get-credentials
#
#  To be machine-processable, this file also contains...
#
#  - ...a script 'access.sh' to execute all the aforementioned commands in one go (under .access_script)
#  - ...the information you will need if you want to use a different way to access the cluster (under .data.<key>)
#
"""

ACCESS_SCRIPT_TEMPLATE = """#!/bin/bash
cat << GCLOUD_CREDFILE_EOF > /tmp/{cluster_name}-credfile.json
{gcloud_credentials}
GCLOUD_CREDFILE_EOF
gcloud auth login --cred-file=/tmp/{cluster_name}-credfile.json
rm -f /tmp/{cluster_name}-credfile.json
gcloud container clusters get-credentials {cluster_name} --zone {zone} --project {project}
"""

if __name__ == "__main__":

    gke_coordinates = read_gke_coordinates()
    gcloud_credentials = read_gcloud_credentials()

    access_script = ACCESS_SCRIPT_TEMPLATE.format(**gke_coordinates)
    readme_txt = README_TXT_TEMPLATE.format(**gke_coordinates)

    access_yaml = { 'access_script': access_script, 'data': gke_coordinates }

    with open ("resources/access.yaml", "w") as f:
        f.write(readme_txt)
        f.write("---\n")
        f.write(yaml.safe_dump(access_yaml , default_flow_style=False, default_style="|", allow_unicode=True))
        f.close()
