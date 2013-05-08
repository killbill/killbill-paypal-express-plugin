[![Build Status](https://travis-ci.org/killbill/killbill-paypal-express-plugin.png)](https://travis-ci.org/killbill/killbill-paypal-express-plugin)
[![Code Climate](https://codeclimate.com/github/killbill/killbill-paypal-express-plugin.png)](https://codeclimate.com/github/killbill/killbill-paypal-express-plugin)

killbill-paypal-express-plugin
==============================

Plugin to use Express Checkout as a gateway.

Configuration
-------------

The plugin expects a `paypal_express.yml` configuration file containing the following:

```
:paypal:
  :signature: 'your-paypal-signature'
  :login: 'your-username-facilitator.something.com'
  :password: 'your-password'
  :log_file: '/var/tmp/paypal.log'
  # Switch to false for production
  :test: true

:database:
  :adapter: 'sqlite3'
  :database: 'test.db'
# For MySQL
#  :adapter: 'jdbc'
#  :username: 'your-username'
#  :password: 'your-password'
#  :driver: 'com.mysql.jdbc.Driver'
#  :url: 'jdbc:mysql://127.0.0.1:3306/your-database'
```

By default, the plugin will look at the plugin directory root (where `killbill.properties` is located) to find this file.
Alternatively, set the Kill Bill system property `-Dcom.ning.billing.osgi.bundles.jruby.conf.dir=/my/directory` to specify another location.
