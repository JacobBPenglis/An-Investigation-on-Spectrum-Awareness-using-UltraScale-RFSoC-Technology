import numpy as np
import numpy.typing as npt
import threading
import time

class WindowedCircularBuffer:
    def __init__(self, size: int, window_size: int):
        # Buffer size constraints
        self.size = size
        self.window_size = window_size

        # Buffer with mirrored first window and required monitoring variables
        self.buffer = np.zeros(self.size + self.window_size, dtype=np.complex64)
        self.head = 0
        self.tail = 0
        self.count = 0
        self.condition = threading.Condition()
        self.active = True
        self.draining = False

        # Timing statistics
        self.start_time = time.perf_counter()
        self.down_time = 0

    def push_samples(self, samples: npt.NDArray) -> None:
        # Get the size of the block to be written to the buffer
        n = len(samples)

        with self.condition:
            # Check if the new block will overwrite unprocessed data.
            # If so, let the buffer drain before continuing
            if self.count + n > self.size:
                start_draining = time.perf_counter()
                print("Buffer draining")
                while self.draining:
                    self.condition.wait()
                down_time = time.perf_counter() - start_draining
                self.down_time += down_time
                print(f"Buffer inactive for {down_time/1e3:.2f}ms")
                return

            # No wrap around
            new_head = self.head + n
            if new_head < self.size:
                self.buffer[self.head:new_head] = samples

            # Wrap around
            else:
                new_head -= self.size
                split = self.size - self.head
                self.buffer[self.head:self.size] = samples[:split]
                self.buffer[:new_head] = samples[split:]

            if self.head < self.window_size or new_head < self.window_size or new_head < self.head:
                self.update_mirror()

            # Update head and count to reflect the newly inserted data
            self.head = new_head
            self.count += n

            # Notify the consumer that data is available
            self.condition.notify_all()

    def update_mirror(self) -> None:
        self.buffer[self.size:] = self.buffer[:self.window_size]

    def peek_window(self) -> npt.NDArray:
        with self.condition:
            while self.count < self.window_size and self.active:
                self.condition.wait()
            return self.buffer[int(self.tail):int(self.tail + self.window_size)]
    
    def pop_window(self, step: int) -> None:
        # Enforce a reasonable range for step
        if step <= 0 or step > self.window_size:
            raise ValueError("Step must be in the range (0, window_size]")
        
        with self.condition:
            # Check if there is enough data to mark the step as consumed
            if self.count < step:
                raise ValueError("Not enough data available")
            
            # Consume window
            self.tail += step
            if self.tail >= self.size:
                self.tail -= self.size
            self.count -= step

            # Wake producer if done draining the buffer
            if self.draining and self.count < self.window_size:
                self.condition.notify_all()

    def close(self) -> None:
        with self.condition:
            self.active = False
            self.display_timing_stats()
            self.condition.notify_all()

    def is_active(self) -> bool:
        with self.condition:
            return self.active

    def display_timing_stats(self) -> None:
        total_time = time.perf_counter() - self.start_time
        print(f"Buffer active for {(1 - self.down_time/total_time)*100:.2f}% of the {total_time/60:.2f} minutes it was open")