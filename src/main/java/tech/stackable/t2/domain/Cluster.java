package tech.stackable.t2.domain;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.UUID;

import org.apache.commons.lang3.StringUtils;

import io.swagger.v3.oas.annotations.media.Schema;

@Schema(description = "Cluster")
public class Cluster {

    @Schema(description = "ID", required = true)
    private UUID id;

    @Schema(description = "Status", required = true)
    private Status status;

    @Schema(description = "Timestamp of cluster creation", required = true)
    private LocalDateTime dateTimeCreated;

    @Schema(description = "Events in the cluster's lifecycle", required = false)
    private List<ClusterEvent> events;

    public Cluster() {
        this(UUID.randomUUID());
    }

    public Cluster(UUID id) {
        this.id = id;
        this.status = Status.NEW;
        this.dateTimeCreated = LocalDateTime.now();
        this.events = new ArrayList<>();
        this.events.add(new ClusterEvent("Cluster creation started.", this.dateTimeCreated));
    }

    public UUID getId() {
        return id;
    }

    public String getShortId() {
        return StringUtils.substring(this.id.toString(), 0, 8);
    }

    public Status getStatus() {
        return status;
    }

    public void setStatus(Status status) {
        this.status = status;
    }

    public void addEvent(String description) {
        synchronized (this.events) {
            this.events.add(new ClusterEvent(description, this.dateTimeCreated));
        }
    }

    public LocalDateTime getDateTimeCreated() {
        return dateTimeCreated;
    }

    public List<ClusterEvent> getEvents() {
        synchronized (this.events) {
            return Collections.unmodifiableList(this.events);
        }
    }

    public LocalDateTime getLastChangedAt() {
        if (this.events.isEmpty()) {
            return null;
        }
        synchronized (this.events) {
            return this.events.get(this.events.size() - 1).getTimestamp();
        }
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
        return "Cluster [id=" + id + ", status=" + status + ", dateTimeCreated=" + dateTimeCreated + ", events=" + events + "]";
    }
}
