require 'active_record'
require 'activemerchant'
require 'pathname'
require 'sinatra'
require 'singleton'
require 'yaml'

require 'killbill'
require 'killbill/response/payment_method_response'
require 'killbill/response/payment_response'
require 'killbill/response/refund_response'

require 'paypal_express/config/configuration'
require 'paypal_express/config/properties'

require 'paypal_express/paypal/gateway'

require 'paypal_express/models/paypal_express_payment_method'
require 'paypal_express/models/paypal_express_response'
require 'paypal_express/models/paypal_express_transaction'

require 'paypal_express/paypal_express_utils'

require 'paypal_express/api'
require 'paypal_express/private_api'


# Thank you Rails for the following!

class Object
  def blank?
    respond_to?(:empty?) ? empty? : !self
  end
end

class Hash
  # By default, only instances of Hash itself are extractable.
  # Subclasses of Hash may implement this method and return
  # true to declare themselves as extractable. If a Hash
  # is extractable, Array#extract_options! pops it from
  # the Array when it is the last element of the Array.
  def extractable_options?
    instance_of?(Hash)
  end
end

class Array
  # Extracts options from a set of arguments. Removes and returns the last
  # element in the array if it's a hash, otherwise returns a blank hash.
  #
  #   def options(*args)
  #     args.extract_options!
  #   end
  #
  #   options(1, 2)        # => {}
  #   options(1, 2, a: :b) # => {:a=>:b}
  def extract_options!
    if last.is_a?(Hash) && last.extractable_options?
      pop
    else
      {}
    end
  end
end

class Module
  def mattr_reader(*syms)
    options = syms.extract_options!
    syms.each do |sym|
      raise NameError.new('invalid attribute name') unless sym =~ /^[_A-Za-z]\w*$/
      class_eval(<<-EOS, __FILE__, __LINE__ + 1)
        @@#{sym} = nil unless defined? @@#{sym}

        def self.#{sym}
          @@#{sym}
        end
      EOS

      unless options[:instance_reader] == false || options[:instance_accessor] == false
        class_eval(<<-EOS, __FILE__, __LINE__ + 1)
          def #{sym}
            @@#{sym}
          end
        EOS
      end
    end
  end

  def mattr_writer(*syms)
    options = syms.extract_options!
    syms.each do |sym|
      raise NameError.new('invalid attribute name') unless sym =~ /^[_A-Za-z]\w*$/
      class_eval(<<-EOS, __FILE__, __LINE__ + 1)
        def self.#{sym}=(obj)
          @@#{sym} = obj
        end
      EOS

      unless options[:instance_writer] == false || options[:instance_accessor] == false
        class_eval(<<-EOS, __FILE__, __LINE__ + 1)
          def #{sym}=(obj)
            @@#{sym} = obj
          end
        EOS
      end
    end
  end

  # Extends the module object with module and instance accessors for class attributes,
  # just like the native attr* accessors for instance attributes.
  #
  #   module AppConfiguration
  #     mattr_accessor :google_api_key
  #
  #     self.google_api_key = "123456789"
  #   end
  #
  #   AppConfiguration.google_api_key # => "123456789"
  #   AppConfiguration.google_api_key = "overriding the api key!"
  #   AppConfiguration.google_api_key # => "overriding the api key!"
  #
  # To opt out of the instance writer method, pass <tt>instance_writer: false</tt>.
  # To opt out of the instance reader method, pass <tt>instance_reader: false</tt>.
  # To opt out of both instance methods, pass <tt>instance_accessor: false</tt>.
  def mattr_accessor(*syms)
    mattr_reader(*syms)
    mattr_writer(*syms)
  end
end