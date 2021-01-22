package tech.stackable.t2.security;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.ResponseStatus;

@SuppressWarnings("serial")
@ResponseStatus(code = HttpStatus.UNAUTHORIZED, reason = "You need a token to perform this action.")
public class TokenRequiredException extends RuntimeException {
}
