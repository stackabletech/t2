package tech.stackable.t2.api.cluster.service;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Collection;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.core.io.ResourceLoader;
import org.springframework.stereotype.Repository;

import tech.stackable.t2.api.cluster.domain.Cluster;
import tech.stackable.t2.terraform.TerraformRunner;

/**
 * Manages 'real' clusters provisioned with Terraform and Ansible
 */
@Repository
@ConditionalOnProperty(name = "t2.feature.provision-real-clusters", havingValue = "true")
public class TerraformAnsibleClusterService implements ClusterService {
  
  private static final Logger LOGGER = LoggerFactory.getLogger(TerraformAnsibleClusterService.class);  

  @Autowired
  @Qualifier("workspaceDirectory")
  private Path workspaceDirectory;
  
  @Autowired
  ResourceLoader resourceLoader;  
  
  private int provisionClusterLimit = -1;  
  
  private Map<UUID, Cluster> clusters = new HashMap<>();

  public TerraformAnsibleClusterService(@Value("${t2.feature.provision-cluster-limit}") int provisionClusterLimit) {
    this.provisionClusterLimit = provisionClusterLimit;
    LOGGER.info("ClusterService cluster number limit: {}", this.provisionClusterLimit);
  }

  @Override
  public Cluster createCluster() {
    // TODO set state
    synchronized(this.clusters) {
      if(clusters.size()>=this.provisionClusterLimit) {
        throw new ClusterLimitReachedException();
      }
      Cluster cluster = new Cluster();
      clusters.put(cluster.getId(), cluster);
      
      try {
        Files.createDirectory(workspaceDirectory.resolve(cluster.getId().toString()));
      } catch (IOException ioe) {
        LOGGER.error("Workspace directory for cluster {} could not be created.", cluster.getId(), ioe);
        throw new RuntimeException(String.format("Workspace directory for cluster %s could not be created.", cluster.getId()));
      }

      try {
        Files.createDirectory(workspaceDirectory.resolve(cluster.getId().toString()).resolve("terraform"));
        Files.copy(this.resourceLoader.getResource("classpath:templates/terraform/cluster.tf").getFile().toPath(), workspaceDirectory.resolve(cluster.getId().toString()).resolve("terraform").resolve("cluster.tf"));
      } catch (IOException ioe) {
        LOGGER.error("Terraform directory for cluster {} could not be created.", cluster.getId(), ioe);
        throw new RuntimeException(String.format("Terraform directory for cluster %s could not be created.", cluster.getId()));
      }
      
      new Thread(() -> {
        TerraformRunner runner = TerraformRunner.create(workspaceDirectory.resolve(cluster.getId().toString()).resolve("terraform").resolve("cluster.tf"), String.format("t2-%s", cluster.getId()));
        runner.init();
        runner.plan();
        runner.apply();
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
  public void deleteCluster(UUID id) {
    // TODO set state
    synchronized(this.clusters) {
      Cluster cluster = this.clusters.get(id);
      if(cluster==null) {
        return;
      }
      
      // TODO check if dir exists etc.
      
      new Thread(() -> {
        TerraformRunner runner = TerraformRunner.create(workspaceDirectory.resolve(cluster.getId().toString()).resolve("terraform").resolve("cluster.tf"), String.format("t2-%s", cluster.getId()));
        runner.destroy();
      }).start();
      
      this.clusters.remove(id);
    }
  }

}
