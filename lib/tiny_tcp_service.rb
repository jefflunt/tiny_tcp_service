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
# TinyTCPService implements a line-based, call and response protocol, where
# every incoming message must be a newline-terminated ("\n") String, and for
# every received message the service responds with a newline-terminated String.
# been set).
#
# If you need more complex objects to be sent over the wire, consider something
# like JSON.
#
# NOTE: if you're running a TinyTCPService and a client of your system violates
# your communication protocol, you should raise an instance of
# TinyTCPService::BadClient, and the TinyTCPService instance will take care of
# safely removing the client.
class TinyTCPService
  def initialize(port)
    @port = port

    @server = TCPServer.new(port)
    @clients = []
    @running = false

    @msg_handler = nil
    @error_handlers = {}
  end

  # h - some object that responds to #call
  def msg_handler=(h)
    @msg_handler = h
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

  def _remove_client!(c)
    @clients.delete(c)
    c.close if c && !c.closed?
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

      @clients.each{|c| _remove_client!(c) if c && !c.closed? }
      @server.close
    end

    # service thread
    Thread.new do |t|
      loop do
        break unless running?

        readable, _, errored = IO.select(@clients, nil, @clients, 1)
        readable&.each do |c|
          begin
            c.puts(@msg_handler&.call(c.gets.chomp))
          rescue TinyTCPService::BadClient => e
            _remove_client!(c)
          rescue => e
            handler = @error_handlers[e.class]

            if handler
              handler.call(e)
            else
              stop!
              raise e
            end
          end
        end

        errored&.each do |c|
          _remove_client!(c)
        end
      end
    end
  end

  # stops the server gracefully
  def stop!
    @running = false
  end
end

class TinyTCPService::BadClient < RuntimeError; end
