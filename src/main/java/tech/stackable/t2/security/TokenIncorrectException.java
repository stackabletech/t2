package tech.stackable.t2.security;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.ResponseStatus;

@SuppressWarnings("serial")
@ResponseStatus(code = HttpStatus.FORBIDDEN, reason = "The token you provided is not valid.")
public class TokenIncorrectException extends RuntimeException {
}
