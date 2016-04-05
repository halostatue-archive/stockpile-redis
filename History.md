### 2.0 / 2016-04-04

*   1 major change

    *   Dropped support for Ruby 1.9

*   1 minor change

    *   Changed Rails environment support from looking for Rails.env to
        RAILS_ENV.

*   1 bugfix

    *   Fix [issue #1][]. OpenStruct is now supported for Stockpile options.

*   1 governance change:

    *   Stockpile::Redis is under the Contributer Covenant Code of Conduct.

*   Miscellaneous

    *   Added Rubocop.

### 1.1 / 2015-02-10

* 2 minor enhancements

  * Modified Stockpile::Redis to be implemented based on the new
    Stockpile::Base class provided in stockpile 1.1.

  * Implemented the +namespace+ option for client connections to add additional
    namespace support to individual child connections.

### 1.0 / 2015-01-21

* 1 major enhancement

  * Birthday!

[issue #1]: https://github.com/halostatue/stockpile-redis/issues/1
