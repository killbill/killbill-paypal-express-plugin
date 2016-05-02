require 'selenium-webdriver'

module Killbill
  module PaypalExpress
    module BrowserHelpers
      def login_and_confirm(url)
        driver = Selenium::WebDriver.for :firefox
        #login page
        driver.get url
        wait = Selenium::WebDriver::Wait.new(:timeout => 15)
        driver.switch_to.frame('injectedUl')
        email_element, pwd_element, login_element = wait.until {
          email_element = driver.find_element(:id, 'email')
          pwd_element = driver.find_element(:id, 'password')
          login_element = driver.find_element(:id, 'btnLogin')
          [email_element, pwd_element, login_element] if (email_element.displayed? && pwd_element.displayed? && login_element.displayed?)
        }
        email_element.send_keys(buyer_info[:username])
        pwd_element.send_keys(buyer_info[:password])
        login_element.click

        #confirmation page
        driver.switch_to.default_content
        confirm_element = wait.until {
          confirm_element = driver.find_element(:id, 'confirmButtonTop')
          confirm_element if confirm_element.displayed? && confirm_element.enabled?
        }
        #wait for page to load. Even if it is displayed and enabled, sometimes the element is still not clickable.
        sleep 2
        confirm_element.click

        #quit
        driver.quit
      end

      def get_buyer_info
         YAML.load_file('paypal_express.yml')[:paypal_buyer]
      end
    end
  end
end
