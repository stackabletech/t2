import yaml

def read_aws_credentials():
    with open ("aws_credentials.yaml", "r") as f:
        return yaml.load(f.read(), Loader=yaml.FullLoader)

README_TXT_TEMPLATE = """#  This file describes how to access a T2 Kubernetes cluster which runs on AWS EKS
#
#  The Kubernetes cluster was created together with an individual admin account which can access the cluster.
#
#  Please configure your AWS CLI to use this admin account:
#
#      aws configure set aws_access_key_id {aws_access_key}
#      aws configure set aws_secret_access_key {aws_secret_access_key}
#      aws configure set region {region}
#
#  Warning! Make sure not to overwrite your existing AWS CLI account settings.
#  If you need help creating profiles, please refer to the AWS CLI help:
#  https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-profiles.html
#
#  After you successfully logged in using the AWS CLI, you have to create a kubeconfig file to access the cluster.
#  This command creates the config for you:
#
#      aws eks update-kubeconfig --name {cluster_name} --region {region}
#
#  If you already have a config at the default location (most probably ~/.kube/config), the command will merge the new
#  config into the existing one as a so called context. To specify a different location, you can use the --kubeconfig
#  param.
#
#  Please refer to the AWS CLI help for details:
#  https://docs.aws.amazon.com/eks/latest/userguide/create-kubeconfig.html
#
#  To be machine-processable, this file also contains...
#
#  - ...a script 'access.sh' to execute all the aforementioned commands in one go (under .access_script)
#  - ...the information you will need if you want to use a different way to access the cluster (under .data.<key>)
#
"""

ACCESS_SCRIPT_TEMPLATE = """#!/bin/bash
aws configure set aws_access_key_id {aws_access_key}
aws configure set aws_secret_access_key {aws_secret_access_key}
aws configure set region {region}
aws eks update-kubeconfig --name {cluster_name} --region {region}
"""

if __name__ == "__main__":

    aws_credentials = read_aws_credentials()

    access_script = ACCESS_SCRIPT_TEMPLATE.format(**aws_credentials)
    readme_txt = README_TXT_TEMPLATE.format(**aws_credentials)

    access_yaml = { 'access_script': access_script, 'data': aws_credentials }

    with open ("resources/access.yaml", "w") as f:
        f.write(readme_txt)
        f.write("---\n")
        f.write(yaml.safe_dump(access_yaml , default_flow_style=False, default_style="|", allow_unicode=True))
        f.close()
