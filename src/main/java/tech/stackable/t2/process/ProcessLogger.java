package tech.stackable.t2.process;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.FileWriter;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.PrintWriter;
import java.nio.file.Path;
import java.time.Instant;
import java.time.format.DateTimeFormatter;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Logs the given output stream of a process asynchronously into a given file.
 * Stops to do so either when the stream has reached its end or when the {@code #stop()} method is called.
 */
public class ProcessLogger {

  private static final Logger LOGGER = LoggerFactory.getLogger(ProcessLogger.class);
  
  private static final DateTimeFormatter TIMESTAMP_FORMAT = DateTimeFormatter.ISO_INSTANT;
 
  private boolean stopped = false;
  
  private ProcessLogger(InputStream in, Path logfile) {
    final BufferedReader reader = new BufferedReader(new InputStreamReader(in));
    new Thread(() -> {
      BufferedWriter bufferedWriter = null;
      PrintWriter printWriter = null;
      try {
        bufferedWriter = new BufferedWriter(new FileWriter(logfile.toFile(), true));
        printWriter = new PrintWriter(bufferedWriter);
        String line = reader.readLine();
        while (!stopped && line != null) {
          printWriter.println(String.format("[%s] %s", TIMESTAMP_FORMAT.format(Instant.now()), line));
          printWriter.flush();
          line = reader.readLine();
        }
      } catch (IOException ioe) {
        LOGGER.error("Error while writing process log to {}", logfile, ioe);
        throw new RuntimeException(String.format("Error while writing process log to %s", logfile), ioe);
      } finally {
        try {
          bufferedWriter.close();
        } catch (IOException ioe) {
          LOGGER.error("Error while closing writer to file {}", logfile, ioe);
        }
      }
      
    }).start();
  }

  public static ProcessLogger start(InputStream in, Path logfile) {
    return new ProcessLogger(in, logfile);
  }

  public void stop() {
    this.stopped = true;
  }

}
