package tech.stackable.t2.security;

import java.io.IOException;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.BeanCreationException;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class SecurityConfiguration {

    private static final Logger LOGGER = LoggerFactory.getLogger(SecurityConfiguration.class);

    @Bean
    public SecurityToken securityToken(@Value("${t2.security.token-file}") String tokenFile) {

        LOGGER.info("Creating security token...");

        LOGGER.info("Read security token from disk...");
        try {
            SecurityToken securityToken = SecurityToken.fromFile(tokenFile);
            LOGGER.info("Created security token from file: [{}]", securityToken);
            return securityToken;
        } catch (IOException e) {
            LOGGER.error("Could not read security token from file '{}'", tokenFile, e);
            throw new BeanCreationException("Security token could not be created.");
        }
    }

}
