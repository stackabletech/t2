package tech.stackable.t2.api.cluster.domain;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.UUID;

import io.swagger.v3.oas.annotations.media.Schema;

/**
 * Stackable cluster metadata.
 */
@Schema(description = "Cluster")
public class Cluster {

  @Schema(description = "ID", required = true)
  private UUID id;

  @Schema(description = "Status", required = true)
  private Status status;

  @Schema(description = "Timestamp of cluster creation", required = true)
  private LocalDateTime dateTimeCreated;

  @Schema(description = "History of events in the cluster's lifecycle", required = false)
  private List<ClusterHistoryEvent> history;
  
  @Schema(description = "IP V4 address", required = false)
  private String ipV4Address;
  
  @Schema(description = "hostname", required = false)
  private String hostname;
  
  public Cluster() {
    this(UUID.randomUUID());
  }

  public Cluster(UUID id) {
    this.id = id;
    this.status = Status.NEW;
    this.dateTimeCreated = LocalDateTime.now();
    this.history = new ArrayList<>();
    this.history.add(new ClusterHistoryEvent(Status.NEW, null, this.dateTimeCreated));
  }

  public UUID getId() {
    return id;
  }

  public Status getStatus() {
    return status;
  }

  public void setStatus(Status status) {
    this.setStatus(status, null);
  }

  public void setStatus(Status status, String description) {
    this.status = status;
    synchronized (this.history) {
      this.history.add(new ClusterHistoryEvent(this.status, description, this.dateTimeCreated));
    }
  }

  public LocalDateTime getDateTimeCreated() {
    return dateTimeCreated;
  }

  public List<ClusterHistoryEvent> getHistory() {
    synchronized (this.history) {
      return Collections.unmodifiableList(this.history);
    }
  }

  public LocalDateTime getLastChangedAt() {
    if(this.history.isEmpty()) {
      return null;
    }
    synchronized(this.history) {
      return this.history.get(this.history.size()-1).getTimestamp();
    }
  }
  
  public String getIpV4Address() {
    return ipV4Address;
  }

  public void setIpV4Address(String ipV4Address) {
    this.ipV4Address = ipV4Address;
  }

  public String getHostname() {
    return hostname;
  }

  public void setHostname(String hostname) {
    this.hostname = hostname;
  }

  @Override
  public int hashCode() {
    final int prime = 31;
    int result = 1;
    result = prime * result + ((id == null) ? 0 : id.hashCode());
    return result;
  }

  @Override
  public boolean equals(Object obj) {
    if (this == obj)
      return true;
    if (obj == null)
      return false;
    if (getClass() != obj.getClass())
      return false;
    Cluster other = (Cluster) obj;
    if (id == null) {
      if (other.id != null)
        return false;
    } else if (!id.equals(other.id))
      return false;
    return true;
  }

  @Override
  public String toString() {
    return "Cluster [id=" + id + ", status=" + status + ", dateTimeCreated=" + dateTimeCreated + ", history=" + history + ", ipV4Address=" + ipV4Address + "]";
  }
}
