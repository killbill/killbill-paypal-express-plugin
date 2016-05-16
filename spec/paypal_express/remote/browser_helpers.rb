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
          # Login page
          driver.get url

          wait = Selenium::WebDriver::Wait.new(:timeout => 15)
          wait.until {
            driver.switch_to.frame('injectedUl') rescue nil
          }

          email_element, pwd_element, login_element = wait.until {
            email_element = driver.find_element(:id, 'email') rescue nil
            pwd_element = driver.find_element(:id, 'password') rescue nil
            login_element = driver.find_element(:id, 'btnLogin') rescue nil
            if ready?(email_element, pwd_element, login_element)
              [email_element, pwd_element, login_element]
            else
              # Find the element ids from the old UI
              old_email_element = driver.find_element(:id, 'login_email') rescue nil
              old_pwd_element = driver.find_element(:id, 'login_password') rescue nil
              old_login_element = driver.find_element(:id, 'submitLogin') rescue nil
              if ready?(old_email_element, old_pwd_element, old_login_element)
                [old_email_element, old_pwd_element, old_login_element]
              else
                false
              end
            end
          }
          email_element.send_keys(ENV['BUYER_USERNAME'])
          pwd_element.send_keys(ENV['BUYER_PASSWORD'])
          login_element.click

          # Confirmation page
          driver.switch_to.default_content
          confirm_element = wait.until {
            confirm_element = driver.find_element(:id, 'confirmButtonTop') rescue nil
            if ready?(confirm_element)
              confirm_element
            else
              old_confirm_element = driver.find_element(:id, 'continue_abovefold') rescue nil
              ready?(old_confirm_element) ? old_confirm_element : false
            end
          }

          # Wait for page to load. Even if it is displayed and enabled, sometimes the element is still not clickable.
          sleep 2
          confirm_element.click

          driver.quit
        end
      end

      private

      def ready?(*elements)
        elements.each do |element|
          return false unless element && element.displayed? && element.enabled?
        end
        true
      end
    end
  end
end
