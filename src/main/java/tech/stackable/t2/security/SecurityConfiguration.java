package tech.stackable.t2.security;

import java.io.IOException;

import org.apache.commons.lang3.ArrayUtils;
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
  
  private static final String TOKEN_SOURCE_FILE = "file";
  private static final String TOKEN_SOURCE_STATIC = "static";

  @Bean
  public SecurityToken securityToken(
      @Value("${t2.security.token.source}") String tokenSource,
      @Value("${t2.security.token.static}") String staticToken,
      @Value("${t2.security.token.file}") String tokenFile) {

    LOGGER.info("Creating security token...");

    if(StringUtils.isBlank(tokenSource) || !ArrayUtils.contains(new String[]{ TOKEN_SOURCE_FILE, TOKEN_SOURCE_STATIC}, tokenSource)) {
      throw new BeanCreationException("t2.security.token.source must be one of: ( static | file ).");
    }
    
    if(TOKEN_SOURCE_STATIC.equals(tokenSource)) {
      LOGGER.info("Using static security token.");
      if(StringUtils.isBlank(staticToken)) {
        throw new BeanCreationException("t2.security.token.static must not be empty.");
      }
      SecurityToken securityToken = SecurityToken.of(staticToken);
      LOGGER.info("Created static security token: [{}]", securityToken);
      return securityToken;
    }
    
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
