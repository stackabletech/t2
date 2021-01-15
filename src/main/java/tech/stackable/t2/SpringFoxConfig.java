package tech.stackable.t2;

import java.util.Collections;
import java.util.function.Predicate;

import org.apache.commons.lang3.StringUtils;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import springfox.documentation.builders.RequestHandlerSelectors;
import springfox.documentation.service.ApiInfo;
import springfox.documentation.service.Contact;
import springfox.documentation.spi.DocumentationType;
import springfox.documentation.spring.web.plugins.Docket;

@Configuration
public class SpringFoxConfig {
  
  private final static String[] PATHS = { "/api/", "/actuator/" };
  
  private final static Predicate<String> PATH_SELECTOR = path -> {
    return StringUtils.startsWithAny(path, PATHS);
  };
  
  @Value("${t2.build.version}")
  private String version;
  
  @Value("${t2.build.git-commit}")
  private String gitCommit;
  
  @Bean
  public Docket apiDocs() {
    return new Docket(DocumentationType.SWAGGER_2)
        .select()
        .apis(RequestHandlerSelectors.any())
        .paths(PATH_SELECTOR)
        .build()
        .apiInfo(apiInfo());
  }
  
  // TODO Could we use Annotations for this as well? see https://github.com/swagger-api/swagger-core/wiki/Swagger-2.X---Annotations
  private ApiInfo apiInfo() {
    return new ApiInfo(
      "Stackable T2 REST API", 
      "REST API of Stackable's T2 service (integration test and troubleshooting)",
      String.format("%s (%s)", version, gitCommit),
      null, 
      new Contact("Stackable", "http://www.stackable.de", "info@stackable.de"), 
      "Apache License 2.0", "http://www.apache.org/licenses/LICENSE-2.0", Collections.emptyList());
}  
  
}
