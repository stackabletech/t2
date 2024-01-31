package tech.stackable.t2.util;

import java.util.function.BiConsumer;
import java.util.function.IntConsumer;
import java.util.function.Supplier;

/**
 * Allows the (re)try of tasks.
 */
public class RetryUtil {

    /**
     * Try the given task for a maximum given number of times.
     * 
     * If the task is successful, this method returns its return value, otherwise it returns <code>null</code>.
     * 
     * @param <R> Type of the task's result
     * @param numberOfTries total try count
     * @param intervalSeconds Waiting interval between tries (seconds)
     * @param task Task to be executed/retried
     * @param retryResult Value of the result which should lead to a retry
     * @param onTryStart Callback on start of a (re)try
     * @param onEventualFailure Callback on eventual failure after last try
     * @return If the task is successful, this method returns its return value, otherwise it returns <code>null</code>.
     */
    public static <R> R retryTask(int numberOfTries, int intervalSeconds, Supplier<R> task, R retryResult, IntConsumer onTryStart, BiConsumer<R, Integer> onEventualFailure) {

        // retry count
        int i = 1;

        // result of task
        R result = null;

        while(i++ <= numberOfTries) {

            // notify about try # i
            onTryStart.accept(i);

            // run task for i-th time
            result = task.get();

            // If we get the result which should lead to a retry ...
            if(result == retryResult) {

                // Was this the last try? => Notify caller
                if(i == numberOfTries) {
                    onEventualFailure.accept(result, i);
                    return null;
                }

                // Any try but the last try? => Sleep for the designated time
                try {
                    Thread.sleep(intervalSeconds * 1_000);
                } catch (InterruptedException e) {
                    // If interrupted, we just return null in lack of other reasonable things to do...
                    return null;
                }

                // Next try...
                continue;
            }

            // Task was successful
            break;

        }        

        return result;
    }

}
