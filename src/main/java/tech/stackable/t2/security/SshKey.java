package tech.stackable.t2.security;

import static java.text.MessageFormat.format;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Objects;

/**
 * SSH Key to use by T2 when running Ansible and the like 
 */
public class SshKey {
  
  private Path privateKeyPath;
  
  private SshKey(Path privateKeyPath) {
    Objects.requireNonNull(privateKeyPath);
    this.privateKeyPath = privateKeyPath;
  }
  
  static SshKey of(Path privateKeyPath) {
    Objects.requireNonNull(privateKeyPath);
    if(!Files.exists(privateKeyPath) || !Files.isRegularFile(privateKeyPath)) {
      throw new IllegalStateException(format("No private key found: {0}.", privateKeyPath)) ;
    }
    SshKey sshKey = new SshKey(privateKeyPath);
    Path publicKey = sshKey.getPublicKeyPath();
    if(!Files.exists(publicKey) || !Files.isRegularFile(publicKey)) {
      throw new IllegalStateException(format("No public key found: {0}.", publicKey)) ;
    }
    return sshKey;
  }

  public Path getPublicKeyPath() {
    return this.privateKeyPath.getParent().resolve(format("{0}.pub", this.privateKeyPath.getFileName()));
  }

  public Path getPrivateKeyPath() {
    return this.privateKeyPath;
  }
}
