package tech.stackable.t2.api.cluster.service;

import java.util.Collection;
import java.util.UUID;

import tech.stackable.t2.api.cluster.domain.Cluster;

public interface ClusterService {

  /**
   * Creates a new cluster
   * 
   * @return new cluster
   */
  Cluster createCluster(String sshPublicKey);

  /**
   * Gets all clusters
   * 
   * @return all clusters
   */
  Collection<Cluster> getAllClusters();

  /**
   * Gets cluster.
   * 
   * @param id ID of the requested cluster
   * @return cluster information, <code>null</code> if cluster does not exist.
   */
  Cluster getCluster(UUID id);

  /**
   * Remove cluster.
   * 
   * @param id ID of cluster to remove
   */
  Cluster deleteCluster(UUID id);

}
