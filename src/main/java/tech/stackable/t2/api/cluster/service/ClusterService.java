package tech.stackable.t2.api.cluster.service;

import java.util.Collection;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

import org.springframework.stereotype.Repository;

import tech.stackable.t2.api.cluster.domain.Cluster;
import tech.stackable.t2.api.cluster.domain.Status;

/**
 * Service that manages clusters.
 */
@Repository
public class ClusterService {

  private Map<UUID, Cluster> clusters = new HashMap<>();

  /**
   * Creates a new cluster
   * 
   * As of now, this is just a dummy cluster which is starting for 30 secs and then up and running...
   * 
   * @return new cluster
   */
  public Cluster createCluster() {
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

  /**
   * Gets all clusters
   * 
   * @return all clusters
   */
  public Collection<Cluster> getAllClusters() {
    return this.clusters.values();
  }

  /**
   * Gets cluster.
   * 
   * @param id ID of the requested cluster
   * @return cluster information, <code>null</code> if cluster does not exist.
   */
  public Cluster getCluster(UUID id) {
    return this.clusters.get(id);
  }

  /**
   * Remove cluster.
   * 
   * @param id ID of cluster to remove
   */
  public void deleteCluster(UUID id) {
    clusters.remove(id);
  }

}
