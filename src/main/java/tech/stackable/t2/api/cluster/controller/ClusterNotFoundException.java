package tech.stackable.t2.api.cluster.controller;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.ResponseStatus;

@ResponseStatus(code = HttpStatus.NOT_FOUND)
public class ClusterNotFoundException extends RuntimeException {

    private static final long serialVersionUID = 909084959090038711L;

    public ClusterNotFoundException(String message) {
        super(message);
    }
}
