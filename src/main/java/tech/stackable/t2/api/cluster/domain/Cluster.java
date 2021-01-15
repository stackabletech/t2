package tech.stackable.t2.api.cluster.domain;

import java.time.LocalDateTime;
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

  public Cluster() {
    this(UUID.randomUUID());
  }

  public Cluster(UUID id) {
    this.id = id;
    this.status = Status.NEW;
    this.dateTimeCreated = LocalDateTime.now();
  }

  public UUID getId() {
    return id;
  }

  public Status getStatus() {
    return status;
  }

  public void setStatus(Status status) {
    this.status = status;
  }

  public LocalDateTime getDateTimeCreated() {
    return dateTimeCreated;
  }

  public void setDateTimeCreated(LocalDateTime dateTimeCreated) {
    this.dateTimeCreated = dateTimeCreated;
  }

  @Override
  public int hashCode() {
    final int prime = 31;
    int result = 1;
    result = prime * result + ((dateTimeCreated == null) ? 0 : dateTimeCreated.hashCode());
    result = prime * result + ((id == null) ? 0 : id.hashCode());
    result = prime * result + ((status == null) ? 0 : status.hashCode());
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
    if (dateTimeCreated == null) {
      if (other.dateTimeCreated != null)
        return false;
    } else if (!dateTimeCreated.equals(other.dateTimeCreated))
      return false;
    if (id == null) {
      if (other.id != null)
        return false;
    } else if (!id.equals(other.id))
      return false;
    if (status != other.status)
      return false;
    return true;
  }

  @Override
  public String toString() {
    return "Cluster [id=" + id + ", status=" + status + ", dateTimeCreated=" + dateTimeCreated + "]";
  }
}
