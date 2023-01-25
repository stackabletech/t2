package tech.stackable.t2.api;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.ResponseStatus;

@ResponseStatus(code = HttpStatus.BAD_REQUEST)
public class MalformedClusterDefinitionException extends RuntimeException {

    public MalformedClusterDefinitionException(String msg) {
        super(msg);
    }

    public MalformedClusterDefinitionException(String msg, Throwable t) {
        super(msg, t);
    }
}
