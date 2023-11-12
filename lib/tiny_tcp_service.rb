require 'socket'

# usage:
#  s = TinyTCPService.new(
#    1234,
#    ->(m) { puts m }
#  )
#
#  s.stop!      # gracefully shutdown the server
#
# TinyTCPService implements a line-based, call and response protocol, where
# every incoming message must be a newline-terminated ("\n") String, and for
# every received message the service responds with a newline-terminated String.
#
# You can use this to send more complex objects, such as minified JSON, so long
# as your JSON's content doesn't also contain newlines.
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
    @running = true

    @msg_handler = nil
    @error_handlers = {}

    # client accept thread
    @thread = Thread.new do |t|
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
            m = c.gets&.chomp

            if m.is_a?(String)
              c.puts(@msg_handler&.call(m))
            else
              _remove_client!(c)
            end
          rescue TinyTCPService::BadClient, Errno::ECONNRESET => e
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

  # join the service Thread if you want to wait until it's closed
  def join
    @thread.join
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

  # stops the server gracefully
  def stop!
    @running = false
  end
end

class TinyTCPService::BadClient < RuntimeError; end
