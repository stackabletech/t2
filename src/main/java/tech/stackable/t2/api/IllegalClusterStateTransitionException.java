package tech.stackable.t2.api;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.ResponseStatus;

@ResponseStatus(code = HttpStatus.CONFLICT)
public class IllegalClusterStateTransitionException extends RuntimeException {

    public IllegalClusterStateTransitionException(String msg) {
        super(msg);
    }

    public IllegalClusterStateTransitionException(String msg, Throwable t) {
        super(msg, t);
    }
}
