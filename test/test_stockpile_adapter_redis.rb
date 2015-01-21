require 'minitest_config'
require 'stockpile/redis'
require 'time'

describe Stockpile do
  describe ".inject!" do
    let(:mod) { Module.new }
    let(:lrt) {
      Module.new do
        def last_run_time(key, value = nil)
          if value
            connection.hset(__method__, key, value.utc.iso8601)
          else
            value = connection.hget(__method__, key)
            Time.parse(value) if value
          end
        end
      end
    }

    describe "Mod.cache_adapter" do
      let(:now) { Time.now }
      before { ::Stockpile.inject_redis!(mod, adaptable: true) }

      it "adapts the cache with last_run_time" do
        mod.cache_adapter(lrt)
        assert_nil mod.cache.last_run_time('foo')
        assert_equal true, mod.cache.last_run_time('foo', now)
        assert_equal now.to_i, mod.cache.last_run_time('foo').to_i
      end

      it "adapts the module with last_run_time" do
        mod.cache_adapter(lrt, mod)
        assert_nil mod.last_run_time('foo')
        assert_equal true, mod.last_run_time('foo', now)
        assert_equal now.to_i, mod.last_run_time('foo').to_i
      end

      it "adapts the lrt module with last_run_time" do
        mod.cache_adapter!(lrt)
        assert_nil lrt.last_run_time('foo')
        assert_equal true, lrt.last_run_time('foo', now)
        assert_equal now.to_i, lrt.last_run_time('foo').to_i
      end
    end
  end
end
