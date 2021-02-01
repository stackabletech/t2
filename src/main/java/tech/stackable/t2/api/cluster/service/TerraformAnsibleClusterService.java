package tech.stackable.t2.api.cluster.service;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.file.Files;
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
import org.springframework.core.io.Resource;
import org.springframework.core.io.ResourceLoader;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Repository;

import tech.stackable.t2.api.cluster.domain.Cluster;
import tech.stackable.t2.api.cluster.domain.Status;
import tech.stackable.t2.terraform.TerraformResult;
import tech.stackable.t2.terraform.TerraformRunner;

/**
 * Manages clusters provisioned with Terraform and Ansible
 */
@Repository
@ConditionalOnProperty(name = "t2.feature.provision-real-clusters", havingValue = "true")
public class TerraformAnsibleClusterService implements ClusterService {
  
  private static final Duration CLEANUP_INACTIVITY_THRESHOLD = Duration.ofDays(1);
  
  private static final Logger LOGGER = LoggerFactory.getLogger(TerraformAnsibleClusterService.class);  

  @Autowired
  @Qualifier("workspaceDirectory")
  private Path workspaceDirectory;
  
  @Autowired
  @Qualifier("credentials")
  private Properties credentials;
  
  @Autowired
  ResourceLoader resourceLoader;  
  
  private int provisionClusterLimit = -1;  
  
  /**
   * cluster metadata per cluster (UUID)
   */
  private Map<UUID, Cluster> clusters = new HashMap<>();
  
  /**
   * Terraform file per cluster (UUID)
   */
  private Map<UUID, Path> terraformFiles = new HashMap<>();

  public TerraformAnsibleClusterService(@Value("${t2.feature.provision-cluster-limit}") int provisionClusterLimit) {
    this.provisionClusterLimit = provisionClusterLimit;
    LOGGER.info("ClusterService cluster number limit: {}", this.provisionClusterLimit);
  }

  @Override
  public Cluster createCluster() {
    synchronized(this.clusters) {
      if(clusters.size()>=this.provisionClusterLimit) {
        throw new ClusterLimitReachedException();
      }
      Cluster cluster = new Cluster();
      clusters.put(cluster.getId(), cluster);
      cluster.setStatus(Status.CREATION_STARTED);
      
      new Thread(() -> {
        TerraformRunner runner = TerraformRunner.create(terraformFile(cluster.getId()), datacenterName(cluster.getId()), credentials);
        TerraformResult result;
        
        cluster.setStatus(Status.TERRAFORM_INIT);
        result = runner.init();
        if(result==TerraformResult.ERROR) {
          cluster.setStatus(Status.TERRAFORM_INIT_FAILED);
          return;
        }
        
        cluster.setStatus(Status.TERRAFORM_PLAN);
        result = runner.plan();
        if(result==TerraformResult.ERROR) {
          cluster.setStatus(Status.TERRAFORM_PLAN_FAILED);
          return;
        }
        
        cluster.setStatus(Status.TERRAFORM_APPLY);
        runner.apply();
        if(result==TerraformResult.ERROR) {
          cluster.setStatus(Status.TERRAFORM_APPLY_FAILED);
          return;
        }

        cluster.setStatus(Status.RUNNING);
        
      }).start();
      
      return cluster;
    }
  }

  @Override
  public Collection<Cluster> getAllClusters() {
    return this.clusters.values();
  }

  @Override
  public Cluster getCluster(UUID id) {
    return this.clusters.get(id);
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
        TerraformRunner runner = TerraformRunner.create(terraformFile(cluster.getId()), datacenterName(cluster.getId()), credentials);
        cluster.setStatus(Status.TERRAFORM_DESTROY);
        TerraformResult result = runner.destroy();
        if(result==TerraformResult.ERROR) {
          cluster.setStatus(Status.TERRAFORM_DESTROY_FAILED);
          return;
        }
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
   * Gets the Terraform file for the given cluster, creates it if necessary
   * @param clusterId Cluster ID
   * @return Terraform file for the given cluster
   */
  private Path terraformFile(UUID clusterId) {
    Path terraformFile = terraformFiles.get(clusterId);
    if(terraformFile==null) {
      terraformFile = createTerraformFile(clusterId);
      terraformFiles.put(clusterId, terraformFile);
    }
    return terraformFile;
  }
  
  /**
   * Creates a Terraform file for the given cluster and returns the corresponding Path object.
   * @param clusterId Cluster ID
   * @return Path of the Terraform file for the given cluster
   */
  private Path createTerraformFile(UUID clusterId) {
    Path terraformFile = workspaceDirectory.resolve(clusterId.toString()).resolve("terraform").resolve("cluster.tf");
    try {
      Files.createDirectories(terraformFile.getParent());
      Resource terraformFileTemplate = this.resourceLoader.getResource("classpath:templates/terraform/cluster.tf");
      BufferedReader templateReader = new BufferedReader(new InputStreamReader(terraformFileTemplate.getInputStream()));
      String contents = templateReader.lines().collect(Collectors.joining(System.lineSeparator()));
      Files.writeString(terraformFile, contents);
    } catch (IOException ioe) {
      LOGGER.error("Terraform directory for cluster {} could not be created.", clusterId, ioe);
      throw new RuntimeException(String.format("Terraform directory for cluster %s could not be created.", clusterId));
    }
    return terraformFile;
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
