killbill-paypal-express-plugin
==============================

Plugin to use [PayPal Express Checkout](https://www.paypal.com/webapps/mpp/express-checkout) as a gateway.

Release builds are available on [Maven Central](http://search.maven.org/#search%7Cga%7C1%7Cg%3A%22org.kill-bill.billing.plugin.ruby%22%20AND%20a%3A%22paypal-express-plugin%22) with coordinates `org.kill-bill.billing.plugin.ruby:paypal-express-plugin`.

Kill Bill compatibility
-----------------------

| Plugin version | Kill Bill version |
| -------------: | ----------------: |
| 2.x.y          | 0.14.z            |
| 4.x.y          | 0.16.z            |
| 5.x.y          | 0.18.z            |

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

Below is a list of optional parameters for build_form_descriptor call. More details can be found on PayPal [manual](https://developer.paypal.com/docs/classic/api/merchant/SetExpressCheckout_API_Operation_SOAP/)

| Key                          | Description                                                       |
| ---------------------------: | ----------------------------------------------------------------- |
| max_amount                   | Maximum amount parameter                                          |
| auth_mode                    | If true, [Authorization Payment Action](https://developer.paypal.com/docs/classic/express-checkout/integration-guide/ECRelatedAPIOps/) is adopted. Otherwise, Sale Payment Action is used.|
| no_shipping                  | Whether or not to show shipping address on PayPal checkout page   |
| req_billing_address           | Is 1 or 0. The value 1 indicates that you require that the buyer’s billing address on file with PayPal be returned. Setting this element will return `BILLTONAME`, `STREET`, `STREET2`, `CITY`, `STATE`, `ZIP`, and `COUNTRYCODE`. |
| address_override             | Determines whether or not the PayPal pages should display the shipping address set by you in this SetExpressCheckout request, not the shipping address on file with PayPal for this buyer.|
| locale                       | Locale of pages displayed by PayPal during Express Checkout. It is either a two-letter country code or five-character locale code supported by PayPal. |
| brand_name                   | A label that overrides the business name in the PayPal account on the PayPal hosted checkout pages.|
| page_style                   | Name of the Custom Payment Page Style for payment pages associated with this button or link. It corresponds to the HTML variable page_style for customizing payment pages. |
| logo_image                   | A URL to your logo image. Use a valid graphics format, such as .gif, .jpg, or .png. Limit the image to 190 pixels wide by 60 pixels high. |
| header_image                 | URL for the image you want to appear at the top left of the payment page. The image has a maximum size of 750 pixels wide by 90 pixels high. |
| header_border_color          | Sets the border color around the header of the payment page. The border is a 2-pixel perimeter around the header space, which is 750 pixels wide by 90 pixels high. By default, the color is black. |
| header_background_color      | Sets the background color for the header of the payment page. By default, the color is white. |
| background_color             | Sets the background color for the payment page. By default, the color is white.|
| allow_guest_checkout         | If set to true, then the SolutionType is Sole and buyer does not need to create a PayPal account to check out. |
| landing_page                 | Type of PayPal page to display. It is one of the following values: Billing for Non-PayPal account and Login — PayPal account login. |
| email                        | Email address of the buyer as entered during checkout. PayPal uses this value to pre-fill the PayPal membership sign-up portion on the PayPal pages. |
| allow_note                   | Enables the buyer to enter a note to the merchant on the PayPal page during checkout.|
| callback_url                 | URL to which the callback request from PayPal is sent. It must start with HTTPS for production integration. |
| callback_timeout             | An override for you to request more or less time to be able to process the callback request and respond. |
| allow_buyer_optin            | Enables the buyer to provide their email address on the PayPal pages to be notified of promotions or special events. |
| shipping_address             | Address to which the order is shipped. This parameter must be a JSON Hash with keys of `name`, `address1`, `address2`, `state`, `city`, `country`, `phone`, `zip` and `phone`. |
| address                      | Address to which the order is shipped if shipping_address is not set. This parameter must be a JSON Hash with keys of `name`, `address1`, `address2`, `state`, `city`, `country`, `phone`, `zip` and `phone`. |
| total_type                   | Type declaration for the label to be displayed in MiniCart for UX. It is one of the following values: Total or EstimatedTotal. |
| funding_sources              | This parameter must be in a JSON hash format with a key being `source`. This element could be used to specify the preferred funding option for a guest user. However, the `landing_page` element must also be set to `Billing`. Otherwise, it is ignored.|
| shipping_options             | This parameter must be in a JSON hash format with keys of `default`, `amount`, and `name`. This corresponds to the `ShippingOptionsType` in the SetupExpressCheckout call. |
| subtotal                     | Sum of cost of all items in this order. For digital goods, this field is required. |
| shipping                     | Total shipping costs for this order.                               |
| handling                     | Total handling costs for this order.                               |
| tax                          | Sum of tax for all items in this order.                            |
| insurance_total              | Total shipping insurance costs for this order. The value must be a non-negative currency amount or null if you offer insurance options. |
| shipping_discount            | Shipping discount for this order, specified as a negative number.  |
| insurance_option_offered     | Indicates whether insurance is available as an option the buyer can choose on the PayPal Review page. |
| description                  | Description of items the buyer is purchasing.                      |
| custom                       | A free-form field for your own use.                                |
| order_id                     | Your own invoice or tracking number.                               |
| invoice_id                   | Your own invoice or tracking number. This will be overridden by order_id. |
| notify_url                   | Your URL for receiving Instant Payment Notification (IPN) about this transaction. If you do not specify this value in the request, the notification URL from your Merchant Profile is used, if one exists.|
| items                        | This parameter must be a JSON Array that contains a list of Hashes with keys of `name`, `number`, `quantity`, `amount`, `description`, `url` and `category`. |
