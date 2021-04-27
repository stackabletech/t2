import argparse
import yaml
import os
import requests
import time
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.backends import default_backend

CLUSTER_FOLDER = ".cluster"
TIMEOUT_SECONDS = 1800

def launch(args): 

    os.mkdir(CLUSTER_FOLDER)
    PUBLIC_KEY, _ = generate_ssh_keypair()

    cluster_definition_yaml = yaml.load(read_cluster_definition(args.cluster_definition_file[0]), Loader=yaml.FullLoader)
    if(not "publicKeys" in cluster_definition_yaml or not isinstance(cluster_definition_yaml["publicKeys"], list)):
        print("The cluster definition file does not contain a valid 'publicKeys' section.")
        exit(1)
    cluster_definition_yaml["publicKeys"].append(PUBLIC_KEY)        
    with open (f"{CLUSTER_FOLDER}/cluster.yaml", "w") as f:
        f.write(yaml.dump(cluster_definition_yaml, default_flow_style=False))
        f.close()
    start_time = time.time()        
    cluster = create_cluster(args.t2_url[0], args.t2_token[0], yaml.dump(cluster_definition_yaml, default_flow_style=False))    
    if(not cluster):
        print("Failed to create cluster via API.")
        exit(1)

    print(f"Created cluster '{cluster['id']}'. Waiting for cluster to be up and running...")
    cluster = update_cluster(args.t2_url[0], args.t2_token[0], cluster)
    while(TIMEOUT_SECONDS > (time.time()-start_time) and cluster['status']['state'] != 'RUNNING' and  not cluster['status']['failed']):
        time.sleep(5)
        cluster = update_cluster(args.t2_url[0], args.t2_token[0], cluster)

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


def terminate(args):
    with open (f"{CLUSTER_FOLDER}/uuid", "r") as f:
        uuid = f.read().strip()

    start_time = time.time()        
    cluster = delete_cluster(args.t2_url[0], args.t2_token[0], uuid)    
    if(not cluster):
        print("Failed to create cluster via API.")
        exit(1)

    print(f"Started termination of cluster '{cluster['id']}'. Waiting for cluster to be terminated...")
    cluster = update_cluster(args.t2_url[0], args.t2_token[0], cluster)
    while(TIMEOUT_SECONDS > (time.time()-start_time) and cluster['status']['state'] != 'TERMINATED' and  not cluster['status']['failed']):
        time.sleep(5)
        cluster = update_cluster(args.t2_url[0], args.t2_token[0], cluster)

    if(cluster['status']['failed']):
        print("Cluster termination failed.")
        exit(1)

    if(TIMEOUT_SECONDS <= (time.time()-start_time)):
        print("Timeout while launching cluster.")
        exit(1)

    print(f"Cluster '{cluster['id']}' is terminated.")


def read_cluster_definition(cluster_definition_file): 
    with open (cluster_definition_file, "r") as f:
        return f.read()

def generate_ssh_keypair():
    key = rsa.generate_private_key(backend=default_backend(), public_exponent=65537, key_size=2048)
    public_key = key.public_key().public_bytes(serialization.Encoding.OpenSSH, serialization.PublicFormat.OpenSSH)
    pem = key.private_bytes(encoding=serialization.Encoding.PEM, format=serialization.PrivateFormat.TraditionalOpenSSL, encryption_algorithm=serialization.NoEncryption())
    with open (f"{CLUSTER_FOLDER}/id.pub", "w") as f:
        f.write(public_key.decode('utf-8'))
        f.close()
    with open (f"{CLUSTER_FOLDER}/id", "w") as f:
        f.write(pem.decode('utf-8'))
        f.close()
    return public_key.decode('utf-8'), pem.decode('utf-8')

def create_cluster(t2_url, t2_token, cluster_definition):
    response = requests.post(f"{t2_url}/api/clusters", data=cluster_definition, headers={ "t2-token": t2_token, "Content-Type": "application/yaml" })
    if(response.status_code != 200):
        print(f"API call to create cluster returned error code {response}")
        return None
    return response.json()

def get_cluster(t2_url, t2_token, id):
    response = requests.get(f"{t2_url}/api/clusters/{id}", headers={ "t2-token": t2_token })
    if(response.status_code != 200):
        print(f"API call to get cluster returned error code {response.status_code}")
        return None
    return response.json()

def update_cluster(t2_url, t2_token, cluster):
    updated_cluster = get_cluster(t2_url, t2_token, cluster['id'])
    if(not updated_cluster):
        return cluster
    return updated_cluster

def delete_cluster(t2_url, t2_token, id):
    response = requests.delete(f"{t2_url}/api/clusters/{id}", headers={ "t2-token": t2_token })
    if(response.status_code != 200):
        print(f"API call to delete cluster returned error code {response.status_code}");
        return None
    return response.json()

argparser = argparse.ArgumentParser(description='Launch or terminate a Stackable cluster using the T2 API.')
subparsers = argparser.add_subparsers(required=True)

launch_parser = subparsers.add_parser('launch')
launch_parser.add_argument('t2_token', metavar='T2_TOKEN', type=str, nargs=1, help='the token to access T2')
launch_parser.add_argument('t2_url', metavar='T2_URL', type=str, nargs=1, help='the base URL of T2')
launch_parser.add_argument('cluster_definition_file', metavar='CLUSTER_DEFINITION_FILE', type=str, nargs=1, help='YAML file which contains the cluster definition')
launch_parser.set_defaults(func=launch)

terminate_parser = subparsers.add_parser('terminate')
terminate_parser.add_argument('t2_token', metavar='T2_TOKEN', type=str, nargs=1, help='the token to access T2')
terminate_parser.add_argument('t2_url', metavar='T2_URL', type=str, nargs=1, help='the base URL of T2')
terminate_parser.set_defaults(func=terminate)

args = argparser.parse_args()

args.func(args)
