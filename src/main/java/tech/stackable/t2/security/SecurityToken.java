package tech.stackable.t2.security;

import java.io.IOException;
import java.nio.file.FileSystems;
import java.nio.file.Files;
import java.util.Objects;

import org.apache.commons.lang3.StringUtils;

public class SecurityToken {
  
  private String token;
  
  private SecurityToken(String token) {
    Objects.requireNonNull(token);
    if(StringUtils.isBlank(token)) {
      throw new IllegalArgumentException("SecurityToken must not be empty.");
    }
    this.token = token;
  }
  
  static SecurityToken fromFile(String file) throws IOException {
    return new SecurityToken(Files.readString(FileSystems.getDefault().getPath(file)));
  }
  
  static SecurityToken of(String token) {
    return new SecurityToken(token);
  }

  @Override
  public String toString() {
    return "SecurityToken (abbreviated): '" + StringUtils.abbreviate(this.token, 8) + "'";
  }

}
