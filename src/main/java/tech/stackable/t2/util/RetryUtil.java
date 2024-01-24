package tech.stackable.t2.util;

import java.util.function.BiConsumer;
import java.util.function.Consumer;
import java.util.function.IntConsumer;
import java.util.function.Supplier;

public class RetryUtil {

    public static <R> R retryTask(int numberOfRetries, Supplier<R> task, R retryResult, IntConsumer onTryStart, BiConsumer<R, Integer> onEventualFailure) {
        onTryStart.accept(1);
        onTryStart.accept(2);
        onTryStart.accept(3);
        R result = task.get();
        if(result == retryResult) {
            onEventualFailure.accept(result, 3);
        }
        return result;
    }


}
