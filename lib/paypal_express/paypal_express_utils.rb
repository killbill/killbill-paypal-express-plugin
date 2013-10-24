require 'socket'

module Killbill::PaypalExpress
  class Utils
    def self.ip
      first_public_ipv4 ? first_public_ipv4.ip_address : first_private_ipv4.ip_address
    end

    def self.first_private_ipv4
      @@first_private_ipv4 ||= Socket.ip_address_list.detect{ |intf| intf.ipv4_private? }
    end

    def self.first_public_ipv4
      @@first_public_ipv4 ||= Socket.ip_address_list.detect{ |intf| intf.ipv4? and !intf.ipv4_loopback? and !intf.ipv4_multicast? and !intf.ipv4_private? }
    end
  end

  # Closest from a streaming API as we can get with ActiveRecord
  class StreamyResultSet
    include Enumerable

    def initialize(limit, batch_size = 100, &delegate)
      @limit = limit
      @batch = [batch_size, limit].min
      @delegate = delegate
    end

    def each(&block)
      (0..(@limit - @batch)).step(@batch) do |i|
        result = @delegate.call(i, @batch)
        block.call(result)
        # Optimization: bail out if no more results
        break if result.nil? || result.empty?
      end
      # Make sure to return DB connections to the Pool
      ActiveRecord::Base.connection.close
    end

    def to_a
      super.to_a.flatten
    end
  end
end
