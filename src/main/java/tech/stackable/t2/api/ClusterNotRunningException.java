package tech.stackable.t2.api;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.ResponseStatus;

@ResponseStatus(code = HttpStatus.CONFLICT)
public class ClusterNotRunningException extends RuntimeException {

    public ClusterNotRunningException(String msg) {
        super(msg);
    }

    public ClusterNotRunningException(String msg, Throwable t) {
        super(msg, t);
    }
}
