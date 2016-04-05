# frozen_string_literal: true
# coding: utf-8

require 'redis'
require 'redis/namespace'
require 'stockpile/base'

class Stockpile
  # A connection manager for Redis.
  class Redis < Stockpile::Base
    VERSION = '2.0' # :nodoc:

    # Create a new Redis connection manager with the provided options.
    #
    # == Options
    #
    # +redis+::     Provides the Redis connection options.
    # +namespace+:: Provides the Redis namespace to use, but only if
    #               redis-namespace is in use (detected with the existence of
    #               Redis::Namespace).
    #
    #               The namespace can also be provided as a key in the +redis+
    #               options if it is missing from the main options. If there is
    #               no namespace key present in either +options+ or
    #               <tt>options[:redis]</tt>, a namespace will be generated
    #               from one of the following: <tt>$REDIS_NAMESPACE</tt>,
    #               <tt>Rails.env</tt> (if in Rails), or <tt>$RACK_ENV</tt>.
    def initialize(options = {})
      super

      @redis_options = (@options.delete(:redis) || {}).dup
      @redis_options = @redis_options.to_h unless @redis_options.kind_of?(Hash)
      @namespace     = @options.fetch(:namespace) {
        @redis_options.fetch(:namespace) {
          ENV['REDIS_NAMESPACE'] || ENV['RAILS_ENV'] || ENV['RACK_ENV']
        }
      }

      @options.delete(:namespace)
      @redis_options.delete(:namespace)
    end

    ##
    # Connect to Redis, unless already connected. Additional client connections
    # can be specified in the parameters as a shorthand for calls to
    # #connection_for.
    #
    # If #narrow? is true, the same Redis connection will be used for all
    # clients managed by this connection manager.
    #
    #   manager.connect
    #   manager.connection_for(:redis)
    #
    #   # This means the same as above.
    #   manager.connect(:redis)
    #
    # === Clients
    #
    # +clients+ may be provided in one of several ways:
    #
    # * A Hash object, mapping client names to client options.
    #
    #     connect(redis: nil, rollout: { namespace: 'rollout' })
    #     # Transforms into:
    #     # connect(redis: {}, rollout: { namespace: 'rollout' })
    #
    # * An (implicit) array of client names, for connections with no options
    #   provided.
    #
    #     connect(:redis, :resque, :rollout)
    #     # Transforms into:
    #     # connect(redis: {}, resque: {}, rollout: {})
    #
    # * An array of Hash objects, mapping client names to client options.
    #
    #     connect({ redis: nil },
    #             { rollout: { namespace: 'rollout' } })
    #     # Transforms into:
    #     # connect(redis: {}, rollout: { namespace: 'rollout' })
    #
    # * A mix of client names and Hash objects:
    #
    #     connect(:redis, { rollout: { namespace: 'rollout' } })
    #     # Transforms into:
    #     # connect(redis: {}, rollout: { namespace: 'rollout' })
    #
    # ==== Client Options
    #
    # Stockpile::Redis supports one option, +namespace+. The use of this with a
    # client automatically wraps the client in the provided +namespace+. The
    # namespace will be within the global namespace for the Stockpile::Redis
    # instance, if one has been set.
    #
    #   r = Stockpile::Redis.new(namespace: 'first')
    #   rr = r.client_for(other: { namespace: 'second' })
    #   rr.set 'found', true
    #   r.set 'found', true
    #   rr.keys # => [ 'found' ]
    #   r.keys # => [ 'found', 'second:found' ]
    #   r.connection.redis.keys # => [ 'first:found', 'first:second:found' ]
    #
    # :method: connect

    ##
    # Returns a Redis client connection for a particular client. If the
    # connection manager is using a narrow connection width, this returns the
    # same as #connection.
    #
    # The +client_name+ of +:all+ will always return +nil+.
    #
    # If the requested client does not yet exist, the connection will be
    # created with the provided options.
    #
    # Because Resque depends on Redis::Namespace, #connection_for will perform
    # special Redis::Namespace handling for a connection with the name
    # +:resque+.
    #
    # :method: connection_for

    ##
    # Reconnect to Redis for some or all clients. The primary connection will
    # always be reconnected; other clients will be reconnected based on the
    # +clients+ provided. Only clients actively managed by previous calls to
    # #connect or #connection_for will be reconnected.
    #
    # If #reconnect is called with the value +:all+, all currently managed
    # clients will be reconnected. If #narrow? is true, the primary connection
    # will be reconnected.
    #
    # :method: reconnect

    ##
    # Disconnect from Redis for some or all clients. The primary connection
    # will always be disconnected; other clients will be disconnected based on
    # the +clients+ provided. Only clients actively managed by previous calls
    # to #connect or #connection_for will be disconnected.
    #
    # If #disconnect is called with the value +:all+, all currently managed
    # clients will be disconnected. If #narrow? is true, the primary connection
    # will be disconnected.
    #
    # :method: disconnect

    private

    def client_connect(name = nil, options = {})
      options = { namespace: options[:namespace] }

      case name
      when :resque
        connect_for_resque(options)
      else
        connect_for_any(options)
      end
    end

    def client_reconnect(redis = connection)
      redis.client.reconnect if redis
    end

    def client_disconnect(redis = connection)
      redis.quit if redis
    end

    def connect_for_any(options)
      r = if connection && narrow?
            connection
          else
            r = ::Redis.new(@redis_options.merge(options))

            if @namespace
              ::Redis::Namespace.new(@namespace, redis: r)
            else
              r
            end
          end

      if options[:namespace]
        r = ::Redis::Namespace.new(options[:namespace], redis: r)
      end

      r
    end

    def connect_for_resque(options)
      r = connect_for_any(options)

      if r.instance_of?(::Redis::Namespace) && r.namespace.to_s !~ /:resque\z/
        r = ::Redis::Namespace.new(:"#{r.namespace}:resque", redis: r.redis)
      elsif r.instance_of?(::Redis)
        r = ::Redis::Namespace.new('resque', redis: r)
      end

      r
    end
  end

  # Enables module or class +mod+ to contain a Stockpile instance that defaults
  # the created +cache+ method to using Stockpile::Redis as the key-value store
  # connection manager.
  #
  # See <tt>Stockpile.inject!</tt>.
  def self.inject_redis!(mod, options = {})
    inject!(mod, options.merge(default_manager: Stockpile::Redis))
  end
end
