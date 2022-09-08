package tech.stackable.t2.security;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class SecurityConfiguration {

    @Bean
	public SecurityToken securityToken(@Value("${t2.security.token}") String token) {
		return SecurityToken.of(token);
	}

}
