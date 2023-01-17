package tech.stackable.t2.util;

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
 * Logs the content of a given {@link InputStream} into a given file.
 * 
 * This Logger reads the stream line by line and prepends it with a timestamp and a prefix which helps identify the
 * context of the logged line (e.g. step in the cluster creation)
 *
 * The Logger stops logging either when the stream has reached its end or when {@link #stop()} is called.
 */
public class ProgressLogger {

    private static final Logger LOGGER = LoggerFactory.getLogger(ProgressLogger.class);

    private static final DateTimeFormatter TIMESTAMP_FORMAT = DateTimeFormatter.ISO_INSTANT;

    /**
     * Has the stop of the logging been requested?
     */
    private boolean stopped = false;

    /**
     * Create a ProgressLogger and start logging immediately.
     * 
     * @param input   The input to be logged.
     * @param logfile The file to which the log output should be written.
     * @param prefix  Prefix for each line to provide context for the logged line.
     */
    private ProgressLogger(InputStream input, Path logfile, String prefix) {
        final BufferedReader reader = new BufferedReader(new InputStreamReader(input));
        new Thread(() -> {
            try (BufferedWriter bufferedWriter = new BufferedWriter(new FileWriter(logfile.toFile(), true)); PrintWriter printWriter = new PrintWriter(bufferedWriter)) {
                String line = reader.readLine();
                while (!stopped && line != null) {
                    printWriter.println(String.format("[%s][%s] %s", TIMESTAMP_FORMAT.format(Instant.now()), prefix, line));
                    printWriter.flush();
                    line = reader.readLine();
                }
            } catch (IOException ioe) {
                LOGGER.error("Error while writing process log to {}", logfile, ioe);
                throw new RuntimeException(String.format("Error while writing process log to %s", logfile), ioe);
            }

        }).start();
    }

    /**
     * Create a ProgressLogger and start logging immediately
     * 
     * @param input   The input to be logged.
     * @param logfile The file to which the log output should be written.
     * @param prefix  Prefix for each line to provide context for the logged line.
     * @return new ProgressLogger
     */
    public static ProgressLogger start(InputStream input, Path logfile, String prefix) {
        return new ProgressLogger(input, logfile, prefix);
    }

    /**
     * Stop logging.
     */
    public void stop() {
        this.stopped = true;
    }

}
