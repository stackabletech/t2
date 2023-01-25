package tech.stackable.t2.security;

import java.util.Objects;

import org.apache.commons.lang3.StringUtils;

/**
 * T2 security token.
 *
 * To use T2, you have to provide a valid token.
 */
public class SecurityToken {

    private String token;

    private SecurityToken(String token) {
        Objects.requireNonNull(token);
        if (StringUtils.isBlank(token)) {
            throw new IllegalArgumentException("SecurityToken must not be empty.");
        }
        this.token = StringUtils.trim(token);
    }

    static SecurityToken of(String token) {
        return new SecurityToken(token);
    }

    public boolean isOk(String token) {
        return this.token.equals(token);
    }

    @Override
    public String toString() {
        return "SecurityToken (abbreviated): '" + StringUtils.abbreviate(this.token, 8) + "'";
    }

}
