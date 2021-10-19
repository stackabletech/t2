package tech.stackable.t2.security;

import java.io.IOException;
import java.io.StringReader;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Properties;

import org.apache.commons.lang3.StringUtils;
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

    @Bean(name = "credentials")
    public Properties credentials(@Value("${t2.security.credential-file:}") String credentialFile) {

        Path path = Path.of(credentialFile); 
        if(credentialFile.startsWith("~")) {
        	path = Path.of(StringUtils.replace(credentialFile, "~", System.getProperty("user.home"), 1));
        }
    	
        Properties credentials = new Properties();
        if (!Files.exists(path) || !Files.isRegularFile(path) || !Files.isReadable(path)) {
            LOGGER.info("No credentials read, as the path {} does not exist.", path);
            return credentials;
        }
        try {
            credentials.load(new StringReader(Files.readString(path)));
        } catch (IOException e) {
            LOGGER.error("No credentials read from path {} due to an error.", path, e);
        }

        LOGGER.info("Credentials read from {}.", path);
        
        return credentials;
    }

}
