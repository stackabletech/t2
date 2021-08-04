import argparse
import yaml
import os
import requests
import time
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.backends import default_backend

CLUSTER_FOLDER = ".cluster/"
PRIVATE_KEY_FILE = f"{CLUSTER_FOLDER}key"
PUBLIC_KEY_FILE = f"{CLUSTER_FOLDER}key.pub"
TIMEOUT_SECONDS = 1800

def launch(args): 
    """Launch a cluster with the given command line args.
    
    The args are taken from the command line args parser and must contain:

    - t2_url: string - URL of T2 server
    - t2_token: string - secret token to access T2 server
    - cluster_definition_file: string - file which contains the cluster definition

    This function creates a folder .cluster/ where everything related to the cluster is stored.

    In the cluster definition, the 'publicKeys' section is extended with a generated public key. The according
    private key is used to access the cluster later.
    
    """

    os.mkdir(CLUSTER_FOLDER)
    os.system(f"ssh-keygen -f {PRIVATE_KEY_FILE} -q -N '' -C ''")
    with open (PUBLIC_KEY_FILE, "r") as f:
        public_key = f.read().strip()

    with open (args.cluster_definition_file, "r") as f:
        cluster_definition_string = f.read()
    cluster_definition_yaml = yaml.load(cluster_definition_string, Loader=yaml.FullLoader)

    if(not "publicKeys" in cluster_definition_yaml or not isinstance(cluster_definition_yaml["publicKeys"], list)):
        print("The cluster definition file does not contain a valid 'publicKeys' section.")
        exit(1)
    cluster_definition_yaml["publicKeys"].append(public_key)        
    with open (f"{CLUSTER_FOLDER}/cluster.yaml", "w") as f:
        f.write(yaml.dump(cluster_definition_yaml, default_flow_style=False))
        f.close()

    start_time = time.time()        
    cluster = create_cluster(args.t2_url, args.t2_token, yaml.dump(cluster_definition_yaml, default_flow_style=False))    
    if(not cluster):
        print("Failed to create cluster via API.")
        exit(1)

    print(f"Created cluster '{cluster['id']}'. Waiting for cluster to be up and running...")

    cluster = get_cluster(args.t2_url, args.t2_token, cluster['id'])
    while(TIMEOUT_SECONDS > (time.time()-start_time) and cluster['status']['state'] != 'RUNNING' and  not cluster['status']['failed']):
        time.sleep(5)
        cluster = get_cluster(args.t2_url, args.t2_token, cluster['id'])

    if(cluster['status']['failed']):
        print("Cluster launch failed.")
        exit(1)

    if(TIMEOUT_SECONDS <= (time.time()-start_time)):
        print("Timeout while launching cluster.")
        exit(1)

    print(f"Cluster '{cluster['id']}' is up and running.")

    with open(f"{CLUSTER_FOLDER}/ip", "w") as ip_text_file:
        print(cluster['ipV4Address'], file=ip_text_file)

    with open(f"{CLUSTER_FOLDER}/uuid", "w") as uuid_text_file:
        print(cluster['id'], file=uuid_text_file)

    print("Downloading Stackable client script for cluster")

    with open ("stackable.sh", "w") as f:
        f.write(get_client_script(args.t2_url, args.t2_token, cluster['id']))
        f.close()
    os.chmod("stackable.sh", 0o755)

    print("Downloading Stackable version information sheet for cluster")

    stackable_versions = get_version_information_sheet(args.t2_url, args.t2_token, cluster['id'])
    with open ("stackable-versions.txt", "w") as f:
        f.write(stackable_versions)
        f.close()
    print("")        
    print("Stackable version information sheet:")        
    print("------------------------------------------------------------------------------------")        
    print(stackable_versions)
    print("------------------------------------------------------------------------------------")        
    print("")        
    print("")        



def terminate(args):
    """Terminates the cluster identified by the data in the .cluster/ folder.
    
    The args are taken from the command line args parser and must contain:

    - t2_url: string - URL of T2 server
    - t2_token: string - secret token to access T2 server
    """
    with open (f"{CLUSTER_FOLDER}/uuid", "r") as f:
        uuid = f.read().strip()

    start_time = time.time()        
    cluster = delete_cluster(args.t2_url, args.t2_token, uuid)    
    if(not cluster):
        print("Failed to create cluster via API.")
        exit(1)

    print(f"Started termination of cluster '{cluster['id']}'. Waiting for cluster to be terminated...")
    cluster = get_cluster(args.t2_url, args.t2_token, cluster['id'])
    while(TIMEOUT_SECONDS > (time.time()-start_time) and cluster['status']['state'] != 'TERMINATED' and  not cluster['status']['failed']):
        time.sleep(5)
        cluster = get_cluster(args.t2_url, args.t2_token, cluster['id'])

    if(cluster['status']['failed']):
        print("Cluster termination failed.")
        exit(1)

    if(TIMEOUT_SECONDS <= (time.time()-start_time)):
        print("Timeout while launching cluster.")
        exit(1)

    print(f"Cluster '{cluster['id']}' is terminated.")


def create_cluster(t2_url, t2_token, cluster_definition):
    """Create a cluster using T2 REST API

    Returns:
    - JSON representing cluster (REST response)
    """
    response = requests.post(f"{t2_url}/api/clusters", data=cluster_definition, headers={ "t2-token": t2_token, "Content-Type": "application/yaml" })
    if(response.status_code != 200):
        print(f"API call to create cluster returned error code {response}")
        return None
    return response.json()


def get_cluster(t2_url, t2_token, id):
    """Get the cluster information using T2 REST API

    Returns:
    - JSON representing cluster (REST response)
    """
    response = requests.get(f"{t2_url}/api/clusters/{id}", headers={ "t2-token": t2_token })
    if(response.status_code != 200):
        print(f"API call to get cluster returned error code {response.status_code}")
        return None
    return response.json()


def delete_cluster(t2_url, t2_token, id):
    """Delete the cluster using T2 REST API

    Returns:
    - JSON representing terminated cluster (REST response)
    """
    response = requests.delete(f"{t2_url}/api/clusters/{id}", headers={ "t2-token": t2_token })
    if(response.status_code != 200):
        print(f"API call to delete cluster returned error code {response.status_code}")
        return None
    return response.json()


def get_client_script(t2_url, t2_token, id):
    """Downloads the Stackable client script using T2 REST API

    Returns:
    - JSON representing terminated cluster (REST response)
    """
    response = requests.get(f"{t2_url}/api/clusters/{id}/stackable-client-script", headers={ "t2-token": t2_token })
    if(response.status_code != 200):
        print(f"API call to get Stackable client script returned error code {response.status_code}")
        return None
    return response.text

def get_version_information_sheet(t2_url, t2_token, id):
    """Downloads the Stackable version information sheet using T2 REST API

    Returns:
    - JSON representing terminated cluster (REST response)
    """
    response = requests.get(f"{t2_url}/api/clusters/{id}/stackable-versions", headers={ "t2-token": t2_token })
    if(response.status_code != 200):
        print(f"API call to get Stackable version information sheet returned error code {response.status_code}")
        return "No Stackable version information available."
    return response.text

if __name__ == "__main__":

    # CLI argument parser
    argparser = argparse.ArgumentParser(description='Launch or terminate a Stackable cluster using the T2 API.')
    subparsers = argparser.add_subparsers(required=True)

    # command 'launch'
    launch_parser = subparsers.add_parser('launch')
    launch_parser.add_argument('t2_token', metavar='T2_TOKEN', type=str, help='the token to access T2')
    launch_parser.add_argument('t2_url', metavar='T2_URL', type=str, help='the base URL of T2')
    launch_parser.add_argument('cluster_definition_file', metavar='CLUSTER_DEFINITION_FILE', type=str, help='YAML file which contains the cluster definition')
    launch_parser.set_defaults(func=launch)

    # command 'terminate'
    terminate_parser = subparsers.add_parser('terminate')
    terminate_parser.add_argument('t2_token', metavar='T2_TOKEN', type=str, help='the token to access T2')
    terminate_parser.add_argument('t2_url', metavar='T2_URL', type=str, help='the base URL of T2')
    terminate_parser.set_defaults(func=terminate)

    # parse args
    args = argparser.parse_args()

    # call function matching command
    args.func(args)
