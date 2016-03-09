killbill-paypal-express-plugin
==============================

Plugin to use [PayPal Express Checkout](https://www.paypal.com/webapps/mpp/express-checkout) as a gateway.

Release builds are available on [Maven Central](http://search.maven.org/#search%7Cga%7C1%7Cg%3A%22org.kill-bill.billing.plugin.ruby%22%20AND%20a%3A%22paypal-express-plugin%22) with coordinates `org.kill-bill.billing.plugin.ruby:paypal-express-plugin`.

Kill Bill compatibility
-----------------------

| Plugin version | Kill Bill version |
| -------------: | ----------------: |
| 2.x.y          | 0.14.z            |
| 3.x.y          | 0.15.z            |
| 4.x.y          | 0.16.z            |

Requirements
------------

The plugin needs a database. The latest version of the schema can be found [here](https://github.com/killbill/killbill-paypal-express-plugin/blob/master/db/ddl.sql).

Configuration
-------------

```
curl -v \
     -X POST \
     -u admin:password \
     -H 'X-Killbill-ApiKey: bob' \
     -H 'X-Killbill-ApiSecret: lazar' \
     -H 'X-Killbill-CreatedBy: admin' \
     -H 'Content-Type: text/plain' \
     -d ':paypal_express:
  :signature: "your-paypal-signature"
  :login: "your-username-facilitator.something.com"
  :password: "your-password"' \
     http://127.0.0.1:8080/1.0/kb/tenants/uploadPluginConfig/killbill-paypal-express
```

To go to production, create a `paypal_express.yml` configuration file under `/var/tmp/bundles/plugins/ruby/killbill-paypal-express/x.y.z/` containing the following:

```
:paypal_express:
  :test: false
```

Usage
-----

### One-off payments

Create a payment method for the account:

```
curl -v \
     -X POST \
     -u admin:password \
     -H 'X-Killbill-ApiKey: bob' \
     -H 'X-Killbill-ApiSecret: lazar' \
     -H 'X-Killbill-CreatedBy: admin' \
     -H 'Content-Type: application/json' \
     -d '{
       "pluginName": "killbill-paypal-express",
       "pluginInfo": {}
     }' \
     "http://127.0.0.1:8080/1.0/kb/accounts/<ACCOUNT_ID>/paymentMethods?isDefault=true"
```

#### Without a pending payment

Generate the redirect URL using buildFormDescriptor (this will invoke `SetExpressCheckout`):

```
curl -v \
     -X POST \
     -u admin:password \
     -H 'X-Killbill-ApiKey: bob' \
     -H 'X-Killbill-ApiSecret: lazar' \
     -H 'X-Killbill-CreatedBy: admin' \
     -H 'Content-Type: application/json' \
     -d '{
       "formFields": [{
         "key": "amount",
         "value": 10
       },{
         "key": "currency",
         "value": "USD"
       }]
     }' \
     "http://127.0.0.1:8080/1.0/kb/paymentGateways/hosted/form/<ACCOUNT_ID>"
```

The customer should be redirected to the url specified in the `formUrl` entry of the response, e.g. https://www.paypal.com/cgi-bin/webscr?cmd=_express-checkout&token=EC-20G53990M6953444J.

Once the customer comes back from the PayPal flow, trigger the payment:

```
curl -v \
     -X POST \
     -u admin:password \
     -H 'X-Killbill-ApiKey: bob' \
     -H 'X-Killbill-ApiSecret: lazar' \
     -H 'X-Killbill-CreatedBy: admin' \
     -H 'Content-Type: application/json' \
     -d '{
       "transactionType": "PURCHASE",
       "amount": "10",
       "currency": "USD"
     }' \
     "http://127.0.0.1:8080/1.0/kb/accounts/<ACCOUNT_ID>/payments"
```

#### With a pending payment

Generate the redirect URL using buildFormDescriptor (this will invoke `SetExpressCheckout`):

```
curl -v \
     -X POST \
     -u admin:password \
     -H 'X-Killbill-ApiKey: bob' \
     -H 'X-Killbill-ApiSecret: lazar' \
     -H 'X-Killbill-CreatedBy: admin' \
     -H 'Content-Type: application/json' \
     -d '{
       "formFields": [{
         "key": "amount",
         "value": 10
       },{
         "key": "currency",
         "value": "USD"
       }]
     }' \
     "http://127.0.0.1:8080/1.0/kb/paymentGateways/hosted/form/<ACCOUNT_ID>?pluginProperty=create_pending_payment=true"
```

The customer should be redirected to the url specified in the `formUrl` entry of the response, e.g. https://www.paypal.com/cgi-bin/webscr?cmd=_express-checkout&token=EC-20G53990M6953444J.

Once the customer comes back from the PayPal flow, complete the payment (the payment id and external key are returned as part of the buildFormDescriptor call):

```
curl -v \
     -X PUT \
     -u admin:password \
     -H 'X-Killbill-ApiKey: bob' \
     -H 'X-Killbill-ApiSecret: lazar' \
     -H 'X-Killbill-CreatedBy: admin' \
     -H 'Content-Type: application/json' \
     "http://127.0.0.1:8080/1.0/kb/payments/<PAYMENT_ID>"
```

### Recurring payments via a billing agreement ID (BAID)

Issue the following call to generate a Paypal token:

```
curl -v \
     -X POST \
     -u admin:password \
     -H 'X-Killbill-ApiKey: bob' \
     -H 'X-Killbill-ApiSecret: lazar' \
     -H 'X-Killbill-CreatedBy: admin' \
     -H 'Content-Type: application/json' \
     -d '{
       "kb_account_id": "13d26090-b8d7-11e2-9e96-0800200c9a66",
       "currency": "USD",
       "options": {
         "return_url": "http://www.google.com/?q=SUCCESS",
         "cancel_return_url": "http://www.google.com/?q=FAILURE",
         "billing_agreement": {
           "description": "Your subscription"
         }
       }
     }' \
     http://127.0.0.1:8080/plugins/killbill-paypal-express/1.0/setup-checkout
```

Kill Bill will return a 302 Found on success. The customer should be redirected to the url specified in the Location header, e.g. https://www.paypal.com/cgi-bin/webscr?cmd=_express-checkout&token=EC-20G53990M6953444J.

Once the customer comes back from the PayPal flow, save the BAID in Kill Bill:

```
curl -v \
     -X POST \
     -u admin:password \
     -H 'X-Killbill-ApiKey: bob' \
     -H 'X-Killbill-ApiSecret: lazar' \
     -H 'X-Killbill-CreatedBy: admin' \
     -H 'Content-Type: application/json' \
     -d '{
       "pluginName": "killbill-paypal-express",
       "pluginInfo": {
         "properties": [{
           "key": "token",
           "value": "20G53990M6953444J"
         }]
       }
     }' \
     "http://127.0.0.1:8080/1.0/kb/accounts/13d26090-b8d7-11e2-9e96-0800200c9a66/paymentMethods?isDefault=true"
```

Plugin properties
-----------------

| Key                          | Description                                                       |
| ---------------------------: | ----------------------------------------------------------------- |
| skip_gw                      | If true, skip the call to PayPal                                  |
| token                        | PayPal token to use                                               |
| payer_id                     | PayPal Payer id to use                                            |
| create_pending_payment       | Create pending payment during buildFormDescriptor call            |
| payment_processor_account_id | Config entry name of the merchant account to use                  |
| external_key_as_order_id     | If true, set the payment external key as the PayPal order id      |
| email                        | Purchaser email                                                   |
| address1                     | Billing address first line                                        |
| address2                     | Billing address second line                                       |
| city                         | Billing address city                                              |
| zip                          | Billing address zip code                                          |
| state                        | Billing address state                                             |
| country                      | Billing address country                                           |
| max_amount                   | Maximum amount parameter (optional) for SetExpressCheckout call   |