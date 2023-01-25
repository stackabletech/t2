package tech.stackable.t2.security;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.ResponseStatus;

@ResponseStatus(code = HttpStatus.FORBIDDEN, reason = "The token you provided does not allow you to perform this operation.")
public class TokenIncorrectException extends RuntimeException {
}
