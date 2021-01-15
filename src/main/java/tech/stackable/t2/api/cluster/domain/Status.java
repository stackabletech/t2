package tech.stackable.t2.api.cluster.domain;

import io.swagger.v3.oas.annotations.media.Schema;

/**
 * Status of a cluster
 */
@Schema(description = "Status of a Cluster")
public enum Status {

  NEW, STARTING, RUNNING, STOPPING, BROKEN, UNKNOWN;
}
