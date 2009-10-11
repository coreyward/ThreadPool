class ThreadPool
  require 'thread'

  attr_reader :mutex , :threads , :thread_count
  attr_writer :debug

  def initialize num=1
    @thread_count=0
    @threads=[]
    @global_queue = Queue.new
    @mutex = Mutex.new
    self.increment(num)
  end

  def debug msg
    @mutex.synchronize do
      puts msg
    end
  end

  # Add threads to the pool

  def increment num=1
    num.times do
      @threads.push(
        Thread.new do
          loop do
            @global_queue.pop.call
          end
        end
      )
    end
    @thread_count+=num
  end

  # Remove threads from the pool

  def decrement num=1
    num=@thread_count if num>@thread_count
    num.times do
      debug "Dispatching termination command" if @debug
      self.dispatch do
        @threads.delete(Thread.current)
        debug "Deleting thread #{Thread.current}" if @debug
        Thread.current.exit
      end
    end
    @thread_count-=num
  end

  # The thread that calls this will block until
  # the threads in @threads have finished.
  # These threads will be terminated and the thread
  # pool emptied.

  def join
    threads=@threads.dup
      # Taking a copy here is really important!
    self.decrement @thread_count
      # Stop the threads or else suffer a deadlock.
    threads.each do |t|
      debug "joining thread #{t}" if @debug
      t.join
    end
  end

  # Dispatch jobs asynchronously.

  def dispatch func=nil , &block
    if block_given?
      @global_queue << func unless func.nil?
      @global_queue << block
    else
      raise "Must be called with a block." if func.nil?
      @global_queue << func
    end
  end

  # A Queue that contains its own thread and which
  # dispatches jobs synchronously.

  class SyncQueue < Queue

    def initialize
      @processing=false
      @stopping=false
      @running=false
      super
      start
    end

    # True if 'stop' has been called but we haven't
    # terminated yet.

    def stopping?
      @stopping
    end

    # True if the SyncQueue is no longer
    # running.  The thread for this queue is
    # not in the middle of processing anything.
    # The queue should be empty.
    # See #terminate .

    def stopped?
      !@running && !@stopping && !@processing
    end

    # Don't process any more jobs but
    # the current one; then stop the thread.
    # Remaining jobs are removed from the queue
    # and returned

    def terminate
      @running=false
      @stopping=false
      while self.size>0
        @left = self.pop
      end
      self << lambda{}
        # Pass a blank function to unblock
        # the thread so it can die.
      @left
    end

    # Stop the thread, but allow it to finish
    # processing the queue.
    # The queue goes into a special state
    # where it will throw an error if you try
    # to add to the queue.
    # The last job will terminate, allowing
    # the queue to be added to at a later time.
    # SyncQueue#stop is used by SyncQueue#join.

    def stop
      @stopping=true
      self << lambda{ self.terminate }
        # Pass a terminate function as final
        # function on queue.  Will unblock thread
        # if not doing anything.
    end

    # True if the SyncQueue instance is not terminated
    # or in a stopping state.

    def running?
      @running && !@stopping
    end

    # Fires up a new thread to process the queue.
    #
    # This method is automatically called when you
    # instantiate.
    #
    # Using it to restart an existing SyncQueue instance
    # has not been fully tested yet.  Currently, it
    # will call SyncQueue#join and go into a stopping
    # state before starting up a new thread.

    def start
      self.join if @running
      @running=true
      @thread = Thread.new do
        while @running
          block=self.pop
          @processing=true
          block.call
          @processing=false
        end
      end
    end

    # Dispatch jobs synchronously.

    def dispatch func=nil , &block
      if block_given?
        self << func unless func.nil?
        self << block
      else
        raise "Must be called with a block." if func.nil?
        self << func
      end
    end

    # Thread calling this will wait for @thread to
    # finish all queued jobs and terminate @thread.

    def join
      self.stop
        # Stop the thread or else suffer a deadlock.
      @thread.join
    end

    # Push blocks onto the queue.
    #
    # Raise an error if this queue is in a stopping
    # state caused by calling SyncQueue#stop.
    # Note that enq and << are aliases for 'push'.

    def push block
      if @stopping
        raise "This SyncQueue has been put into a stopping state using ThreadPool::SyncQueue#stop."
      end
      super
    end

  end

end
