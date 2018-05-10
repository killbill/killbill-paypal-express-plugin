require 'selenium-webdriver'

module Killbill
  module PaypalExpress
    module BrowserHelpers
      def login_and_confirm(url)
        if ENV['BUYER_USERNAME'].blank? || ENV['BUYER_PASSWORD'].blank?
          print "\nPlease go to #{url} to proceed and press any key to continue... Note: you need to log-in with a paypal sandbox account (create one here: https://developer.paypal.com/webapps/developer/applications/accounts)\n"
          $stdin.gets
        else
          debug = !(ENV['SELENIUM_DEBUG'].blank?)
          $DEBUG = true if debug

          if ENV['SELENIUM_URL'].blank?
            driver = Selenium::WebDriver.for :firefox
          else
            driver = Selenium::WebDriver.for :remote, :url => ENV['SELENIUM_URL'], :desired_capabilities => :firefox
          end
          # Login page
          driver.get url

          # PayPal... :'-(
          sandbox_ui_version = 0

          wait = Selenium::WebDriver::Wait.new(:timeout => 45)
          begin
            wait.until {
              driver.switch_to.frame('injectedUl') rescue nil
            }
          rescue Selenium::WebDriver::Error::TimeOutError => e
            sandbox_ui_version = 3
          end

          driver.save_screenshot('landing.png') if debug

          if sandbox_ui_version < 3
            email_element, pwd_element, login_element = wait.until {
              email_element = driver.find_element(:id, 'email') rescue nil
              pwd_element = driver.find_element(:id, 'password') rescue nil
              login_element = driver.find_element(:id, 'btnLogin') rescue nil
              if ready?(email_element, pwd_element, login_element)
                sandbox_ui_version = 2
                [email_element, pwd_element, login_element]
              else
                # Find the element ids from the old old UI
                old_email_element = driver.find_element(:id, 'login_email') rescue nil
                old_pwd_element = driver.find_element(:id, 'login_password') rescue nil
                old_login_element = driver.find_element(:id, 'submitLogin') rescue nil
                if ready?(old_email_element, old_pwd_element, old_login_element)
                  sandbox_ui_version = 1
                  [old_email_element, old_pwd_element, old_login_element]
                else
                  false
                end
              end
            }
            email_element.send_keys(ENV['BUYER_USERNAME'])
            pwd_element.send_keys(ENV['BUYER_PASSWORD'])
            login_element.click
          else
            email_element = wait.until {
              email_element = driver.find_element(:id, 'email') rescue nil
              ready?(email_element) ? email_element : false
            }

            begin
              next_element = wait.until {
                next_element = driver.find_element(:id, 'btnNext') rescue nil
                ready?(next_element) ? next_element : false
              }
            rescue Error::TimeOutError
              # Ignore - in the new version, password is not always on a separate page
              sandbox_ui_version = 4
            end

            email_element.send_keys(ENV['BUYER_USERNAME'])

            next_element.click unless next_element.nil?

            pwd_element, login_element = wait.until {
              pwd_element = driver.find_element(:id, 'password') rescue nil
              login_element = driver.find_element(:id, 'btnLogin') rescue nil
              if ready?(pwd_element, login_element)
                [pwd_element, login_element]
              else
                false
              end
            }
            pwd_element.send_keys(ENV['BUYER_PASSWORD'])
            driver.save_screenshot('confirmation.png') if debug

            login_element.click
          end

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
          driver.save_screenshot('confirmed.png') if debug

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
