package tech.stackable.t2;

import org.apache.commons.lang3.StringUtils;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import io.swagger.v3.oas.models.Components;
import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Contact;
import io.swagger.v3.oas.models.info.Info;
import io.swagger.v3.oas.models.info.License;
import io.swagger.v3.oas.models.security.SecurityScheme;

/**
 * Spring Boot configuration for Swagger (REST API metadata/documentation).
 */
@Configuration
public class SwaggerUiConfig {

    private String versionInformation;

    SwaggerUiConfig(
            @Value("${t2.build.version}") String buildVersion,
            @Value("${t2.displayVersion}") String displayVersion) {
        if (StringUtils.isBlank(displayVersion)) {
            this.versionInformation = buildVersion;
        } else {
            this.versionInformation = String.format("%s (%s)", displayVersion, buildVersion);
        }
    }

    @Bean
    public OpenAPI customOpenAPI() {
        return new OpenAPI()
                .components(new Components()
                        .addSecuritySchemes("basicScheme", new SecurityScheme()
                                .type(SecurityScheme.Type.HTTP)
                                .scheme("basic")))
                .info(new Info()
                        .title("T2 REST API")
                        .version(this.versionInformation)
                        .contact(new Contact()
                                .name("Stackable GmbH")
                                .url("https://www.stackable.de")
                                .email("info@stackable.de"))
                        .license(new License()
                                .name("Apache License 2.0")
                                .url("http://www.apache.org/licenses/LICENSE-2.0")));
    }
}
