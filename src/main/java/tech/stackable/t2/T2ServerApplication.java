package tech.stackable.t2;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication
@EnableScheduling
public class T2ServerApplication {

    public static void main(String[] args) {
        SpringApplication.run(T2ServerApplication.class, args);
    }
}
