import os
import os.path
import datetime
import time
import sys
import yaml
import requests
import re

CLUSTER_FOLDER = ".cluster/"
PRIVATE_KEY_FILE = f"{CLUSTER_FOLDER}key"
PUBLIC_KEY_FILE = f"{CLUSTER_FOLDER}key.pub"
TIMEOUT_SECONDS = 1800

def prerequisites():
    if not 'T2_TOKEN' in os.environ:
        print("Error: Please supply T2_TOKEN as an environment variable.")
        exit(1)
    if not 'T2_URL' in os.environ:
        print("Error: Please supply T2_URL as an environment variable.")
        exit(1)
    if not os.path.isfile("/cluster.yaml"):
        print("Error Please supply cluster definition as file in /cluster.yaml.")
        exit(1)
         
def init_log():
    """ Inits (=clears) the log file """
    os.system('rm -rf /target/testdriver.log || true')
    os.system('touch /target/testdriver.log')
    os.system(f"chown {uid_gid_output} /target/testdriver.log")
    os.system('chmod 664 /target/testdriver.log')

def log(msg=""):
    """ Logs the given text message to stdout AND the logfile """
    print(msg)
    sys.stdout.flush()
    f = open("/target/testdriver.log", "a")
    f.write('{:%Y-%m-%d %H:%M:%S.%s} :: '.format(datetime.datetime.now()))
    f.write(f"{msg}\n")
    f.close()    

def is_dry_run():
    return 'DRY_RUN' in os.environ and os.environ['DRY_RUN']=='true'

def run_test_script():
    if os.path.isfile("/test.sh"):
        os.system('rm -rf /target/test_output.log || true')
        os.system('touch /target/test_output.log')
        os.system(f"chown {uid_gid_output} /target/test_output.log")
        os.system('chmod 664 /target/test_output.log')
        os.system('/test.sh 2>&1 | tee /target/test_output.log')
    else:
        log("No test script supplied.")

def launch(): 
    """Launch a cluster.
    
    This function creates a folder .cluster/ where everything related to the cluster is stored.

    In the cluster definition, the 'publicKeys' section is extended with a generated public key. The according
    private key is used to access the cluster later.
    
    """

    os.mkdir(CLUSTER_FOLDER)
    os.system(f"ssh-keygen -f {PRIVATE_KEY_FILE} -q -N '' -C ''")
    with open (PUBLIC_KEY_FILE, "r") as f:
        public_key = f.read().strip()

    with open ("/cluster.yaml", "r") as f:
        cluster_definition_string = f.read()
    cluster_definition_yaml = yaml.load(cluster_definition_string, Loader=yaml.FullLoader)

    if(not "publicKeys" in cluster_definition_yaml or not isinstance(cluster_definition_yaml["publicKeys"], list)):
        log("Error: The cluster definition file does not contain a valid 'publicKeys' section.")
        exit(1)
    cluster_definition_yaml["publicKeys"].append(public_key)        
    with open (f"{CLUSTER_FOLDER}/cluster.yaml", "w") as f:
        f.write(yaml.dump(cluster_definition_yaml, default_flow_style=False))
        f.close()

    start_time = time.time()        
    cluster = create_cluster(os.environ["T2_URL"], os.environ["T2_TOKEN"], yaml.dump(cluster_definition_yaml, default_flow_style=False))    
    if(not cluster):
        log("Error: Failed to create cluster via API.")
        exit(1)

    log(f"Created cluster '{cluster['id']}'. Waiting for cluster to be up and running...")

    cluster = get_cluster(os.environ["T2_URL"], os.environ["T2_TOKEN"], cluster['id'])
    while(TIMEOUT_SECONDS > (time.time()-start_time) and cluster['status']['state'] != 'RUNNING' and  not cluster['status']['failed']):
        time.sleep(5)
        cluster = get_cluster(os.environ["T2_URL"], os.environ["T2_TOKEN"], cluster['id'])

    if(cluster['status']['failed']):
        log("Cluster launch failed.")
        exit(1)

    if(TIMEOUT_SECONDS <= (time.time()-start_time)):
        log("Timeout while launching cluster.")
        exit(1)

    log(f"Cluster '{cluster['id']}' is up and running.")

    with open(f"{CLUSTER_FOLDER}/uuid", "w") as uuid_text_file:
        print(cluster['id'], file=uuid_text_file)

    log("Downloading Stackable client script for cluster")

    with open ("/stackable.sh", "w") as f:
        f.write(get_client_script(os.environ["T2_URL"], os.environ["T2_TOKEN"], cluster['id']))
        f.close()
    os.chmod("/stackable.sh", 0o755)

    log("Downloading Stackable kubeconfig")

    with open ("/kubeconfig", "w") as f:
        f.write(get_kubeconfig(os.environ["T2_URL"], os.environ["T2_TOKEN"], cluster['id']))
        f.close()

    log("Downloading Stackable version information sheet for cluster")

    stackable_versions = get_version_information_sheet(os.environ["T2_URL"], os.environ["T2_TOKEN"], cluster['id'])
    with open ("/target/stackable-versions.txt", "w") as f:
        f.write(stackable_versions)
        f.close()
    os.system(f"chown {uid_gid_output} /target/stackable-versions.txt")
    os.system('chmod 664 /target/stackable-versions.txt')


def terminate():
    """Terminates the cluster identified by the data in the .cluster/ folder.
    """
    with open (f"{CLUSTER_FOLDER}/uuid", "r") as f:
        uuid = f.read().strip()

    start_time = time.time()        
    cluster = delete_cluster(os.environ["T2_URL"], os.environ["T2_TOKEN"], uuid)    
    if(not cluster):
        log("Failed to create cluster via API.")
        exit(1)

    log(f"Started termination of cluster '{cluster['id']}'. Waiting for cluster to be terminated...")
    cluster = get_cluster(os.environ["T2_URL"], os.environ["T2_TOKEN"], cluster['id'])
    while(TIMEOUT_SECONDS > (time.time()-start_time) and cluster['status']['state'] != 'TERMINATED' and  not cluster['status']['failed']):
        time.sleep(5)
        cluster = get_cluster(os.environ["T2_URL"], os.environ["T2_TOKEN"], cluster['id'])

    if(cluster['status']['failed']):
        log("Cluster termination failed.")
        exit(1)

    if(TIMEOUT_SECONDS <= (time.time()-start_time)):
        log("Timeout while launching cluster.")
        exit(1)

    log(f"Cluster '{cluster['id']}' is terminated.")


def create_cluster(t2_url, t2_token, cluster_definition):
    """Create a cluster using T2 REST API

    Returns:
    - JSON representing cluster (REST response)
    """
    response = requests.post(f"{t2_url}/api/clusters", data=cluster_definition, headers={ "t2-token": t2_token, "Content-Type": "application/yaml" })
    if(response.status_code != 200):
        log(f"API call to create cluster returned error code {response}")
        return None
    return response.json()


def get_cluster(t2_url, t2_token, id):
    """Get the cluster information using T2 REST API

    Returns:
    - JSON representing cluster (REST response)
    """
    response = requests.get(f"{t2_url}/api/clusters/{id}", headers={ "t2-token": t2_token })
    if(response.status_code != 200):
        log(f"API call to get cluster returned error code {response.status_code}")
        return None
    return response.json()


def delete_cluster(t2_url, t2_token, id):
    """Delete the cluster using T2 REST API

    Returns:
    - JSON representing terminated cluster (REST response)
    """
    response = requests.delete(f"{t2_url}/api/clusters/{id}", headers={ "t2-token": t2_token })
    if(response.status_code != 200):
        log(f"API call to delete cluster returned error code {response.status_code}")
        return None
    return response.json()


def get_client_script(t2_url, t2_token, id):
    """Downloads the Stackable client script using T2 REST API

    Returns:
    - content of the Stackable client script
    """
    response = requests.get(f"{t2_url}/api/clusters/{id}/stackable-client-script", headers={ "t2-token": t2_token })
    if(response.status_code != 200):
        log(f"API call to get Stackable client script returned error code {response.status_code}")
        return None
    return response.text

def get_version_information_sheet(t2_url, t2_token, id):
    """Downloads the Stackable version information sheet using T2 REST API

    Returns:
    - content of the Stackable version information sheet
    """
    response = requests.get(f"{t2_url}/api/clusters/{id}/stackable-versions", headers={ "t2-token": t2_token })
    if(response.status_code != 200):
        log(f"API call to get Stackable version information sheet returned error code {response.status_code}")
        return "No Stackable version information available."
    return response.text

def get_kubeconfig(t2_url, t2_token, id):
    """Downloads the kubeconfig using T2 REST API

    Returns:
    - content of the Stackable kubeconfig
    """
    response = requests.get(f"{t2_url}/api/clusters/{id}/kubeconfig", headers={ "t2-token": t2_token })
    if(response.status_code != 200):
        log(f"API call to get Stackable kubeconfig returned error code {response.status_code}")
        return None
    return response.text

def create_kubeconfig_for_ssh_tunnel(kubeconfig_file, kubeconfig_target_file):
    """
        Creates a kubeconfig in which the Server URL is modified to use a locally set up SSH tunnel. (using 127.0.0.1 as an address)

        Returns a tuple consisting of: 
            - the original IP/Servername of the K8s API
            - the original Port of the K8s API
    """
    with open (kubeconfig_file, "r") as f:
        kubeconfig = yaml.load(f.read(), Loader=yaml.FullLoader)

    original_server_address = kubeconfig["clusters"][0]["cluster"]["server"]

    address_pattern = re.compile('https://([^:]*):([0-9]+)')

    match = address_pattern.match(original_server_address)

    if not match:
        print('Error: No API address found in kubeconfig')
        exit(1)

    original_api_hostname = match.group(1)
    original_api_port = match.group(2)

    kubeconfig["clusters"][0]["cluster"]["server"] = f"https://127.0.0.1:{original_api_port}"

    with open (kubeconfig_target_file, "w") as f:
        f.write(yaml.dump(kubeconfig, default_flow_style=False))
        f.close()

    return (original_api_hostname, original_api_port)        

def establish_ssh_tunnel_to_api(api_port):
    os.system(f"/stackable.sh -i {PRIVATE_KEY_FILE} api-tunnel {api_port}")


if __name__ == "__main__":

    prerequisites()

    uid_gid_output = "0:0"
    if 'UID_GID' in os.environ:
        uid_gid_output = os.environ['UID_GID']

    init_log()

    log("Starting T2 test driver...")

    dry_run = is_dry_run()

    if dry_run:
        log('WARNING: This is a DRY RUN only!')
        exit(0)

    log(f"Creating a cluster using T2 at {os.environ['T2_URL']}...")
    launch()
    (_, api_port) = create_kubeconfig_for_ssh_tunnel("/kubeconfig", "/root/.kube/config")
    establish_ssh_tunnel_to_api(api_port)
    log("Running test script...")
    run_test_script()
    log("Test script finished.")
    log(f"Terminating the test cluster...")
    terminate()
    log("T2 test driver finished.")