require 'selenium-webdriver'

module Killbill
  module PaypalExpress
    module BrowserHelpers
      def login_and_confirm(url)
        if ENV['BUYER_USERNAME'].blank? || ENV['BUYER_PASSWORD'].blank?
          print "\nPlease go to #{url} to proceed and press any key to continue... Note: you need to log-in with a paypal sandbox account (create one here: https://developer.paypal.com/webapps/developer/applications/accounts)\n"
          $stdin.gets
        else
          driver = Selenium::WebDriver.for :firefox
          #login page
          driver.get url
          wait = Selenium::WebDriver::Wait.new(:timeout => 15)
          driver.switch_to.frame('injectedUl')
          email_element, pwd_element, login_element = wait.until {
            email_element = driver.find_element(:id, 'email')
            pwd_element = driver.find_element(:id, 'password')
            login_element = driver.find_element(:id, 'btnLogin')
            if email_element.displayed? && pwd_element.displayed? && login_element.displayed?
              [email_element, pwd_element, login_element]
            else
              #find the element id from old UI
              old_email_element = driver.find_element(:id, 'login_email')
              old_pwd_element = driver.find_element(:id, 'login_password')
              old_login_element = driver.find_element(:id, 'submitLogin')
              [old_email_element, old_pwd_element, old_login_element] if (old_email_element.displayed? && old_pwd_element.displayed? && old_login_element.displayed?)
            end
          }
          email_element.send_keys(ENV['BUYER_USERNAME'])
          pwd_element.send_keys(ENV['BUYER_PASSWORD'])
          login_element.click

          #confirmation page
          driver.switch_to.default_content
          confirm_element = wait.until {
            confirm_element = driver.find_element(:id, 'confirmButtonTop')
            if confirm_element.displayed? && confirm_element.enabled?
              confirm_element
            else
              old_confirm_element = driver.find_element(:id, 'continue_abovefold')
              old_confirm_element if old_confirm_element.displayed? && old_confirm_element.enabled?
            end
          }
          #wait for page to load. Even if it is displayed and enabled, sometimes the element is still not clickable.
          sleep 2
          confirm_element.click

          #quit
          driver.quit
        end
      end
    end
  end
end
