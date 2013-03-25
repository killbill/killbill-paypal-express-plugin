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
end