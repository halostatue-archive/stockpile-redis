require 'minitest_config'
require 'stockpile/redis'

describe Stockpile::Redis do
  def assert_clients expected_clients, connector
    actual_clients = connector.instance_variable_get(:@clients).keys
    assert_equal actual_clients.sort, expected_clients.sort
  end

  let(:rcm) { stub_env({}) { Stockpile::Redis.new } }
  let(:rcm_namespace) { stub_env({}) { Stockpile::Redis.new(namespace: 'Z') } }
  let(:rcm_wide) { stub_env({}) { Stockpile::Redis.new(narrow: false) } }
  let(:rcm_narrow) { stub_env({}) { Stockpile::Redis.new(narrow: true) } }

  describe 'constructor' do
    it "uses the default connection width by default" do
      stub ::Stockpile, :narrow?, lambda { false } do
        refute Stockpile::Redis.new.narrow?,
          "should be narrow, but is not"
      end

      stub ::Stockpile, :narrow?, lambda { true } do
        assert Stockpile::Redis.new.narrow?,
          "is not narrow, but should be"
      end
    end

    it "can be told which connection width to use explicitly" do
      stub ::Stockpile, :narrow?, lambda { false } do
        assert rcm_narrow.narrow?
      end

      stub ::Stockpile, :narrow?, lambda { true } do
        refute rcm_wide.narrow?
      end
    end

    it "passes settings through to Redis" do
      options = {
        redis: {
          url: 'redis://xyz/'
        }
      }
      rcm = ::Stockpile::Redis.new(options)
      assert_equal 'xyz', rcm.connect.client.options[:host]
    end

    it "has no clients by default" do
      assert_clients [], ::Stockpile::Redis.new
    end

    describe "namespace support" do
      def assert_namespace(client)
        assert_equal 'stockpile', client.instance_variable_get(:@namespace)
      end

      it "will set namespace from ENV['REDIS_NAMESPACE']" do
        stub_env({ 'REDIS_NAMESPACE' => 'stockpile' }) do
          assert_namespace ::Stockpile::Redis.new
        end
      end

      it "will set namespace from Rails.env" do
        begin
          ::Rails = Class.new do
            def self.env
              'stockpile'
            end
          end

          stub_env({}) do
            assert_namespace ::Stockpile::Redis.new
          end
        ensure
          Object.send(:remove_const, :Rails)
        end
      end

      it "will set namespace from ENV['RACK_ENV']" do
        stub_env({ 'RACK_ENV' => 'stockpile' }) do
          assert_namespace ::Stockpile::Redis.new
        end
      end

      it "will set namespace from parameters" do
        stub_env({ 'RACK_ENV' => 'test' }) do
          assert_namespace ::Stockpile::Redis.new(namespace: 'stockpile')
        end
      end
    end
  end

  describe "#connect" do
    it "creates a connection to Redis" do
      assert_nil rcm.connection
      refute_nil rcm.connect
      assert_kind_of ::Redis, rcm.connection
    end

    it "creates a namespaced connection to Redis" do
      assert_nil rcm_namespace.connection
      refute_nil rcm_namespace.connect
      assert_kind_of ::Redis::Namespace, rcm_namespace.connection
    end

    describe "with a wide connection width" do
      before do
        rcm_wide.connect(:redis, rollout: { namespace: 'rollout' })
      end

      it "connects multiple clients" do
        assert_clients [ :redis, :rollout ], rcm_wide
      end

      it "creates a Redis::Namespace for rollout" do
        assert_kind_of Redis::Namespace, rcm_wide.connection_for(:rollout)
      end

      it "connects *different* clients" do
        refute_same rcm_wide.connection, rcm_wide.connection_for(:redis)
        refute_same rcm_wide.connection, rcm_wide.connection_for(:rollout)
        refute_same rcm_wide.connection_for(:redis), rcm_wide.connection_for(:rollout)
      end
    end

    describe "with a narrow connection width" do
      before do
        rcm_narrow.connect(:redis, rollout: { namespace: 'rollout' })
      end

      it "appears to connect multiple clients" do
        assert_clients [ :redis, :rollout ], rcm_narrow
      end

      it "creates a Redis::Namespace for rollout" do
        assert_kind_of Redis::Namespace, rcm_narrow.connection_for(:rollout)
      end

      it "returns identical clients" do
        assert_same rcm_narrow.connection, rcm_narrow.connection_for(:redis)
        refute_same rcm_narrow.connection, rcm_narrow.connection_for(:rollout)
        assert_same rcm_narrow.connection,
          rcm_narrow.connection_for(:rollout).redis
        refute_same rcm_narrow.connection_for(:redis), rcm_narrow.connection_for(:rollout)
        assert_same rcm_narrow.connection_for(:redis),
          rcm_narrow.connection_for(:rollout).redis
      end
    end
  end

  describe "#connection_for" do
    describe "with a wide connection width" do
      it "connects the main client" do
        rcm_wide.connection_for(:global)
        assert rcm_wide.connection
        refute_same rcm_wide.connection, rcm_wide.connection_for(:global)
      end

      it "wraps a :resque client in Redis::Namespace" do
        assert_kind_of Redis::Namespace, rcm_wide.connection_for(:resque)
        assert_equal "resque", rcm_wide.connection_for(:resque).namespace
      end
    end

    describe "with a narrow connection width" do
      it "connects the main client" do
        rcm_narrow.connection_for(:global)
        assert rcm_narrow.connection
        assert_same rcm_narrow.connection, rcm_narrow.connection_for(:global)
      end

      it "wraps a :resque client in Redis::Namespace" do
        assert_kind_of Redis::Namespace, rcm_narrow.connection_for(:resque)
      end
    end
  end

  # #disconnect cannot be tested with FakeRedis because the FakeRedis
  # #connected? method always returns true.
  describe "#disconnect" do
    describe "with a wide connection width" do
      let(:global) { rcm_wide.connection }
      let(:redis) { rcm_wide.connection_for(:redis) }

      def force_connection
        rcm_wide.connect(:redis)
        global.client.connect
        redis.client.connect
      end

      it "disconnects the global client" do
        instance_stub Redis, :quit do
          force_connection
          rcm_wide.disconnect
        end
        assert_instance_called Redis, :quit, 1
      end

      it "disconnects the redis and global clients" do
        instance_stub Redis, :quit do
          force_connection
          rcm_wide.disconnect(:redis)
        end
        assert_instance_called Redis, :quit, 2
      end
    end

    describe "with a narrow connection width" do
      let(:global) { rcm_narrow.connection }
      let(:redis) { rcm_narrow.connection_for(:redis) }

      def force_connection
        rcm_narrow.connect(:redis)
        global.client.connect
        redis.client.connect
      end

      it "disconnects the global client" do
        instance_stub Redis, :quit do
          force_connection
          rcm_narrow.disconnect
        end
        assert_instance_called Redis, :quit, 1
      end

      it "disconnects the redis and global clients" do
        instance_stub Redis, :quit do
          force_connection
          rcm_narrow.disconnect(:redis)
        end
        assert_instance_called Redis, :quit, 1
      end
    end
  end

  # #reconnect cannot be tested with FakeRedis because the FakeRedis
  # #connected? method always returns true.
  describe "#reconnect" do
    describe "with a wide connection width" do
      let(:global) { rcm_wide.connection }
      let(:redis) { rcm_wide.connection_for(:redis) }

      def force_connection
        rcm_wide.connect(:redis)
        global.client.connect
        redis.client.connect
      end

      it "reconnects the global client" do
        instance_stub Redis::Client, :reconnect do
          force_connection
          rcm_wide.reconnect
        end
        assert_instance_called Redis::Client, :reconnect, 1
      end

      it "reconnects the redis and global clients" do
        instance_stub Redis::Client, :reconnect do
          force_connection
          rcm_wide.reconnect(:redis)
        end
        assert_instance_called Redis::Client, :reconnect, 2
      end
    end

    describe "with a narrow connection width" do
      let(:global) { rcm_narrow.connection }
      let(:redis) { rcm_narrow.connection_for(:redis) }

      def force_connection
        rcm_narrow.connect(:redis)
        global.client.connect
        redis.client.connect
      end

      it "reconnects the global client" do
        instance_stub Redis::Client, :reconnect do
          force_connection
          rcm_narrow.reconnect
        end
        assert_instance_called Redis::Client, :reconnect, 1
      end

      it "reconnects the redis and global clients" do
        instance_stub Redis::Client, :reconnect do
          force_connection
          rcm_narrow.reconnect(:redis)
        end
        assert_instance_called Redis::Client, :reconnect, 1
      end
    end
  end
end
