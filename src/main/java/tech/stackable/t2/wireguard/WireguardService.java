package tech.stackable.t2.wireguard;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.text.MessageFormat;

import org.apache.commons.io.IOUtils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

@Service
public class WireguardService {

    private static final Logger LOGGER = LoggerFactory.getLogger(WireguardService.class);

    public String generatePrivateKey() {
        try {
            Process process = new ProcessBuilder().command("sh", "-c", "wg genkey").redirectErrorStream(true).start();
            int exitCode = process.waitFor();
            if (exitCode != 0) {
                throw new RuntimeException(MessageFormat.format("Error while calling wireguard keygen, return code {0}", exitCode));
            }
            return IOUtils.toString(process.getInputStream(), StandardCharsets.UTF_8.name()).trim();
        } catch (IOException | InterruptedException e) {
            LOGGER.error("Error while calling wireguard keygen", e);
            throw new RuntimeException("Error while calling wireguard keygen", e);
        }
    }

    public String generatePublicKey(String privateKey) {
        try {
            Process process = new ProcessBuilder().command("sh", "-c", "echo \"" + privateKey + "\" | wg pubkey").redirectErrorStream(true).start();
            int exitCode = process.waitFor();
            if (exitCode != 0) {
                throw new RuntimeException(MessageFormat.format("Error while calling wireguard pubkey, return code {0}", exitCode));
            }
            return IOUtils.toString(process.getInputStream(), StandardCharsets.UTF_8.name()).trim();
        } catch (IOException | InterruptedException e) {
            LOGGER.error("Error while calling wireguard pubkey", e);
            throw new RuntimeException("Error while calling wireguard pubkey", e);
        }
    }

}
