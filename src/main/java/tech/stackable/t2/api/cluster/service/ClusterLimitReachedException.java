package tech.stackable.t2.api.cluster.service;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.ResponseStatus;

@SuppressWarnings("serial")
@ResponseStatus(code = HttpStatus.CONFLICT, reason = "T2 has reached its limit of coexisting clusters.")
public class ClusterLimitReachedException extends RuntimeException {
}
