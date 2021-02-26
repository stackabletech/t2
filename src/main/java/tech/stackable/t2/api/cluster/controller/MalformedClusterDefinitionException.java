package tech.stackable.t2.api.cluster.controller;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.ResponseStatus;

@ResponseStatus(code = HttpStatus.BAD_REQUEST)
public class MalformedClusterDefinitionException extends RuntimeException {

  private static final long serialVersionUID = -5279165502248464802L;

  public MalformedClusterDefinitionException(String msg) {
    super(msg);
  }

  public MalformedClusterDefinitionException(String msg, Throwable t) {
    super(msg, t);
  }
}
