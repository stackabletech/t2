package tech.stackable.t2.dns;

import java.io.IOException;
import java.io.UnsupportedEncodingException;
import java.text.MessageFormat;
import java.util.Properties;

import org.apache.http.HttpResponse;
import org.apache.http.client.HttpClient;
import org.apache.http.client.methods.HttpDelete;
import org.apache.http.client.methods.HttpPost;
import org.apache.http.entity.StringEntity;
import org.apache.http.impl.client.HttpClientBuilder;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

@Service
public class DnsService {

  private static final Logger LOGGER = LoggerFactory.getLogger(DnsService.class);  

  @Autowired
  @Qualifier("credentials")
  private Properties credentials;
  
  @Value("${t2.dns.cluster-domain}")
  private String domain;

  @Value("${t2.dns.livedns-api-url}")
  private String apiUrl;

  public String addSubdomain(String subdomain, String ipV4) {
    HttpClient client = HttpClientBuilder.create().build();
    HttpPost httpPost = new HttpPost(MessageFormat.format("{0}/domains/{1}/records", this.apiUrl, this.domain));
    httpPost.addHeader("Authorization", MessageFormat.format("Apikey {0}", credentials.getProperty("gandi_api_token")));
    String json = String.format("{\"rrset_values\": [ \"%s\" ],\"rrset_name\": \"%s\",\"rrset_type\": \"A\"}", ipV4, subdomain);
    StringEntity entity;
    try {
      entity = new StringEntity(json);
    } catch (UnsupportedEncodingException e1) {
      // TODO Auto-generated catch block
      e1.printStackTrace();
      return null;
    }
    httpPost.setEntity(entity);
    httpPost.setHeader("Content-type", "application/json");
    try {
      HttpResponse response = client.execute(httpPost);
      if(response.getStatusLine().getStatusCode()>=200 && response.getStatusLine().getStatusCode()<300) {
        return MessageFormat.format("{0}.stackable.tech", subdomain);
      }
      return null;
    } catch (IOException e) {
      LOGGER.error("DNS entry for {}.{} could not be created.", subdomain, this.domain, e);
      return null;
    }
  }

  public boolean removeSubdomain(String subdomain) {
    HttpClient client = HttpClientBuilder.create().build();
    HttpDelete httpDelete = new HttpDelete(MessageFormat.format("{0}/domains/{1}/records/{2}/A", this.apiUrl, this.domain, subdomain));
    httpDelete.addHeader("Authorization", MessageFormat.format("Apikey {0}", credentials.getProperty("gandi_api_token")));
    try {
      HttpResponse response = client.execute(httpDelete);
      return response.getStatusLine().getStatusCode()>=200 && response.getStatusLine().getStatusCode()<300;
    } catch (IOException e) {
      LOGGER.error("DNS entry for {}.{} could not be removed.", subdomain, this.domain, e);
      return false;
    }
  }

}
