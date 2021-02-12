package tech.stackable.t2.api.cluster.service;

import java.nio.file.Path;
import java.time.Duration;
import java.time.LocalDateTime;
import java.util.Collection;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Properties;
import java.util.UUID;
import java.util.stream.Collectors;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Repository;

import tech.stackable.t2.ansible.AnsibleResult;
import tech.stackable.t2.ansible.AnsibleService;
import tech.stackable.t2.api.cluster.domain.Cluster;
import tech.stackable.t2.api.cluster.domain.Status;
import tech.stackable.t2.dns.DnsService;
import tech.stackable.t2.terraform.TerraformResult;
import tech.stackable.t2.terraform.TerraformService;

/**
 * Manages clusters provisioned with Terraform and Ansible
 */
@Repository
@ConditionalOnProperty(name = "t2.feature.provision-real-clusters", havingValue = "true")
public class TerraformAnsibleClusterService implements ClusterService {
  
  private static final Logger LOGGER = LoggerFactory.getLogger(TerraformAnsibleClusterService.class);  
  
  private static final Duration CLEANUP_INACTIVITY_THRESHOLD = Duration.ofDays(1);
  
  @Autowired
  @Qualifier("workspaceDirectory")
  private Path workspaceDirectory;
  
  @Autowired
  @Qualifier("credentials")
  private Properties credentials;
  
  @Autowired
  private DnsService dnsService; 
  
  @Autowired
  private TerraformService terraformService; 
  
  @Autowired
  private AnsibleService ansibleService; 
  
  private int provisionClusterLimit = -1;  
  
  /**
   * cluster metadata per cluster (UUID)
   */
  private Map<UUID, Cluster> clusters = new HashMap<>();
  
  public TerraformAnsibleClusterService(@Value("${t2.feature.provision-cluster-limit}") int provisionClusterLimit) {
    this.provisionClusterLimit = provisionClusterLimit;
    LOGGER.info("Created TerraformAnsibleClusterService, cluster count limit: {}", this.provisionClusterLimit);
  }

  @Override
  public Collection<Cluster> getAllClusters() {
    return this.clusters.values();
  }

  @Override
  public Cluster getCluster(UUID id) {
    return this.clusters.get(id);
  }

  // TODO The SSH key is ignored, we're working on a sophisticated mechanism: https://github.com/stackabletech/t2/issues/9
  @Override
  public Cluster createCluster(String sshPublicKey) {
    synchronized(this.clusters) {
      
      // TODO count only active clusters for limit
      if(clusters.size()>=this.provisionClusterLimit) {
        throw new ClusterLimitReachedException();
      }
      Cluster cluster = new Cluster();
      clusters.put(cluster.getId(), cluster);
      cluster.setStatus(Status.CREATION_STARTED);
      
      new Thread(() -> {
        
        TerraformResult terraformResult = null;
        
        Path terraformFolder = this.terraformService.terraformFolder(cluster);
        
        cluster.setStatus(Status.TERRAFORM_INIT);
        terraformResult = this.terraformService.init(terraformFolder, datacenterName(cluster.getId()));
        if(terraformResult==TerraformResult.ERROR) {
          cluster.setStatus(Status.TERRAFORM_INIT_FAILED);
          return;
        }
        
        cluster.setStatus(Status.TERRAFORM_PLAN);
        terraformResult = this.terraformService.plan(terraformFolder, datacenterName(cluster.getId()));
        if(terraformResult==TerraformResult.ERROR) {
          cluster.setStatus(Status.TERRAFORM_PLAN_FAILED);
          return;
        }
        
        cluster.setStatus(Status.TERRAFORM_APPLY);
        terraformResult = this.terraformService.apply(terraformFolder, datacenterName(cluster.getId()));
        if(terraformResult==TerraformResult.ERROR) {
          cluster.setStatus(Status.TERRAFORM_APPLY_FAILED);
          return;
        }
        
        cluster.setIpV4Address(this.terraformService.getIpV4(terraformFolder));

        cluster.setStatus(Status.DNS_WRITE_RECORD);
        String hostname = this.dnsService.addSubdomain(cluster.getShortId(), cluster.getIpV4Address());
        if(hostname==null) {
          cluster.setStatus(Status.DNS_WRITE_RECORD_FAILED);
          return;
        }
        
        cluster.setHostname(hostname);

        cluster.setStatus(Status.ANSIBLE_PROVISIONING);

        // TODO use kind of a retry mechanism instead of waiting stupidly
        try {
          Thread.sleep(60_000);
        } catch (InterruptedException e) {
          e.printStackTrace();
        }
        
        Path ansibleFolder = this.ansibleService.ansibleFolder(cluster);

        AnsibleResult ansibleResult = this.ansibleService.run(ansibleFolder);
        if(ansibleResult==AnsibleResult.ERROR) {
          cluster.setStatus(Status.ANSIBLE_FAILED);
          return;
        }
        
        cluster.setStatus(Status.RUNNING);
        
      }).start();
      
      return cluster;
    }
  }

  @Override
  public Cluster deleteCluster(UUID id) {
    synchronized(this.clusters) {
      Cluster cluster = this.clusters.get(id);
      if(cluster==null) {
        return null;
      }
      cluster.setStatus(Status.DELETION_STARTED);
      
      new Thread(() -> {
        
        cluster.setStatus(Status.DNS_DELETE_RECORD);
        boolean dnsRemovalSucceded = this.dnsService.removeSubdomain(cluster.getShortId());
        if(!dnsRemovalSucceded) {
          cluster.setStatus(Status.DNS_DELETE_RECORD_FAILED);
          return;
        }

        Path terraformFolder = this.terraformService.terraformFolder(cluster);
        
        cluster.setStatus(Status.TERRAFORM_DESTROY);
        TerraformResult terraformResult = this.terraformService.destroy(terraformFolder, datacenterName(cluster.getId()));
        if(terraformResult==TerraformResult.ERROR) {
          cluster.setStatus(Status.TERRAFORM_DESTROY_FAILED);
          return;
        }
        cluster.setIpV4Address(null);
        cluster.setStatus(Status.TERMINATED);
      }).start();
      
      return cluster;
    }
  }

  /**
   * Cleans up list of clusters regularly.
   */
  @Scheduled(cron="0 0 * * * *") // on the hour
  private void cleanup() {
    LOGGER.info("cleaning up clusters ...");
    List<UUID> clustersToDelete = this.clusters.values()
      .stream()
      .filter(TerraformAnsibleClusterService::readyForCleanup)
      .map(Cluster::getId)
      .collect(Collectors.toList());

    synchronized (clusters) {
      clustersToDelete.forEach(id -> {
        LOGGER.info("Cluster {} will be cleaned up.", id);
        this.clusters.remove(id);
      });
    }
    
    LOGGER.info("cleaned up {} clusters.", clustersToDelete.size());
  }

  /**
   * Decides if a given Cluster is ready to be cleaned up.
   * 
   * We assume that clusters that are not in state {@link Status#RUNNING} and haven't changed their state for a day are ready to be removed.
   * 
   * @param cluster cluster to check
   * @return Is the given cluster ready to be cleaned up?
   */
  private static boolean readyForCleanup(Cluster cluster) {
    return !(cluster.getStatus()==Status.RUNNING)
        && Duration.between(cluster.getLastChangedAt(), LocalDateTime.now()).compareTo(CLEANUP_INACTIVITY_THRESHOLD) > 0;
  }
  
  /**
   * Datacenter name for the given cluster
   * @param clusterId Cluster ID
   * @return datacenter name for the given cluster
   */
  private String datacenterName(UUID clusterId) {
    return String.format("t2-%s", clusterId);
  }
  
}
