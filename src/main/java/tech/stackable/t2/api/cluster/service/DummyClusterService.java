package tech.stackable.t2.api.cluster.service;

import java.util.Collection;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Repository;

import tech.stackable.t2.api.cluster.domain.Cluster;
import tech.stackable.t2.api.cluster.domain.Status;

/**
 * Manages Dummy-Clusters.
 */
@Repository
@ConditionalOnProperty(name = "t2.feature.provision-real-clusters", havingValue = "false")
public class DummyClusterService implements ClusterService {
  
  private static final Logger LOGGER = LoggerFactory.getLogger(DummyClusterService.class);  

  private Map<UUID, Cluster> clusters = new HashMap<>();

  private int provisionClusterLimit = -1;  
  
  public DummyClusterService(@Value("${t2.feature.provision-cluster-limit}") int provisionClusterLimit) {
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
      new Thread(() -> {
        try {
          Thread.sleep(30000);
          cluster.setStatus(Status.RUNNING);
        } catch (InterruptedException e) {
          // we can live with that as of now
        }
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
      return clusters.remove(id);
    }
  }

}
