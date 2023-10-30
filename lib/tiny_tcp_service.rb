require 'socket'

# usage:
#  s = TinyTCPService.new(
#    1234,
#    ->(m) { puts m }
#  )
#
#  s.start!     # everything runs in background threads
#  s.stop!      # gracefully shutdown the server
#
# NOTE: the msg_handler does not need to be a proc/lambda, it just needs to be
# an object that responds_to?(:call), and accepts a single message object.
# however, if your msg_handler is simple enough to fit into something as tiny as
# a proc then more power to you.
class TinyTCPService
  def initialize(port, msg_handler)
    @port = port
    @msg_handler = msg_handler

    @server = TCPServer.new(port)
    @clients = []
    @running = false
    @error_handlers = {}
  end

  # returns true if the server is running
  # false otherwise
  def running?
    @running
  end

  # add the error handler and block for the specified class
  #
  # you can assume that the local variable name of the error will be `e'
  def add_error_handler(klass, block)
    @error_handlers[klass] = block
  end

  # remove the error handler associated with klass
  def remove_error_handler(klass)
    @error_handlers.delete(klass)
  end

  # returns the number of connected clients
  def num_clients
    @clients.length
  end

  # starts the server
  def start!
    return if running?
    @running = true

    # client accept thread
    Thread.new do |t|
      loop do
        break unless running?
        @clients << @server.accept
      end

      @clients.each{|c| c.close if c && !c.closed? }
      @server.close
    end

    # service thread
    Thread.new do |t|
      loop do
        break unless running?

        readable, _, errored = IO.select(@clients, nil, @clients, 1)
        readable&.each do |client|
          begin
            @msg_handler.call(client.gets.chomp)
          rescue => e
            handler = @error_handlers[e.class]

            if handler
              handler.call(e)
            else
              stop!
              raise e unless handler
            end
          end
        end

        errored&.each do |client|
          @clients.delete(client)
          client.close if client && !client.closed?
        end
      end
    end
  end

  # stops the server gracefully
  def stop!
    @running = false
  end
end
