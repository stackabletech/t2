package tech.stackable.t2.api.cluster.service;

import java.util.Collection;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Repository;

import tech.stackable.t2.api.cluster.domain.Cluster;

/**
 * Manages 'real' clusters provisioned with Terraform and Ansible
 */
@Repository
@ConditionalOnProperty(name = "t2.feature.provision-real-clusters", havingValue = "true")
public class TerraformAnsibleClusterService implements ClusterService {
  
  private static final Logger LOGGER = LoggerFactory.getLogger(TerraformAnsibleClusterService.class);  

  private int provisionClusterLimit = -1;  
  
  public TerraformAnsibleClusterService(@Value("${t2.feature.provision-cluster-limit}") int provisionClusterLimit) {
    this.provisionClusterLimit = provisionClusterLimit;
    LOGGER.info("ClusterService cluster number limit: {}", this.provisionClusterLimit);
  }

  @Override
  public Cluster createCluster() {
    throw new UnsupportedOperationException("wip");
  }

  @Override
  public Collection<Cluster> getAllClusters() {
    throw new UnsupportedOperationException("wip");
  }

  @Override
  public Cluster getCluster(UUID id) {
    throw new UnsupportedOperationException("wip");
  }

  @Override
  public void deleteCluster(UUID id) {
    throw new UnsupportedOperationException("wip");
  }

}
